/**
 * @file loop_filter.h
 * @brief Scalar Tracking Loop Filter (DLL/PLL) for Event Horizon GNSS
 */

#ifndef LOOP_FILTER_H
#define LOOP_FILTER_H

#include <stdint.h>
#include <math.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

/* ============== Loop Filter Configuration ============== */
#define FS_HZ                   4000000.0     /* Sample rate */
#define CODE_RATE_HZ            1023000.0     /* GPS L1CA code rate */
#define EPOCH_PERIOD_S          0.001         /* 1 ms integration */
#define EARLY_LATE_SPACING      0.5           /* chips */

/* Loop bandwidths (Hz) - typical values for GPS L1CA */
#define PLL_BANDWIDTH_HZ        15.0          /* Carrier PLL */
#define DLL_BANDWIDTH_HZ        2.0           /* Code DLL */

/* ============== Loop Filter State ============== */
typedef struct {
    /* PLL state */
    double carrier_phase;       /* Current carrier phase (radians) */
    double carrier_freq;        /* Current carrier frequency (Hz) */
    double pll_coeff1;          /* PLL loop filter coefficient 1 */
    double pll_coeff2;          /* PLL loop filter coefficient 2 */
    double pll_integrator;      /* PLL loop filter integrator */
    
    /* DLL state */
    double code_phase;          /* Current code phase (chips) */
    double code_freq;           /* Current code frequency (chips/s) */
    double dll_coeff1;          /* DLL loop filter coefficient 1 */
    double dll_coeff2;          /* DLL loop filter coefficient 2 */
    double dll_integrator;      /* DLL loop filter integrator */
    
    /* Configuration */
    double early_late_spacing;  /* Early-Late spacing (chips) */
} ScalarLoopFilter_t;

/* ============== Function Prototypes ============== */

/**
 * @brief Initialize the loop filter with default tracking parameters
 */
void loop_filter_init(ScalarLoopFilter_t *lf, double initial_doppler_hz, double initial_code_phase);

/**
 * @brief Update PLL: Calculate new carrier frequency and phase
 */
void pll_update(ScalarLoopFilter_t *lf, int32_t I_P, int32_t Q_P, double dt);

/**
 * @brief Update DLL: Calculate new code frequency and phase
 */
void dll_update(ScalarLoopFilter_t *lf, int32_t I_E, int32_t I_L, double dt);

/**
 * @brief Convert carrier frequency (Hz) to NCO frequency word (48-bit)
 */
uint64_t freq_to_nco_word(double freq_hz, double fs_hz);

/**
 * @brief Convert code frequency (chips/s) to NCO frequency word (32-bit)
 */
uint32_t code_freq_to_nco_word(double code_freq, double fs_hz);

#endif /* LOOP_FILTER_H */