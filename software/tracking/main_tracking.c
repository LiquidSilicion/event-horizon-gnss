/**
 * @file main_tracking.c
 * @brief Main tracking loop for Event Horizon GNSS
 */

#define _POSIX_C_SOURCE 200809L
#define _GNU_SOURCE

#include <stdio.h>
#include <stdint.h>
#include <unistd.h>
#include "../drivers/tracking_driver.h"
#include "loop_filter.h"

int main() {
    Tracking_Driver_t drv;
    ScalarLoopFilter_t loop_filter;
    
    printf("===========================================\n");
    printf("Event Horizon GNSS - Scalar Tracking Loop\n");
    printf("===========================================\n\n");
    
    /* Initialize driver */
    if (tracking_init(&drv, TRACKING_BASE_ADDR) < 0) {
        fprintf(stderr, "Failed to initialize tracking driver\n");
        return -1;
    }
    
    /* Configure initial parameters */
    printf("Configuring tracking channel...\n");
    tracking_set_doppler(&drv, 1255.0);
    tracking_set_code_freq(&drv);
    tracking_set_code_phase(&drv, 347.0);
    tracking_set_prn(&drv, 1, 1);
    
    /* Initialize loop filter */
    loop_filter_init(&loop_filter, 1255.0, 347.0);
    
    printf("Starting tracking loop...\n\n");
    printf("%-8s %-12s %-12s %-12s %-12s %-12s %-12s %-12s %-12s\n",
           "Epoch", "I_E", "Q_E", "I_P", "Q_P", "I_L", "Q_L", "Freq", "Phase");
    printf("--------------------------------------------------------------------------------\n");
    
    /* Main tracking loop (runs at 1 kHz = 1 ms epoch) */
    for (int epoch = 0; epoch < 10000; epoch++) {
        /* Wait for new dump */
        if (tracking_wait_dump(&drv, 100) < 0) {
            printf("Timeout at epoch %d\n", epoch);
            break;
        }
        
        /* Read all 6 correlator outputs */
        int32_t I_E = tracking_read_I_E(&drv);
        int32_t Q_E = tracking_read_Q_E(&drv);
        int32_t I_P = tracking_read_I_P(&drv);
        int32_t Q_P = tracking_read_Q_P(&drv);
        int32_t I_L = tracking_read_I_L(&drv);
        int32_t Q_L = tracking_read_Q_L(&drv);
        
        /* Update loop filters */
        pll_update(&loop_filter, I_P, Q_P, EPOCH_PERIOD_S);
        dll_update(&loop_filter, I_E, I_L, EPOCH_PERIOD_S);
        
        /* Convert to NCO words */
        uint64_t carr_freq_word = freq_to_nco_word(loop_filter.carrier_freq, FS_HZ);
        uint32_t code_freq_word = code_freq_to_nco_word(loop_filter.code_freq, FS_HZ);
        
        /* Write updated NCO values to FPGA */
        drv.regs->carr_freq_lo = (uint32_t)(carr_freq_word & 0xFFFFFFFF);
        drv.regs->carr_freq_hi = (uint16_t)((carr_freq_word >> 32) & 0xFFFF);
        drv.regs->code_freq = code_freq_word;
        
        /* Log every 100 epochs */
        if (epoch % 100 == 0) {
            printf("%-8d %-12d %-12d %-12d %-12d %-12d %-12d %-12.2f %-12.3f\n",
                   epoch, I_E, Q_E, I_P, Q_P, I_L, Q_L,
                   loop_filter.carrier_freq, loop_filter.code_phase);
        }
    }
    
    printf("\n");
    tracking_close(&drv);
    return 0;
}