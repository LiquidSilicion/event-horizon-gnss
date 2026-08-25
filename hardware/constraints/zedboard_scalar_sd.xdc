create_clock -period 10.000 -name sys_clk [get_ports clk_100mhz]
set_property PACKAGE_PIN T22 [get_ports led_dump_valid]
set_property IOSTANDARD LVCMOS33 [get_ports led_dump_valid]
set_property PACKAGE_PIN T21 [get_ports led_tracking_ok]
set_property IOSTANDARD LVCMOS33 [get_ports led_tracking_ok]
# Note: Since we are booting from SD card without PS UART/JTAG active initially, 
# we do NOT need to constrain rst_n or i_sample/q_sample if they are tied off internally.