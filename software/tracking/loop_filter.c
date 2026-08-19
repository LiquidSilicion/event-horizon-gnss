/**
 * @file loop_filter.c
 * @brief Scalar Tracking Loop Filter Implementation
 */

#include "loop_filter.h"
#include <math.h>

void loop_filter_init(ScalarLoopFilter_t *lf, double initial_doppler_hz, double initial_code_phase) {
    /* PLL initialization (2nd order loop) */
    lf->carrier_phase = 0.0;
    lf->carrier_freq = initial_doppler_hz;
    
    /* Calculate PLL coefficients based on loop bandwidth */
    /* For 2nd order PLL: coeff1 = 0.5 * Bn, coeff2 = 0.25 * Bn^2 */
    double pll_bn = PLL_BANDWIDTH_HZ;
    lf->pll_coeff1 = 0.5 * pll_bn;
    lf->pll_coeff2 = 0.25 * pll_bn * pll_bn;
    lf->pll_integrator = 0.0;
    
    /* DLL initialization (1st order loop) */
    lf->code_phase = initial_code_phase;
    lf->code_freq = CODE_RATE_HZ;
    
    /* Calculate DLL coefficients based on loop bandwidth */
    /* For 1st order DLL: coeff1 = Bn */
    double dll_bn = DLL_BANDWIDTH_HZ;
    lf->dll_coeff1 = dll_bn;
    lf->dll_coeff2 = 0.0;  /* Not used for 1st order */
    lf->dll_integrator = 0.0;
    
    lf->early_late_spacing = EARLY_LATE_SPACING;
}

void pll_update(ScalarLoopFilter_t *lf, int32_t I_P, int32_t Q_P, double dt) {
    /* Phase error from discriminator: atan2(Q, I) */
    double phase_error = atan2((double)Q_P, (double)I_P);
    
    /* 2nd order loop filter */
    lf->pll_integrator += lf->pll_coeff2 * phase_error * dt;
    double freq_correction = lf->pll_coeff1 * phase_error + lf->pll_integrator;
    
    /* Update carrier frequency and phase */
    lf->carrier_freq += freq_correction;
    lf->carrier_phase += 2 * M_PI * lf->carrier_freq * dt;
    
    /* Wrap phase to [0, 2π) */
    while (lf->carrier_phase >= 2 * M_PI) lf->carrier_phase -= 2 * M_PI;
    while (lf->carrier_phase < 0) lf->carrier_phase += 2 * M_PI;
}

void dll_update(ScalarLoopFilter_t *lf, int32_t I_E, int32_t I_L, double dt) {
    /* Code phase error from discriminator: (E - L) / (E + L) */
    double E = fabs((double)I_E);
    double L = fabs((double)I_L);
    double code_error = 0.0;
    
    if ((E + L) > 0) {
        code_error = (E - L) / (E + L) * lf->early_late_spacing;
    }
    
    /* 1st order loop filter */
    double freq_correction = lf->dll_coeff1 * code_error;
    
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