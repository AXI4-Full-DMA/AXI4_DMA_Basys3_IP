# -------------------------------------------------------------------------
# 5. Add Custom Counter (DUT) using Module Reference
# -------------------------------------------------------------------------
# Add the RTL module to the Block Design with instance name 'counter_dut'
create_bd_cell -type module -reference counter counter_dut

# Connect the 100MHz output clock from the wizard to the counter input
# Using absolute path to ensure correct pin matching
connect_bd_net [get_bd_pins /clk_wiz_0/clk_out1] [get_bd_pins /counter_dut/clk]

# Ensure xlconstant_0 exists to provide a stable '1' to the enable signal
if {[get_bd_cells -quiet /xlconstant_0] == ""} {
    create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 /xlconstant_0
}

# Connect Constant '1' to the enable (en) pin for continuous counting operation
connect_bd_net [get_bd_pins /xlconstant_0/dout] [get_bd_pins /counter_dut/en]

# -------------------------------------------------------------------------
# 6. Mark Debug and Finalization

#create ports
make_bd_pins_external [get_bd_pins /counter_dut/count]

# -------------------------------------------------------------------------
# Mark the 'count' signal for Debugging to allow ILA observation

set_property HDL_ATTRIBUTE.DEBUG true [get_bd_nets -of_objects [get_bd_pins /counter_dut/count]]


# -------------------------------------------------------------------------
# Apply Debug Automation
# This command:
#   - Instantiates 'system_ila_0'
#   - Sets probe to 'Data and Trigger'
#   - Connects clock from '/clk_wiz_0/clk_out1'
# -------------------------------------------------------------------------
apply_bd_automation -rule xilinx.com:bd_rule:debug -dict [list \
    [get_bd_nets -of_objects [get_bd_pins /counter_dut/count]] \
    {PROBE_TYPE "Data and Trigger" CLK_SRC "/clk_wiz_0/clk_out1" SYSTEM_ILA "Auto"} \
]

# Assign addresses to all AXI peripherals (UART, etc.)
assign_bd_address

# Clean up and reorganize the Block Design diagram layout
regenerate_bd_layout

# Perform final design validation to check for connectivity or configuration errors
validate_bd_design