/**
 * @file tracking_driver.h
 * @brief User-space driver for Event Horizon GNSS Scalar Tracking Channel
 * 
 * This driver communicates with the FPGA-based scalar tracking engine via
 * AXI4-Lite memory-mapped registers. It provides functions to configure
 * NCOs, select PRNs, and read I&D correlator dumps.
 * 
 * Register Map (per channel, base offset 0x00):
 *   0x00: carr_freq_lo    [31:0]   (W) Carrier NCO frequency word low
 *   0x04: carr_freq_hi    [15:0]   (W) Carrier NCO frequency word high
 *   0x08: code_freq       [31:0]   (W) Code NCO frequency word
 *   0x0C: init_code_phase [31:0]   (W) Initial code phase
 *   0x10: control         [8:0]    (W) PRN[4:0], channel_en[8]
 *   0x20: I_P             [31:0]   (R) Prompt in-phase correlator dump
 *   0x24: Q_P             [31:0]   (R) Prompt quadrature correlator dump
 *   0x28: status          [31:0]   (R) dump_valid[0], epoch_count[31:16]
 */

#ifndef TRACKING_DRIVER_H
#define TRACKING_DRIVER_H

#include <stdint.h>

#define TRACKING_BASE_ADDR      0x40000000UL
#define TRACKING_ADDR_RANGE     0x10000
#define TRACKING_DEV_MEM        "/dev/mem"

#define FS_HZ                   4000000.0
#define CODE_RATE_HZ            1023000.0

/* Register Offsets */
#define REG_CARR_FREQ_LO        0x00
#define REG_CARR_FREQ_HI        0x04
#define REG_CODE_FREQ           0x08
#define REG_INIT_CODE_PHASE     0x0C
#define REG_CONTROL             0x10
#define REG_I_E                 0x20
#define REG_Q_E                 0x24
#define REG_I_P                 0x28
#define REG_Q_P                 0x2C
#define REG_I_L                 0x30
#define REG_Q_L                 0x34
#define REG_STATUS              0x38

typedef struct {
    volatile uint32_t carr_freq_lo;
    volatile uint32_t carr_freq_hi;
    volatile uint32_t code_freq;
    volatile uint32_t init_code_phase;
    volatile uint32_t control;
    volatile uint32_t reserved[3];
    volatile int32_t  I_E;
    volatile int32_t  Q_E;
    volatile int32_t  I_P;
    volatile int32_t  Q_P;
    volatile int32_t  I_L;
    volatile int32_t  Q_L;
    volatile uint32_t status;
} Tracking_Regs_t;

typedef struct {
    int              fd;
    void            *mapped_base;
    Tracking_Regs_t *regs;
    uint32_t         base_addr;
} Tracking_Driver_t;

int tracking_init(Tracking_Driver_t *drv, uint32_t base_addr);
void tracking_close(Tracking_Driver_t *drv);
void tracking_set_doppler(Tracking_Driver_t *drv, double doppler_hz);
void tracking_set_code_freq(Tracking_Driver_t *drv);
void tracking_set_code_phase(Tracking_Driver_t *drv, double code_phase_chips);
void tracking_set_prn(Tracking_Driver_t *drv, uint8_t prn, uint8_t enable);

/* All 6 correlator read functions */
int32_t tracking_read_I_E(Tracking_Driver_t *drv);
int32_t tracking_read_Q_E(Tracking_Driver_t *drv);
int32_t tracking_read_I_P(Tracking_Driver_t *drv);
int32_t tracking_read_Q_P(Tracking_Driver_t *drv);
int32_t tracking_read_I_L(Tracking_Driver_t *drv);
int32_t tracking_read_Q_L(Tracking_Driver_t *drv);

void tracking_read_status(Tracking_Driver_t *drv, uint8_t *dump_valid, uint16_t *epoch_count);
int tracking_wait_dump(Tracking_Driver_t *drv, uint32_t timeout_ms);

#endif