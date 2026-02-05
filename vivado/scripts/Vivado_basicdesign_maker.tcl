# 1. Create MicroBlaze RISC-V and Clocking Wizard
startgroup
create_bd_cell -type ip -vlnv xilinx.com:ip:microblaze_riscv:1.0 microblaze_riscv_0
create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz_0
endgroup

# 2. MicroBlaze Block Automation
# Using manually created clk_wiz_0 as the clock source
apply_bd_automation -rule xilinx.com:bd_rule:microblaze_riscv -config { \
    axi_intc {1} \
    axi_periph {Enabled} \
    cache {None} \
    clk {/clk_wiz_0/clk_out1 (100 MHz)} \
    debug_module {Debug Enabled} \
    ecc {None} \
    local_mem {128KB} \
    preset {None} \
} [get_bd_cells microblaze_riscv_0]

# 3. Clock and Reset Connection Automation
# Using Board Flow interfaces (sys_clock and BTNC reset)
startgroup
apply_bd_automation -rule xilinx.com:bd_rule:board -config { Board_Interface {sys_clock ( System Clock ) } Manual_Source {Auto}} [get_bd_pins clk_wiz_0/clk_in1]
apply_bd_automation -rule xilinx.com:bd_rule:board -config { Board_Interface {reset ( Reset Signal (BTNC) ) } Manual_Source {Auto}} [get_bd_pins clk_wiz_0/reset]
apply_bd_automation -rule xilinx.com:bd_rule:board -config { Board_Interface {reset ( Reset Signal (BTNC) ) } Manual_Source {Auto}} [get_bd_pins rst_clk_wiz_0_100M/ext_reset_in]
endgroup

# 4. Add UARTlite and Connect Board Interface
# Applied [current_bd_design] for reusability
startgroup
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_uartlite:2.0 axi_uartlite_0
apply_board_connection -board_interface "usb_uart" -ip_intf "axi_uartlite_0/UART" -diagram [current_bd_design]
endgroup

# 5. Connect UARTlite to MicroBlaze via AXI Interconnect
# Performs address assignment (0x4060_0000)
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { \
    Clk_master {/clk_wiz_0/clk_out1 (100 MHz)} \
    Clk_slave {Auto} \
    Clk_xbar {/clk_wiz_0/clk_out1 (100 MHz)} \
    Master {/microblaze_riscv_0 (Periph)} \
    Slave {/axi_uartlite_0/S_AXI} \
    ddr_seg {Auto} \
    intc_ip {/microblaze_riscv_0_axi_periph} \
    master_apm {0} \
} [get_bd_intf_pins axi_uartlite_0/S_AXI]

# 6. Finalize Design
assign_bd_address
regenerate_bd_layout
validate_bd_design