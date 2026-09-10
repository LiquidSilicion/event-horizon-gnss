## ZedBoard Pin Constraints for GNSS Acquisition Engine
## ================================================================

## System Clock (100 MHz)
set_property PACKAGE_PIN Y9 [get_ports clk_100]
set_property IOSTANDARD LVCMOS33 [get_ports clk_100]
create_clock -add -name sys_clk_pin -period 10.00 [get_ports clk_100]

## Reset Button (BTN_CENTER - Active Low)
set_property PACKAGE_PIN P16 [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]

## Start Button (BTN_UP - Active High)
set_property PACKAGE_PIN R16 [get_ports start_btn]
set_property IOSTANDARD LVCMOS33 [get_ports start_btn]

## Status LEDs (Active High)
set_property PACKAGE_PIN T22 [get_ports led_done]      # LED 0 (Green)
set_property IOSTANDARD LVCMOS33 [get_ports led_done]

set_property PACKAGE_PIN T21 [get_ports led_busy]      # LED 1 (Green)
set_property IOSTANDARD LVCMOS33 [get_ports led_busy]

set_property PACKAGE_PIN U22 [get_ports led_found]     # LED 2 (Green)
set_property IOSTANDARD LVCMOS33 [get_ports led_found]

set_property PACKAGE_PIN U21 [get_ports led_prn_0]     # LED 3 (Green)
set_property IOSTANDARD LVCMOS33 [get_ports led_prn_0]

set_property PACKAGE_PIN R14 [get_ports led_prn_1]     # LED 4 (Green)
set_property IOSTANDARD LVCMOS33 [get_ports led_prn_1]

set_property PACKAGE_PIN P14 [get_ports led_prn_2]     # LED 5 (Green)
set_property IOSTANDARD LVCMOS33 [get_ports led_prn_2]

set_property PACKAGE_PIN N16 [get_ports led_prn_3]     # LED 6 (Green)
set_property IOSTANDARD LVCMOS33 [get_ports led_prn_3]

set_property PACKAGE_PIN M16 [get_ports led_prn_4]     # LED 7 (Green)
set_property IOSTANDARD LVCMOS33 [get_ports led_prn_4]

## UART Interface (directly to USB-UART bridge on ZedBoard)
set_property PACKAGE_PIN B20 [get_ports uart_tx]       # UART TX to USB
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]

set_property PACKAGE_PIN B21 [get_ports uart_rx]       # UART RX from USB
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx]

## Timing Constraints
create_generated_clock -name clk_4m -source [get_ports clk_100] \
    -divide_by 25 [get_ports clk_100]

## False path for asynchronous reset
set_false_path -from [get_ports rst_n]