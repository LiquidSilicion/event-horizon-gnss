/**
 * Scalar Tracking Loop Filter (DLL/PLL)
 * Implements the feedback control that steers the NCOs
 */

typedef struct {
    // PLL state
    double carrier_phase;      // Current carrier phase (radians)
    double carrier_freq;       // Current carrier frequency (Hz)
    double pll_coeff1;         // PLL loop filter coefficient 1
    double pll_coeff2;         // PLL loop filter coefficient 2
    double pll_integrator;     // PLL loop filter integrator
    
    // DLL state
    double code_phase;         // Current code phase (chips)
    double code_freq;          // Current code frequency (Hz)
    double dll_coeff1;         // DLL loop filter coefficient 1
    double dll_coeff2;         // DLL loop filter coefficient 2
    double dll_integrator;     // DLL loop filter integrator
    
    // Configuration
    double early_late_spacing; // Early-Late spacing (chips), typically 0.5
} ScalarLoopFilter_t;

/**
 * Initialize the loop filter with default tracking parameters
 */
void loop_filter_init(ScalarLoopFilter_t *lf, double initial_doppler_hz, double initial_code_phase) {
    // PLL initialization (2nd order loop)
    lf->carrier_phase = 0.0;
    lf->carrier_freq = initial_doppler_hz;
    lf->pll_coeff1 = 0.0;  // Calculate based on loop bandwidth
    lf->pll_coeff2 = 0.0;  // Calculate based on loop bandwidth
    lf->pll_integrator = 0.0;
    
    // DLL initialization (1st order loop)
    lf->code_phase = initial_code_phase;
    lf->code_freq = 1023000.0;  // GPS L1CA code rate
    lf->dll_coeff1 = 0.0;  // Calculate based on loop bandwidth
    lf->dll_coeff2 = 0.0;
    lf->dll_integrator = 0.0;
    
    lf->early_late_spacing = 0.5;
}

/**
 * PLL discriminator: atan2(Q_P, I_P)
 * Returns phase error in radians
 */
double pll_discriminator(int32_t I_P, int32_t Q_P) {
    return atan2((double)Q_P, (double)I_P);
}

/**
 * DLL discriminator: (E - L) / (E + L) for code tracking
 * Returns code phase error in chips
 */
double dll_discriminator(int32_t I_E, int32_t I_L) {
    double E = sqrt((double)(I_E * I_E));  // Or use magnitude
    double L = sqrt((double)(I_L * I_L));
    
    if ((E + L) == 0) return 0.0;
    return (E - L) / (E + L) * lf->early_late_spacing;
}

/**
 * Update PLL: Calculate new carrier frequency and phase
 */
void pll_update(ScalarLoopFilter_t *lf, int32_t I_P, int32_t Q_P, double dt) {
    // Phase error from discriminator
    double phase_error = pll_discriminator(I_P, Q_P);
    
    // 2nd order loop filter
    lf->pll_integrator += lf->pll_coeff2 * phase_error * dt;
    double freq_correction = lf->pll_coeff1 * phase_error + lf->pll_integrator;
    
    // Update carrier frequency and phase
    lf->carrier_freq += freq_correction;
    lf->carrier_phase += 2 * M_PI * lf->carrier_freq * dt;
    
    // Wrap phase to [0, 2π)
    while (lf->carrier_phase >= 2 * M_PI) lf->carrier_phase -= 2 * M_PI;
    while (lf->carrier_phase < 0) lf->carrier_phase += 2 * M_PI;
}

/**
 * Update DLL: Calculate new code frequency and phase
 */
void dll_update(ScalarLoopFilter_t *lf, int32_t I_E, int32_t I_L, double dt) {
    // Code phase error from discriminator
    double code_error = dll_discriminator(I_E, I_L);
    
    // 1st order loop filter
    double freq_correction = lf->dll_coeff1 * code_error;
    
    // Update code frequency and phase
    lf->code_freq += freq_correction;
    lf->code_phase += lf->code_freq * dt;
    
    // Wrap code phase to [0, 1023)
    while (lf->code_phase >= 1023.0) lf->code_phase -= 1023.0;
}

/**
 * Convert carrier frequency (Hz) to NCO frequency word (48-bit)
 */
uint64_t freq_to_nco_word(double freq_hz, double fs_hz) {
    return (uint64_t)((freq_hz / fs_hz) * (double)(1ULL << 48));
}

/**
 * Convert code frequency (chips/s) to NCO frequency word (32-bit)
 */
uint32_t code_freq_to_nco_word(double code_freq, double fs_hz) {
    return (uint32_t)((code_freq / fs_hz) * (double)(1ULL << 32));
}

/**
 * Convert carrier phase (radians) to NCO phase word (48-bit)
 */
uint64_t phase_to_nco_word(double phase_rad) {
    return (uint64_t)((phase_rad / (2 * M_PI)) * (double)(1ULL << 48));
}

/**
 * Convert code phase (chips) to NCO phase word (32-bit)
 */
uint32_t code_phase_to_nco_word(double code_phase_chips) {
    return (uint32_t)(code_phase_chips * (double)(1ULL << 22));
}