/**
 * Software-only simulation of the scalar tracking loop
 * Tests the loop filter with synthetic I&D data (no hardware needed)
 */

#define _POSIX_C_SOURCE 200809L
#define _GNU_SOURCE

#include<stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <math.h>
#include <string.h>
#include "loop_filter.h"

/* Simulation parameters */
#define SIM_DURATION_MS     1000        /* 1 second of tracking */
#define TRUE_DOPPLER_HZ     1250.0      /* True satellite Doppler */
#define INIT_DOPPLER_HZ     1255.0      /* Initial estimate (5 Hz offset) */
#define TRUE_CODE_PHASE     347.0       /* True code phase (chips) */
#define NOISE_STD_DEV       5000.0      /* Thermal noise on I&D */
#define SIGNAL_AMPLITUDE    5000000.0   /* Expected I_P amplitude when locked */

/* Simple Gaussian noise generator (Box-Muller) */
double gaussian_noise(double std_dev) {
    static int has_spare = 0;
    static double spare;
    if (has_spare) {
        has_spare = 0;
        return std_dev * spare;
    }
    double u, v, s;
    do {
        u = (rand() / (RAND_MAX + 1.0)) * 2.0 - 1.0;
        v = (rand() / (RAND_MAX + 1.0)) * 2.0 - 1.0;
        s = u * u + v * v;
    } while (s >= 1.0 || s == 0.0);
    s = sqrt(-2.0 * log(s) / s);
    spare = v * s;
    has_spare = 1;
    return std_dev * u * s;
}

/* Generate synthetic I&D dumps for one epoch */
void generate_synthetic_dumps(
    int epoch,
    double true_doppler,
    double est_doppler,
    double *I_E, double *Q_E,
    int32_t *I_P, int32_t *Q_P,
    double *I_L, double *Q_L
) {
    /* Phase error = true - estimated */
    double phase_err_rad = 2 * M_PI * (true_doppler - est_doppler) * EPOCH_PERIOD_S * epoch;
    
    /* Prompt correlator (locked case: I_P large, Q_P small) */
    double signal_I = SIGNAL_AMPLITUDE * cos(phase_err_rad);
    double signal_Q = SIGNAL_AMPLITUDE * sin(phase_err_rad);
    
    *I_P = (int32_t)(signal_I + gaussian_noise(NOISE_STD_DEV));
    *Q_P = (int32_t)(signal_Q + gaussian_noise(NOISE_STD_DEV));
    
    /* Early/Late for DLL (assume perfect code lock for simplicity) */
    *I_E = SIGNAL_AMPLITUDE * 0.9 + gaussian_noise(NOISE_STD_DEV);
    *Q_E = gaussian_noise(NOISE_STD_DEV);
    *I_L = SIGNAL_AMPLITUDE * 0.9 + gaussian_noise(NOISE_STD_DEV);
    *Q_L = gaussian_noise(NOISE_STD_DEV);
}

int main() {
    ScalarLoopFilter_t lf;
    
    printf("====================================================\n");
    printf("Scalar Tracking Loop - Software Simulation\n");
    printf("====================================================\n");
    printf("True Doppler:     %.3f Hz\n", TRUE_DOPPLER_HZ);
    printf("Initial Estimate: %.3f Hz (offset: %.3f Hz)\n", 
           INIT_DOPPLER_HZ, INIT_DOPPLER_HZ - TRUE_DOPPLER_HZ);
    printf("Simulation Time:  %d ms\n\n", SIM_DURATION_MS);
    
    /* Initialize loop filter */
    loop_filter_init(&lf, INIT_DOPPLER_HZ, TRUE_CODE_PHASE);
    
    /* Open log file for plotting */
    FILE *log_file = fopen("tracking_sim_log.csv", "w");
    if (log_file) {
        fprintf(log_file, "epoch_ms,est_doppler_hz,freq_error_hz,code_phase_chips,I_P,Q_P\n");
    }
    
    printf("%-10s %-14s %-14s %-14s %-12s %-12s\n",
           "Epoch(ms)", "Est Freq(Hz)", "Freq Err(Hz)", "Code Phase", "I_P", "Q_P");
    printf("--------------------------------------------------------------------\n");
    
    for (int epoch = 0; epoch < SIM_DURATION_MS; epoch++) {
        /* Generate synthetic measurements */
        double I_E, Q_E, I_L, Q_L;
        int32_t I_P, Q_P;
        generate_synthetic_dumps(epoch, TRUE_DOPPLER_HZ, lf.carrier_freq,
                                &I_E, &Q_E, &I_P, &Q_P, &I_L, &Q_L);
        
        /* Run loop filters */
        pll_update(&lf, I_P, Q_P, EPOCH_PERIOD_S);
        dll_update(&lf, (int32_t)I_E, (int32_t)I_L, EPOCH_PERIOD_S);
        
        /* Log every 50 ms */
        if (epoch % 50 == 0) {
            double freq_error = lf.carrier_freq - TRUE_DOPPLER_HZ;
            printf("%-10d %-14.4f %-14.4f %-14.6f %-12d %-12d\n",
                   epoch, lf.carrier_freq, freq_error, 
                   lf.code_phase, I_P, Q_P);
            
            if (log_file) {
                fprintf(log_file, "%d,%.6f,%.6f,%.6f,%d,%d\n",
                        epoch, lf.carrier_freq, freq_error,
                        lf.code_phase, I_P, Q_P);
            }
        }
    }
    
    if (log_file) {
        fclose(log_file);
        printf("\n✓ Log saved to: tracking_sim_log.csv\n");
        printf("  Plot with: python3 plot_tracking_sim.py\n");
    }
    
    /* Final statistics */
    double final_freq_error = lf.carrier_freq - TRUE_DOPPLER_HZ;
    printf("\n====================================================\n");
    printf("Final State:\n");
    printf("  Estimated Doppler: %.6f Hz\n", lf.carrier_freq);
    printf("  Frequency Error:   %.6f Hz\n", final_freq_error);
    printf("  Code Phase:        %.6f chips\n", lf.code_phase);
    printf("====================================================\n");
    
    if (fabs(final_freq_error) < 1.0) {
        printf("✓ PASS: Loop filter converged (error < 1 Hz)\n");
    } else {
        printf("✗ FAIL: Loop filter did not converge\n");
    }
    
    return 0;
}