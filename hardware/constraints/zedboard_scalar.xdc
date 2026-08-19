# ==========================================
# Clock Constraint (100 MHz System Clock)
# ==========================================
create_clock -period 10.000 -name sys_clk [get_ports clk_100mhz]

# ==========================================
# System Clock Pin (Y9 on ZedBoard)
# ==========================================
set_property PACKAGE_PIN Y9 [get_ports clk_100mhz]
set_property IOSTANDARD LVCMOS33 [get_ports clk_100mhz]

# ==========================================
# Reset Button (CPU_RESETN, Active Low)
# ==========================================
set_property PACKAGE_PIN P17 [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]

# ==========================================
# User LEDs (Active High)
# ==========================================
# LED 0 (Green) - Dump Valid Pulse
set_property PACKAGE_PIN T22 [get_ports led_dump_valid]
set_property IOSTANDARD LVCMOS33 [get_ports led_dump_valid]

# LED 1 (Green) - Tracking OK Indicator
set_property PACKAGE_PIN T21 [get_ports led_tracking_ok]
set_property IOSTANDARD LVCMOS33 [get_ports led_tracking_ok]