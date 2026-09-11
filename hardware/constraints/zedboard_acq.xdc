## ================================================================
## ZedBoard Clock and Pin Constraints (FIXED)
## ================================================================

## 1. Primary System Clock (100 MHz) - MUST be defined here
create_clock -period 10.000 -name clk_100 [get_ports clk_100]
set_property PACKAGE_PIN Y9 [get_ports clk_100]
set_property IOSTANDARD LVCMOS33 [get_ports clk_100]

## 2. Generated Clock (200 MHz from MMCM)
## This tells Vivado that clk_out1 is derived from clk_100
create_generated_clock -name clk_200 \
    -source [get_ports clk_100] \
    -multiply_by 2 \
    [get_pins u_clk_wiz/inst/clk_out1]

## 3. Control Buttons
set_property PACKAGE_PIN P16 [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]

set_property PACKAGE_PIN R16 [get_ports start_btn]
set_property IOSTANDARD LVCMOS33 [get_ports start_btn]

## 4. Status LEDs
set_property PACKAGE_PIN T22 [get_ports {led_done}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_done}]

set_property PACKAGE_PIN T21 [get_ports {led_busy}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_busy}]

set_property PACKAGE_PIN U22 [get_ports {led_found}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_found}]

set_property PACKAGE_PIN U21 [get_ports {led_prn[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_prn[0]}]

set_property PACKAGE_PIN V22 [get_ports {led_prn[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_prn[1]}]

set_property PACKAGE_PIN W22 [get_ports {led_prn[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_prn[2]}]

set_property PACKAGE_PIN U19 [get_ports {led_prn[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_prn[3]}]

set_property PACKAGE_PIN U14 [get_ports {led_prn[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led_prn[4]}]

## 5. UART Interface
set_property PACKAGE_PIN B20 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]

set_property PACKAGE_PIN B21 [get_ports uart_rx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_rx]

## 6. False path for asynchronous reset
set_false_path -from [get_ports rst_n]

## 7. Clock domain crossing constraints (if needed)
## The sample_div_counter runs on clk_100, but sample_en is used across domains
set_false_path -from [get_cells sample_div_counter_reg*] -to [get_cells sample_en*]