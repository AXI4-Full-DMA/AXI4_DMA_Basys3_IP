`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// Simple Realistic Testbench - 빠른 파형 확인용
// 2개 테스트만 실행 → 깔끔한 파형
////////////////////////////////////////////////////////////////////////////////

module tb_write_master();

    // =========================================================================
    // 클럭 및 리셋
    // =========================================================================
    reg clk;
    reg reset_n;
    
    always #5 clk = ~clk;
    
    // =========================================================================
    // 제어 신호
    // =========================================================================
    reg i_start;            // 시작 신호
    reg [31:0] i_dst_addr;  // 
    reg [31:0] i_total_len;
    wire o_write_done;
    
    // =========================================================================
    // FIFO
    // =========================================================================
    reg i_fifo_empty;
    wire o_fifo_rd_en;
    reg [31:0] i_w_data;
    
    reg [31:0] fifo_data [0:255];
    integer fifo_rd_ptr;
    
    // =========================================================================
    // AXI4 신호
    // =========================================================================
    wire [31:0] m_axi_awaddr;
    wire [7:0]  m_axi_awlen;
    wire [2:0]  m_axi_awsize;
    wire [1:0]  m_axi_awburst;
    wire        m_axi_awvalid;
    reg         m_axi_awready;
    
    wire [31:0] m_axi_wdata;
    wire [3:0]  m_axi_wstrb;
    wire        m_axi_wlast;
    wire        m_axi_wvalid;
    reg         m_axi_wready;
    
    reg [1:0]   m_axi_bresp;
    reg         m_axi_bvalid;
    wire        m_axi_bready;
    
    // =========================================================================
    // DUT
    // =========================================================================
    Write_Master #(
        .C_M_AXI_ADDR_WIDTH(32),
        .C_M_AXI_DATA_WIDTH(32)
    ) dut (
        .clk(clk),
        .reset_n(reset_n),
        .i_start(i_start),
        .i_dst_addr(i_dst_addr),
        .i_total_len(i_total_len),
        .o_write_done(o_write_done),
        .i_fifo_empty(i_fifo_empty),
        .o_fifo_rd_en(o_fifo_rd_en),
        .i_w_data(i_w_data),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready)
    );
    
    // =========================================================================
    // FIFO 모델
    // =========================================================================
    initial begin
        for (integer i = 0; i < 256; i = i + 1) begin
            fifo_data[i] = 32'hA000_0000 + i;
        end
    end
    
    always @(*) begin
        i_w_data = fifo_data[fifo_rd_ptr];
    end
    
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            fifo_rd_ptr <= 0;
            i_fifo_empty <= 0;
        end else begin
            if (o_fifo_rd_en && !i_fifo_empty) begin
                fifo_rd_ptr <= fifo_rd_ptr + 1;
                if (fifo_rd_ptr == 255) i_fifo_empty <= 1;
            end
        end
    end
    
    // =========================================================================
    // Realistic AXI Slave - VALID 후 Delay 후 READY
    // =========================================================================
    
    // AW Channel
    reg [3:0] aw_delay_cnt;
    reg       aw_waiting;
    parameter AW_DELAY = 2;  // 2 사이클 지연
    
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            m_axi_awready <= 0;
            aw_delay_cnt <= 0;
            aw_waiting <= 0;
        end else begin
            if (m_axi_awvalid && !aw_waiting) begin
                aw_waiting <= 1;
                aw_delay_cnt <= 0;
                m_axi_awready <= 0;
            end
            
            if (aw_waiting && !m_axi_awready) begin
                if (aw_delay_cnt < AW_DELAY) begin
                    aw_delay_cnt <= aw_delay_cnt + 1;
                end else begin
                    m_axi_awready <= 1;
                end
            end
            
            if (m_axi_awvalid && m_axi_awready) begin
                m_axi_awready <= 0;
                aw_waiting <= 0;
            end
        end
    end
    
    // W Channel
    reg [3:0] w_delay_cnt;
    reg       w_waiting;
    parameter W_DELAY = 1;  // 1 사이클 지연
    
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            m_axi_wready <= 0;
            w_delay_cnt <= 0;
            w_waiting <= 0;
        end else begin
            if (m_axi_wvalid && !w_waiting) begin
                w_waiting <= 1;
                w_delay_cnt <= 0;
                m_axi_wready <= 0;
            end
            
            if (w_waiting && !m_axi_wready) begin
                if (w_delay_cnt < W_DELAY) begin
                    w_delay_cnt <= w_delay_cnt + 1;
                end else begin
                    m_axi_wready <= 1;
                end
            end
            
            if (m_axi_wvalid && m_axi_wready) begin
                m_axi_wready <= 0;
                w_waiting <= 0;
            end
        end
    end
    
    // B Channel
    reg [3:0] b_delay_cnt;
    reg       b_pending;
    parameter B_DELAY = 2;  // 2 사이클 지연
    
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            m_axi_bvalid <= 0;
            m_axi_bresp <= 2'b00;
            b_delay_cnt <= 0;
            b_pending <= 0;
        end else begin
            if (m_axi_wvalid && m_axi_wready && m_axi_wlast && !b_pending) begin
                b_pending <= 1;
                b_delay_cnt <= 0;
                m_axi_bvalid <= 0;
            end
            
            if (b_pending && !m_axi_bvalid) begin
                if (b_delay_cnt < B_DELAY) begin
                    b_delay_cnt <= b_delay_cnt + 1;
                end else begin
                    m_axi_bvalid <= 1;
                    m_axi_bresp <= 2'b00;
                end
            end
            
            if (m_axi_bvalid && m_axi_bready) begin
                m_axi_bvalid <= 0;
                b_pending <= 0;
            end
        end
    end
    
    // =========================================================================
    // 테스트 시나리오 (2개만!)
    // =========================================================================
    initial begin
        clk = 0;
        reset_n = 0;
        i_start = 0;
        i_dst_addr = 0;
        i_total_len = 0;
        
        // 리셋
        #50;
        reset_n = 1;
        #20;
        
        $display("\n========================================");
        $display("Realistic Timing Test");
        $display("AW delay: 2 cycles");
        $display("W delay:  1 cycle");
        $display("B delay:  2 cycles");
        $display("========================================\n");
        
        // Test 1: 16바이트 (4 beats)
        $display("Test 1: 16 bytes (4 beats)");
        i_dst_addr = 32'h8000_0000;
        i_total_len = 16;
        i_start = 1;
        #10;
        i_start = 0;
        
        wait(o_write_done);
        #100;
        
        // Test 2: 32바이트 (8 beats)
        $display("\nTest 2: 32 bytes (8 beats)");
        i_dst_addr = 32'h8000_0100;
        i_total_len = 32;
        i_start = 1;
        #10;
        i_start = 0;
        
        wait(o_write_done);
        #100;
        
        $display("\n========================================");
        $display("ALL TESTS COMPLETED");
        $display("========================================\n");
        $finish;
    end
    
    // =========================================================================
    // 모니터링
    // =========================================================================
    always @(posedge clk) begin
        if (m_axi_awvalid && m_axi_awready) begin
            $display("[%0t] AW: addr=0x%08h, len=%2d", $time, m_axi_awaddr, m_axi_awlen+1);
        end
        
        if (m_axi_wvalid && m_axi_wready) begin
            $display("[%0t] W:  data=0x%08h, last=%0b", $time, m_axi_wdata, m_axi_wlast);
        end
        
        if (m_axi_bvalid && m_axi_bready) begin
            $display("[%0t] B:  resp=OKAY", $time);
        end
        
        if (o_write_done) begin
            $display("[%0t] *** WRITE DONE ***", $time);
        end
    end
    
    // =========================================================================
    // Waveform (이미지 신호만)
    // =========================================================================
    initial begin
        $dumpfile("tb_write_master.vcd");
        $dumpvars(0, tb_write_master);
        
        $dumpvars(1, clk);
        $dumpvars(1, reset_n);
        $dumpvars(1, i_start);
        $dumpvars(1, m_axi_awvalid);
        $dumpvars(1, m_axi_awready);
        $dumpvars(1, m_axi_awaddr);
        $dumpvars(1, m_axi_wvalid);
        $dumpvars(1, m_axi_wready);
        $dumpvars(1, m_axi_wdata);
        $dumpvars(1, m_axi_wlast);
        $dumpvars(1, m_axi_bvalid);
        $dumpvars(1, m_axi_bready);
        $dumpvars(1, m_axi_bresp);
        $dumpvars(1, o_fifo_rd_en);
        $dumpvars(1, o_write_done);
    end

endmodule