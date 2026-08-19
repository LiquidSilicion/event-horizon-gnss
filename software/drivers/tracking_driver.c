/* ============================================
 * CRITICAL: Feature test macro MUST be first
 * This tells GCC to expose POSIX functions
 * like clock_gettime() and CLOCK_MONOTONIC
 * ============================================ */
#define _POSIX_C_SOURCE 200809L
#define _GNU_SOURCE

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <time.h>
#include <math.h>
#include "tracking_driver.h"

/* ============== Driver Implementation ============== */

int tracking_init(Tracking_Driver_t *drv, uint32_t base_addr) {
    drv->base_addr = base_addr;
    
    drv->fd = open(TRACKING_DEV_MEM, O_RDWR | O_SYNC);
    if (drv->fd < 0) {
        perror("ERROR: Could not open /dev/mem. Run with sudo.");
        return -1;
    }
    
    drv->mapped_base = mmap(NULL, TRACKING_ADDR_RANGE, 
                            PROT_READ | PROT_WRITE, 
                            MAP_SHARED, 
                            drv->fd, 
                            base_addr);
    
    if (drv->mapped_base == MAP_FAILED) {
        perror("ERROR: mmap failed");
        close(drv->fd);
        return -1;
    }
    
    drv->regs = (Tracking_Regs_t *)drv->mapped_base;
    
    printf("✓ Tracking driver initialized at 0x%08X\n", base_addr);
    return 0;
}

void tracking_close(Tracking_Driver_t *drv) {
    if (drv->mapped_base && drv->mapped_base != MAP_FAILED) {
        munmap(drv->mapped_base, TRACKING_ADDR_RANGE);
    }
    if (drv->fd >= 0) {
        close(drv->fd);
    }
    printf("✓ Tracking driver closed\n");
}

void tracking_set_doppler(Tracking_Driver_t *drv, double doppler_hz) {
    double ratio = doppler_hz / FS_HZ;
    uint64_t freq_word_48 = (uint64_t)(ratio * (double)(1ULL << 48));
    
    uint32_t lo = (uint32_t)(freq_word_48 & 0xFFFFFFFF);
    uint16_t hi = (uint16_t)((freq_word_48 >> 32) & 0xFFFF);
    
    drv->regs->carr_freq_lo = lo;
    drv->regs->carr_freq_hi = hi;
    
    printf("✓ Set Doppler: %.3f Hz -> freq_word = 0x%04X%08X\n", 
           doppler_hz, hi, lo);
}

void tracking_set_code_freq(Tracking_Driver_t *drv) {
    double ratio = CODE_RATE_HZ / FS_HZ;
    uint32_t freq_word = (uint32_t)(ratio * (double)(1ULL << 32));
    
    drv->regs->code_freq = freq_word;
    printf("✓ Set Code Freq: %.0f Hz -> freq_word = 0x%08X\n", 
           CODE_RATE_HZ, freq_word);
}

void tracking_set_code_phase(Tracking_Driver_t *drv, double code_phase_chips) {
    uint32_t phase_word = (uint32_t)(code_phase_chips * (double)(1 << 22));
    drv->regs->init_code_phase = phase_word;
    printf("✓ Set Code Phase: %.3f chips -> 0x%08X\n", 
           code_phase_chips, phase_word);
}

void tracking_set_prn(Tracking_Driver_t *drv, uint8_t prn, uint8_t enable) {
    if (prn < 1 || prn > 32) {
        printf("ERROR: PRN must be 1-32\n");
        return;
    }
    uint32_t ctrl = ((uint32_t)(prn - 1) & 0x1F) | ((uint32_t)(enable & 0x1) << 8);
    drv->regs->control = ctrl;
    printf("✓ Set PRN %d, enable=%d -> control = 0x%08X\n", 
           prn, enable, ctrl);
}

int32_t tracking_read_I_P(Tracking_Driver_t *drv) {
    return drv->regs->I_P;
}

int32_t tracking_read_Q_P(Tracking_Driver_t *drv) {
    return drv->regs->Q_P;
}

void tracking_read_status(Tracking_Driver_t *drv, uint8_t *dump_valid, 
                          uint16_t *epoch_count) {
    uint32_t status = drv->regs->status;
    *dump_valid = status & 0x1;
    *epoch_count = (status >> 16) & 0xFFFF;
}

int tracking_wait_dump(Tracking_Driver_t *drv, uint32_t timeout_ms) {
    struct timespec start, now;
    
    /* This now works because of _POSIX_C_SOURCE at the top */
    clock_gettime(CLOCK_MONOTONIC, &start);
    
    while (1) {
        uint8_t dump_valid;
        uint16_t epoch_count;
        tracking_read_status(drv, &dump_valid, &epoch_count);
        
        if (dump_valid) {
            return 0;
        }
        
        clock_gettime(CLOCK_MONOTONIC, &now);
        uint32_t elapsed_ms = (now.tv_sec - start.tv_sec) * 1000 +
                              (now.tv_nsec - start.tv_nsec) / 1000000;
        if (elapsed_ms > timeout_ms) {
            return -1;
        }
        
        usleep(100);
    }
}

/* ============== Test Main ============== */

int main(int argc, char *argv[]) {
    Tracking_Driver_t drv;
    
    printf("===========================================\n");
    printf("Event Horizon GNSS - Tracking Driver Test\n");
    printf("===========================================\n\n");
    
    if (tracking_init(&drv, TRACKING_BASE_ADDR) < 0) {
        return -1;
    }
    
    printf("\n--- Configuring Channel ---\n");
    tracking_set_doppler(&drv, 1255.0);
    tracking_set_code_freq(&drv);
    tracking_set_code_phase(&drv, 347.0);
    tracking_set_prn(&drv, 1, 1);
    
    printf("\n--- Reading Correlator Dumps ---\n");
    printf("%-8s %-12s %-12s %-12s %-8s\n", 
           "Epoch", "I_P", "Q_P", "Status", "Valid");
    printf("----------------------------------------------\n");
    
    for (int i = 0; i < 10; i++) {
        if (tracking_wait_dump(&drv, 100) < 0) {
            printf("Timeout waiting for dump!\n");
            break;
        }
        
        int32_t ip = tracking_read_I_P(&drv);
        int32_t qp = tracking_read_Q_P(&drv);
        
        uint8_t dump_valid;
        uint16_t epoch_count;
        tracking_read_status(&drv, &dump_valid, &epoch_count);
        
        printf("%-8d %-12d %-12d %-12u %-8d\n", 
               epoch_count, ip, qp, 
               drv.regs->status, dump_valid);
    }
    
    printf("\n");
    tracking_close(&drv);
    
    return 0;
}