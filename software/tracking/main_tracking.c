/**
 * @file main_tracking.c
 * @brief Main tracking loop for Event Horizon GNSS
 */

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
        return -1;
    }
    
    /* Configure initial parameters */
    tracking_set_doppler(&drv, 1255.0);
    tracking_set_code_freq(&drv);
    tracking_set_code_phase(&drv, 347.0);
    tracking_set_prn(&drv, 1, 1);
    
    /* Initialize loop filter */
    loop_filter_init(&loop_filter, 1255.0, 347.0);
    
    printf("Starting tracking loop...\n\n");
    
    /* Main tracking loop (runs at 1 kHz = 1 ms epoch) */
    for (int epoch = 0; epoch < 10000; epoch++) {
        /* Wait for new dump */
        if (tracking_wait_dump(&drv, 100) < 0) {
            printf("Timeout at epoch %d\n", epoch);
            break;
        }
        
        /* Read correlator outputs */
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
            printf("Epoch %5d: I_P=%8d Q_P=%8d | Freq=%.2f Hz Phase=%.3f chips\n",
                   epoch, I_P, Q_P, loop_filter.carrier_freq, loop_filter.code_phase);
        }
    }
    
    tracking_close(&drv);
    return 0;
}