`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// Vivado-compatible AXI4 Read Master Testbench
////////////////////////////////////////////////////////////////////////////////

module tb_read_master();

    // =========================================================================
    // Signals
    // =========================================================================
    reg clk;
    reg reset_n;
    
    always #5 clk = ~clk;
    
    reg i_start;
    reg [31:0] i_src_addr;
    reg [31:0] i_total_len;
    wire o_read_done;
    
    reg i_fifo_full;
    wire o_fifo_push;
    wire [31:0] o_r_data;
    
    wire [31:0] m_axi_araddr;
    wire [7:0]  m_axi_arlen;
    wire [2:0]  m_axi_arsize;
    wire [1:0]  m_axi_arburst;
    wire        m_axi_arvalid;
    reg         m_axi_arready;
    
    reg [31:0]  m_axi_rdata;
    reg         m_axi_rlast;
    reg         m_axi_rvalid;
    wire        m_axi_rready;
    
    // =========================================================================
    // DUT
    // =========================================================================
    Read_Master #(
        .C_M_AXI_ADDR_WIDTH(32),
        .C_M_AXI_DATA_WIDTH(32)
    ) dut (
        .clk(clk),
        .reset_n(reset_n),
        .i_start(i_start),
        .i_src_addr(i_src_addr),
        .i_total_len(i_total_len),
        .o_read_done(o_read_done),
        .i_fifo_full(i_fifo_full),
        .o_fifo_push(o_fifo_push),
        .o_r_data(o_r_data),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready)
    );
    
    // =========================================================================
    // Memory Model
    // =========================================================================
    reg [31:0] memory [0:4095];
    
    integer i;
    initial begin
        for (i = 0; i < 4096; i = i + 1) begin
            memory[i] = 32'hA000_0000 + i;
        end
    end
    
    // =========================================================================
    // AR Channel
    // =========================================================================
    reg [3:0] ar_delay_cnt;
    reg       ar_waiting;
    reg [31:0] stored_addr;
    reg [7:0]  stored_len;
    
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            m_axi_arready <= 1'b0;
            ar_delay_cnt <= 4'd0;
            ar_waiting <= 1'b0;
            stored_addr <= 32'd0;
            stored_len <= 8'd0;
        end else begin
            if (m_axi_arvalid && !ar_waiting && !m_axi_arready) begin
                ar_waiting <= 1'b1;
                ar_delay_cnt <= 4'd0;
            end
            
            if (ar_waiting && !m_axi_arready) begin
                if (ar_delay_cnt < 4'd2) begin
                    ar_delay_cnt <= ar_delay_cnt + 4'd1;
                end else begin
                    m_axi_arready <= 1'b1;
                    stored_addr <= m_axi_araddr;
                    stored_len <= m_axi_arlen;
                end
            end
            
            if (m_axi_arvalid && m_axi_arready) begin
                m_axi_arready <= 1'b0;
                ar_waiting <= 1'b0;
            end
        end
    end
    
    // =========================================================================
    // R Channel
    // =========================================================================
    reg [7:0] r_beat_cnt;
    reg [7:0] r_total_beats;
    reg [31:0] r_addr;
    reg       r_active;
    reg [3:0] r_delay_cnt;
    reg       r_waiting;
    
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            m_axi_rvalid <= 1'b0;
            m_axi_rlast <= 1'b0;
            m_axi_rdata <= 32'd0;
            r_beat_cnt <= 8'd0;
            r_total_beats <= 8'd0;
            r_addr <= 32'd0;
            r_active <= 1'b0;
            r_delay_cnt <= 4'd0;
            r_waiting <= 1'b0;
        end else begin
            if (m_axi_arvalid && m_axi_arready && !r_active) begin
                r_active <= 1'b1;
                r_addr <= stored_addr;
                r_total_beats <= stored_len;
                r_beat_cnt <= 8'd0;
                r_waiting <= 1'b1;
                r_delay_cnt <= 4'd0;
            end
            
            if (r_active && !m_axi_rvalid && r_waiting) begin
                if (r_delay_cnt < 4'd1) begin
                    r_delay_cnt <= r_delay_cnt + 4'd1;
                end else begin
                    m_axi_rvalid <= 1'b1;
                    m_axi_rdata <= memory[(r_addr >> 2) + r_beat_cnt];
                    m_axi_rlast <= (r_beat_cnt == r_total_beats) ? 1'b1 : 1'b0;
                    r_waiting <= 1'b0;
                end
            end
            
            if (m_axi_rvalid && m_axi_rready) begin
                m_axi_rvalid <= 1'b0;
                m_axi_rlast <= 1'b0;
                
                if (r_beat_cnt < r_total_beats) begin
                    r_beat_cnt <= r_beat_cnt + 8'd1;
                    r_waiting <= 1'b1;
                    r_delay_cnt <= 4'd0;
                end else begin
                    r_active <= 1'b0;
                end
            end
        end
    end
    
    // =========================================================================
    // Test Scenario
    // =========================================================================
    initial begin
        clk = 1'b0;
        reset_n = 1'b0;
        i_start = 1'b0;
        i_src_addr = 32'd0;
        i_total_len = 32'd0;
        i_fifo_full = 1'b0;
        
        #50;
        reset_n = 1'b1;
        #20;
        
        // Test 1
        $display("Test 1: 16 bytes");
        i_src_addr = 32'h0000_0000;
        i_total_len = 32'd16;
        i_start = 1'b1;
        #10;
        i_start = 1'b0;
        
        wait(o_read_done == 1'b1);
        #100;
        
        // Test 2
        $display("Test 2: 32 bytes");
        i_src_addr = 32'h0000_0100;
        i_total_len = 32'd32;
        i_start = 1'b1;
        #10;
        i_start = 1'b0;
        
        wait(o_read_done == 1'b1);
        #100;
        
        $display("All tests completed");
        $finish;
    end
    
    // =========================================================================
    // Monitor
    // =========================================================================
    always @(posedge clk) begin
        if (m_axi_arvalid && m_axi_arready) begin
            $display("[%0t] AR: addr=0x%h, len=%0d", $time, m_axi_araddr, m_axi_arlen+1);
        end
        
        if (m_axi_rvalid && m_axi_rready) begin
            $display("[%0t] R: data=0x%h, last=%0b", $time, m_axi_rdata, m_axi_rlast);
        end
        
        if (o_read_done) begin
            $display("[%0t] READ DONE", $time);
        end
    end

endmodule