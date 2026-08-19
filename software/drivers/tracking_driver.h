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

/* ============== Configuration Constants ============== */
#define TRACKING_BASE_ADDR      0x40000000UL  /* AXI base address from Vivado */
#define TRACKING_ADDR_RANGE     0x10000       /* 64 KB address space */
#define TRACKING_DEV_MEM        "/dev/mem"

/* Default sample rate (must match FPGA design) */
#define FS_HZ                   4000000.0     /* 4 MHz */
#define CODE_RATE_HZ            1023000.0     /* GPS L1CA C/A code rate */

/* ============== Register Offsets ============== */
#define REG_CARR_FREQ_LO        0x00
#define REG_CARR_FREQ_HI        0x04
#define REG_CODE_FREQ           0x08
#define REG_INIT_CODE_PHASE     0x0C
#define REG_CONTROL             0x10
#define REG_I_P                 0x20
#define REG_Q_P                 0x24
#define REG_STATUS              0x28

/* ============== Register Map Structure ============== */
typedef struct {
    volatile uint32_t carr_freq_lo;     /* 0x00 */
    volatile uint32_t carr_freq_hi;     /* 0x04 */
    volatile uint32_t code_freq;        /* 0x08 */
    volatile uint32_t init_code_phase;  /* 0x0C */
    volatile uint32_t control;          /* 0x10 */
    volatile uint32_t reserved[3];      /* 0x14 - 0x1C */
    volatile int32_t  I_P;              /* 0x20 */
    volatile int32_t  Q_P;              /* 0x24 */
    volatile uint32_t status;           /* 0x28 */
} Tracking_Regs_t;

/* ============== Driver Handle ============== */
typedef struct {
    int              fd;                /* File descriptor for /dev/mem */
    void            *mapped_base;       /* mmap'd base address */
    Tracking_Regs_t *regs;              /* Typed register pointer */
    uint32_t         base_addr;         /* Physical base address */
} Tracking_Driver_t;

/* ============== Function Prototypes ============== */

/**
 * @brief Initialize the tracking driver
 * @param drv      Pointer to driver handle
 * @param base_addr Physical AXI base address (use TRACKING_BASE_ADDR if default)
 * @return 0 on success, -1 on failure
 */
int tracking_init(Tracking_Driver_t *drv, uint32_t base_addr);

/**
 * @brief Close the tracking driver and release resources
 */
void tracking_close(Tracking_Driver_t *drv);

/**
 * @brief Set the carrier Doppler frequency
 * @param drv         Pointer to driver handle
 * @param doppler_hz  Doppler frequency in Hz (e.g., 1255.0)
 */
void tracking_set_doppler(Tracking_Driver_t *drv, double doppler_hz);

/**
 * @brief Set the code NCO frequency (usually fixed at 1.023 MHz)
 */
void tracking_set_code_freq(Tracking_Driver_t *drv);

/**
 * @brief Set the initial code phase
 * @param code_phase_chips  Initial code phase in chips (0 to 1022.999)
 */
void tracking_set_code_phase(Tracking_Driver_t *drv, double code_phase_chips);

/**
 * @brief Select PRN and enable the channel
 * @param prn       PRN number (1 to 32)
 * @param enable    1 to enable, 0 to disable
 */
void tracking_set_prn(Tracking_Driver_t *drv, uint8_t prn, uint8_t enable);

/**
 * @brief Read the Prompt In-Phase correlator dump
 */
int32_t tracking_read_I_P(Tracking_Driver_t *drv);

/**
 * @brief Read the Prompt Quadrature correlator dump
 */
int32_t tracking_read_Q_P(Tracking_Driver_t *drv);

/**
 * @brief Read the status register
 * @param dump_valid  Output: 1 if new dump is available
 * @param epoch_count Output: Number of completed epochs
 */
void tracking_read_status(Tracking_Driver_t *drv, uint8_t *dump_valid, 
                          uint16_t *epoch_count);

/**
 * @brief Wait for a new dump to be available (blocking)
 * @param timeout_ms  Maximum time to wait in milliseconds
 * @return 0 on success, -1 on timeout
 */
int tracking_wait_dump(Tracking_Driver_t *drv, uint32_t timeout_ms);

#endif /* TRACKING_DRIVER_H */