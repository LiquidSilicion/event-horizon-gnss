# ==========================================
# System Clock (Y9 on ZedBoard)
# 33.333 MHz oscillator input
# ==========================================
set_property PACKAGE_PIN Y9 [get_ports clk_100mhz]
set_property IOSTANDARD LVCMOS33 [get_ports clk_100mhz]

# ==========================================
# Reset Button (P17 on ZedBoard)
# CPU_RESETN button (Active Low)
# ==========================================
set_property PACKAGE_PIN P17 [get_ports rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n]

# ==========================================
# User LEDs (Active High)
# LED 0 (T22) - Dump Valid Pulse
# LED 1 (T21) - Tracking OK Indicator
# ==========================================
set_property PACKAGE_PIN T22 [get_ports led_dump_valid]
set_property IOSTANDARD LVCMOS33 [get_ports led_dump_valid]

set_property PACKAGE_PIN T21 [get_ports led_tracking_ok]
set_property IOSTANDARD LVCMOS33 [get_ports led_tracking_ok]