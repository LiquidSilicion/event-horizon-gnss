# ==========================================
# Clock Constraint (from Zynq PS FCLK_CLK0)
# Note: The actual clock comes from the PS, 
# but we still constrain the input oscillator
# ==========================================
# ZedBoard has a 33.333 MHz oscillator on Y9
# But since we're using FCLK_CLK0 from PS, 
# we don't need to constrain an external clock pin.
# The PS generates the 100 MHz internally.

# ==========================================
# Reset Button (CPU_RESETN, Active Low)
# Only needed if you chose Option 5a
# ==========================================
set_property PACKAGE_PIN P17 [get_ports rst_n_0]
set_property IOSTANDARD LVCMOS33 [get_ports rst_n_0]

# ==========================================
# User LEDs (Active High)
# ==========================================
# LED 0 (Green) - Dump Valid Pulse
set_property PACKAGE_PIN T22 [get_ports led_dump_valid_0]
set_property IOSTANDARD LVCMOS33 [get_ports led_dump_valid_0]

# LED 1 (Green) - Tracking OK Indicator
set_property PACKAGE_PIN T21 [get_ports led_tracking_ok_0]
set_property IOSTANDARD LVCMOS33 [get_ports led_tracking_ok_0]