/**
 * @file loop_filter.c
 * @brief Scalar Tracking Loop Filter - Stable Implementation (Fixed)
 */

#include "loop_filter.h"
#include <math.h>
#include <stdio.h>

void loop_filter_init(ScalarLoopFilter_t *lf, double initial_doppler_hz, double initial_code_phase) {
    /* PLL initialization */
    lf->carrier_phase = 0.0;
    lf->carrier_freq = initial_doppler_hz;
    lf->pll_integrator = 0.0;
    
    /* PLL coefficients for 2nd order loop */
    /* For loop bandwidth Bn and damping ratio ζ:
     * Natural frequency: ωn = 2π * Bn / (ζ + 1/(4ζ))
     * For ζ = 0.707: ωn ≈ 5.93 * Bn
     */
    double Bn = PLL_BANDWIDTH_HZ;  /* 15 Hz */
    double dt = EPOCH_PERIOD_S;    /* 0.001 s */
    double zeta = 0.707;
    
    /* Calculate natural frequency */
    double omega_n = 2 * M_PI * Bn / (zeta + 1.0/(4.0*zeta));
    
    /* Discrete-time coefficients (much more conservative) */
    lf->pll_coeff1 = 2 * zeta * omega_n * dt;  /* Proportional */
    lf->pll_coeff2 = omega_n * omega_n * dt * dt;  /* Integral */
    
    printf("PLL Init: Bn=%.1f Hz, ωn=%.2f rad/s\n", Bn, omega_n);
    printf("  coeff1 (prop) = %.6f\n", lf->pll_coeff1);
    printf("  coeff2 (int)  = %.6f\n", lf->pll_coeff2);
    
    /* DLL initialization */
    lf->code_phase = initial_code_phase;
    lf->code_freq = CODE_RATE_HZ;
    lf->dll_integrator = 0.0;
    
    double dll_Bn = DLL_BANDWIDTH_HZ;  /* 2 Hz */
    double dll_omega_n = 2 * M_PI * dll_Bn / (zeta + 1.0/(4.0*zeta));
    lf->dll_coeff1 = 2 * zeta * dll_omega_n * dt;
    lf->dll_coeff2 = 0.0;  /* 1st order DLL */
    
    printf("DLL Init: Bn=%.1f Hz, coeff1=%.6f\n", dll_Bn, lf->dll_coeff1);
    
    lf->early_late_spacing = EARLY_LATE_SPACING;
}

void pll_update(ScalarLoopFilter_t *lf, int32_t I_P, int32_t Q_P, double dt) {
    /* Phase error discriminator: atan2(Q, I) in radians */
    double phase_error_rad = atan2((double)Q_P, (double)I_P);
    
    /* Convert to cycles (not radians) for direct Hz correction */
    double phase_error_cycles = phase_error_rad / (2.0 * M_PI);
    
    /* 2nd order loop filter */
    /* Proportional path */
    double proportional = lf->pll_coeff1 * phase_error_cycles;
    
    /* Integral path */
    lf->pll_integrator += lf->pll_coeff2 * phase_error_cycles;
    
    /* Total frequency correction in Hz */
    double freq_correction_hz = proportional + lf->pll_integrator;
    
    /* Update carrier frequency */
    lf->carrier_freq += freq_correction_hz;
    
    /* Update carrier phase */
    lf->carrier_phase += 2.0 * M_PI * lf->carrier_freq * dt;
    
    /* Wrap phase to [0, 2π) */
    while (lf->carrier_phase >= 2.0 * M_PI) lf->carrier_phase -= 2.0 * M_PI;
    while (lf->carrier_phase < 0) lf->carrier_phase += 2.0 * M_PI;
}

void dll_update(ScalarLoopFilter_t *lf, int32_t I_E, int32_t I_L, double dt) {
    /* Code phase error discriminator: (E - L) / (E + L) */
    double E = fabs((double)I_E);
    double L = fabs((double)I_L);
    double code_error_chips = 0.0;
    
    if ((E + L) > 0.0) {
        code_error_chips = ((E - L) / (E + L)) * lf->early_late_spacing;
    }
    
    /* 1st order loop filter */
    double freq_correction = lf->dll_coeff1 * code_error_chips;
    
    /* Update code frequency and phase */
    lf->code_freq += freq_correction;
    lf->code_phase += lf->code_freq * dt;
    
    /* Wrap code phase to [0, 1023) */
    while (lf->code_phase >= 1023.0) lf->code_phase -= 1023.0;
    while (lf->code_phase < 0) lf->code_phase += 1023.0;
}

uint64_t freq_to_nco_word(double freq_hz, double fs_hz) {
    return (uint64_t)((freq_hz / fs_hz) * (double)(1ULL << 48));
}

uint32_t code_freq_to_nco_word(double code_freq, double fs_hz) {
    return (uint32_t)((code_freq / fs_hz) * (double)(1ULL << 32));
}