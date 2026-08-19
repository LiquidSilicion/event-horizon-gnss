// tracking_driver.h
#ifndef TRACKING_DRIVER_H
#define TRACKING_DRIVER_H

#include <stdint.h>

// Base address assigned in Vivado (e.g., 0x40000000)
#define TRACKING_BASE_ADDR 0x40000000

typedef struct {
    volatile uint32_t carr_freq_lo;    // 0x00
    volatile uint32_t carr_freq_hi;    // 0x04
    volatile uint32_t code_freq;       // 0x08
    volatile uint32_t init_code_phase; // 0x0C
    volatile uint32_t control;         // 0x10 (PRN[4:0], channel_en[8])
    volatile uint32_t reserved1[3];    
    volatile int32_t  I_P;             // 0x20
    volatile int32_t  Q_P;             // 0x24
    volatile uint32_t status;          // 0x28 (epoch_count[31:16], dump_valid[0])
} Tracking_Regs_t;

// Function prototypes
void tracking_init(void* base_addr);
void tracking_set_doppler(void* base_addr, double doppler_hz);
int32_t tracking_read_I_P(void* base_addr);

#endif