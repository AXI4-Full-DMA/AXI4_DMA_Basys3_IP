`timescale 1 ns / 1 ps

	module Top_DMA #
	(
		// Users to add parameters here

		// User parameters ends
		// Do not modify the parameters beyond this line


		// Parameters of Axi Slave Bus Interface S00_AXI
		parameter integer C_S00_AXI_DATA_WIDTH	= 32,
		parameter integer C_S00_AXI_ADDR_WIDTH	= 5,

		// Parameters of Axi Master Bus Interface M00_AXI
		parameter  C_M00_AXI_TARGET_SLAVE_BASE_ADDR	= 32'h40000000,
		parameter integer C_M00_AXI_BURST_LEN	= 16,
		parameter integer C_M00_AXI_ID_WIDTH	= 1,
		parameter integer C_M00_AXI_ADDR_WIDTH	= 32,
		parameter integer C_M00_AXI_DATA_WIDTH	= 32,
		parameter integer C_M00_AXI_AWUSER_WIDTH	= 0,
		parameter integer C_M00_AXI_ARUSER_WIDTH	= 0,
		parameter integer C_M00_AXI_WUSER_WIDTH	= 0,
		parameter integer C_M00_AXI_RUSER_WIDTH	= 0,
		parameter integer C_M00_AXI_BUSER_WIDTH	= 0,

		// Parameters of Axi Master Bus Interface M01_AXI
		parameter  C_M01_AXI_TARGET_SLAVE_BASE_ADDR	= 32'h40000000,
		parameter integer C_M01_AXI_BURST_LEN	= 16,
		parameter integer C_M01_AXI_ID_WIDTH	= 1,
		parameter integer C_M01_AXI_ADDR_WIDTH	= 32,
		parameter integer C_M01_AXI_DATA_WIDTH	= 32,
		parameter integer C_M01_AXI_AWUSER_WIDTH	= 0,
		parameter integer C_M01_AXI_ARUSER_WIDTH	= 0,
		parameter integer C_M01_AXI_WUSER_WIDTH	= 0,
		parameter integer C_M01_AXI_RUSER_WIDTH	= 0,
		parameter integer C_M01_AXI_BUSER_WIDTH	= 0
	)
	(
		// Users to add ports here
        // Slave와 Master들을 연결할 내부 신호선들

		// User ports ends
		// Do not modify the ports beyond this line


		// Ports of Axi Slave Bus Interface S00_AXI
		input wire  s00_axi_aclk,
		input wire  s00_axi_aresetn,
		input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_awaddr,
		input wire [2 : 0] s00_axi_awprot,
		input wire  s00_axi_awvalid,
		output wire  s00_axi_awready,
		input wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_wdata,
		input wire [(C_S00_AXI_DATA_WIDTH/8)-1 : 0] s00_axi_wstrb,
		input wire  s00_axi_wvalid,
		output wire  s00_axi_wready,
		output wire [1 : 0] s00_axi_bresp,
		output wire  s00_axi_bvalid,
		input wire  s00_axi_bready,
		input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_araddr,
		input wire [2 : 0] s00_axi_arprot,
		input wire  s00_axi_arvalid,
		output wire  s00_axi_arready,
		output wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_rdata,
		output wire [1 : 0] s00_axi_rresp,
		output wire  s00_axi_rvalid,
		input wire  s00_axi_rready,

		// Ports of Axi Master Bus Interface M00_AXI
		input wire  m00_axi_init_axi_txn,
		output wire  m00_axi_txn_done,
		output wire  m00_axi_error,
		input wire  m00_axi_aclk,
		input wire  m00_axi_aresetn,
		output wire [C_M00_AXI_ID_WIDTH-1 : 0] m00_axi_awid,
		output wire [C_M00_AXI_ADDR_WIDTH-1 : 0] m00_axi_awaddr,
		
		
		output wire [7 : 0] m00_axi_awlen,
		output wire [2 : 0] m00_axi_awsize,
		output wire [1 : 0] m00_axi_awburst,
		output wire  m00_axi_awlock,
		output wire [3 : 0] m00_axi_awcache,
		output wire [2 : 0] m00_axi_awprot,
		output wire [3 : 0] m00_axi_awqos,
		output wire [C_M00_AXI_AWUSER_WIDTH-1 : 0] m00_axi_awuser,
		
		output wire m00_axi_arlock,    // [에러 발생 포트]
        output wire [3 : 0] m00_axi_arcache, // [에러 발생 포트]
        output wire [2 : 0] m00_axi_arprot,  // [에러 발생 포트]
        output wire [3 : 0] m00_axi_arqos,    // [에러 발생 포트]
        output wire [C_M00_AXI_ARUSER_WIDTH-1 : 0] m00_axi_aruser, // [에러 발생 포트]
        
        input wire [C_M00_AXI_ID_WIDTH-1 : 0] m00_axi_rid,    // [에러 발생 포트]
        input wire [1 : 0] m00_axi_rresp,   // [에러 발생 포트]
        input wire [C_M00_AXI_RUSER_WIDTH-1 : 0] m00_axi_ruser, // [에러 발생 포트]
        
		output wire  m00_axi_awvalid,
		input wire  m00_axi_awready,
		output wire [C_M00_AXI_DATA_WIDTH-1 : 0] m00_axi_wdata,
		output wire [C_M00_AXI_DATA_WIDTH/8-1 : 0] m00_axi_wstrb,
		output wire  m00_axi_wlast,
		output wire [C_M00_AXI_WUSER_WIDTH-1 : 0] m00_axi_wuser,
		output wire  m00_axi_wvalid,
		input wire  m00_axi_wready,
		input wire [C_M00_AXI_ID_WIDTH-1 : 0] m00_axi_bid,
		input wire [1 : 0] m00_axi_bresp,
		input wire [C_M00_AXI_BUSER_WIDTH-1 : 0] m00_axi_buser,
		input wire  m00_axi_bvalid,
		output wire  m00_axi_bready,
		output wire [C_M00_AXI_ID_WIDTH-1 : 0] m00_axi_arid,
		output wire [C_M00_AXI_ADDR_WIDTH-1 : 0] m00_axi_araddr,
		output wire [7 : 0] m00_axi_arlen,
		output wire [2 : 0] m00_axi_arsize,
		output wire [1 : 0] m00_axi_arburst,
		output wire  m00_axi_arvalid,
		input wire  m00_axi_arready,
		input wire [C_M00_AXI_DATA_WIDTH-1 : 0] m00_axi_rdata,
		input wire  m00_axi_rlast,
		input wire  m00_axi_rvalid,
		output wire  m00_axi_rready,

		// Ports of Axi Master Bus Interface M01_AXI
		input wire  m01_axi_init_axi_txn,
		output wire  m01_axi_txn_done,
		output wire  m01_axi_error,
		input wire  m01_axi_aclk,
		input wire  m01_axi_aresetn,
		output wire [C_M01_AXI_ID_WIDTH-1 : 0] m01_axi_awid,
		output wire [C_M01_AXI_ADDR_WIDTH-1 : 0] m01_axi_awaddr,
		output wire [7 : 0] m01_axi_awlen,
		output wire [2 : 0] m01_axi_awsize,
		output wire [1 : 0] m01_axi_awburst,
		output wire  m01_axi_awlock,
		output wire [3 : 0] m01_axi_awcache,
		output wire [2 : 0] m01_axi_awprot,
		output wire [3 : 0] m01_axi_awqos,
		output wire [C_M01_AXI_AWUSER_WIDTH-1 : 0] m01_axi_awuser,
		output wire  m01_axi_awvalid,
		input wire  m01_axi_awready,
		output wire [C_M01_AXI_DATA_WIDTH-1 : 0] m01_axi_wdata,
		output wire [C_M01_AXI_DATA_WIDTH/8-1 : 0] m01_axi_wstrb,
		output wire  m01_axi_wlast,
		output wire [C_M01_AXI_WUSER_WIDTH-1 : 0] m01_axi_wuser,
		output wire  m01_axi_wvalid,
		input wire  m01_axi_wready,
		input wire [C_M01_AXI_ID_WIDTH-1 : 0] m01_axi_bid,
		input wire [1 : 0] m01_axi_bresp,
		input wire [C_M01_AXI_BUSER_WIDTH-1 : 0] m01_axi_buser,
		input wire  m01_axi_bvalid,
		output wire  m01_axi_bready,
		output wire [C_M01_AXI_ID_WIDTH-1 : 0] m01_axi_arid,
		output wire [C_M01_AXI_ADDR_WIDTH-1 : 0] m01_axi_araddr,
		output wire [7 : 0] m01_axi_arlen,
		output wire [2 : 0] m01_axi_arsize,
		output wire [1 : 0] m01_axi_arburst,
		output wire  m01_axi_arlock,
		output wire [3 : 0] m01_axi_arcache,
		output wire [2 : 0] m01_axi_arprot,
		output wire [3 : 0] m01_axi_arqos,
		output wire [C_M01_AXI_ARUSER_WIDTH-1 : 0] m01_axi_aruser,
		output wire  m01_axi_arvalid,
		input wire  m01_axi_arready,
		input wire [C_M01_AXI_ID_WIDTH-1 : 0] m01_axi_rid,
		input wire [C_M01_AXI_DATA_WIDTH-1 : 0] m01_axi_rdata,
		input wire [1 : 0] m01_axi_rresp,
		input wire  m01_axi_rlast,
		input wire [C_M01_AXI_RUSER_WIDTH-1 : 0] m01_axi_ruser,
		input wire  m01_axi_rvalid,
		output wire  m01_axi_rready,
		
		input wire i_btn_start // 버튼 연결용 핀
	);
	
// Add user logic here
// =========================================================================
// [Step 1] 내부 연결 신호(Wire) 선언
// =========================================================================
    // Slave -> Master 전달용
    wire [31:0] src_addr_w;
    wire [31:0] dst_addr_w;
    wire [31:0] trf_len_w;
//  wire        dma_start_w;
    wire sw_start_w;  // 소프트웨어(AXI)에서 나오는 시작 신호
    wire real_start;  // 실제 동작 신호
    
    wire        dma_done_w;
    wire        rd_done_w;    // Read Master 완료 신호용 추가
    wire        wr_done_w;    // Write Master 완료 신호용 추가
    
    // Master <-> FIFO 연결용
    wire        fifo_wr_en;
    wire [31:0] fifo_din;
    wire        fifo_full;
    wire        fifo_rd_en;
    wire [31:0] fifo_dout;
    wire        fifo_empty;

    // =========================================================================
    // [Step 2] AXI Lite Slave 인스턴스 (CPU 인터페이스)
    // =========================================================================
    Top_DMA_slave_lite_v1_0_S00_AXI # ( 
        .C_S_AXI_DATA_WIDTH(C_S00_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_S00_AXI_ADDR_WIDTH)
    ) Slave_inst (
        .o_src_addr  (src_addr_w),
        .o_dst_addr  (dst_addr_w),
        .o_trf_len   (trf_len_w),
        .o_dma_start (sw_start_w),
        .i_dma_done  (dma_done_w),   // 최종 완료 신호 연결
        
        // AXI 표준 포트 연결 
        .S_AXI_ACLK   (s00_axi_aclk),
        .S_AXI_ARESETN(s00_axi_aresetn),
        .S_AXI_AWADDR (s00_axi_awaddr),
        .S_AXI_AWVALID(s00_axi_awvalid),
        .S_AXI_AWREADY(s00_axi_awready),
        .S_AXI_WDATA  (s00_axi_wdata),
        .S_AXI_WSTRB  (s00_axi_wstrb),
        .S_AXI_WVALID (s00_axi_wvalid),
        .S_AXI_WREADY (s00_axi_wready),
        .S_AXI_BVALID (s00_axi_bvalid),
        .S_AXI_BREADY (s00_axi_bready),
        .S_AXI_ARADDR (s00_axi_araddr),
        .S_AXI_ARVALID(s00_axi_arvalid),
        .S_AXI_ARREADY(s00_axi_arready),
        .S_AXI_RDATA  (s00_axi_rdata),
        .S_AXI_RVALID (s00_axi_rvalid),
        .S_AXI_RREADY (s00_axi_rready),
        .S_AXI_BRESP  (s00_axi_bresp),
        .S_AXI_RRESP  (s00_axi_rresp),
        .S_AXI_AWPROT (s00_axi_awprot),
        .S_AXI_ARPROT (s00_axi_arprot)
    );
    
    // =========================================================================
    // [Step 3] Read Master 인스턴스 (M00: Memory -> FIFO)
    // =========================================================================
    Top_DMA_master_full_v1_0_M00_AXI # (
        .C_M_AXI_BURST_LEN(C_M00_AXI_BURST_LEN),
        .C_M_AXI_ADDR_WIDTH(C_M00_AXI_ADDR_WIDTH),
        .C_M_AXI_DATA_WIDTH(C_M00_AXI_DATA_WIDTH)
    ) Read_Master_inst (
        // 유저 인터페이스 연결
        .i_start      (real_start),
        .i_src_addr   (src_addr_w),
        .i_total_len  (trf_len_w),
        .o_fifo_push  (fifo_wr_en),
        .o_r_data     (fifo_din),
        .i_fifo_full  (fifo_full),
        .o_read_done  (rd_done_w), // 필요시 연결

        // AXI 표준 포트 연결
        .M_AXI_ACLK   (m00_axi_aclk),
        .M_AXI_ARESETN(m00_axi_aresetn),
        .M_AXI_ARADDR (m00_axi_araddr),
        .M_AXI_ARLEN  (m00_axi_arlen),
        .M_AXI_ARSIZE (m00_axi_arsize),
        .M_AXI_ARBURST(m00_axi_arburst),
        .M_AXI_ARVALID(m00_axi_arvalid),
        .M_AXI_ARREADY(m00_axi_arready),
        .M_AXI_RDATA  (m00_axi_rdata),
        .M_AXI_RLAST  (m00_axi_rlast),
        .M_AXI_RVALID (m00_axi_rvalid),
        .M_AXI_RREADY (m00_axi_rready),
        
        // --- Read Address Channel ---
        .M_AXI_ARID    (m00_axi_arid)

    );

    // =========================================================================
    // [Step 4] Write Master 인스턴스 (M01: FIFO -> Memory)
    // =========================================================================
    Top_DMA_master_full_v1_0_M01_AXI # (
        .C_M_AXI_BURST_LEN(C_M01_AXI_BURST_LEN),
        .C_M_AXI_ADDR_WIDTH(C_M01_AXI_ADDR_WIDTH),
        .C_M_AXI_DATA_WIDTH(C_M01_AXI_DATA_WIDTH)
    ) Write_Master_inst (
        // 유저 인터페이스 연결
        .i_start      (real_start),
        .i_dst_addr   (dst_addr_w),
        .i_total_len  (trf_len_w),
        .i_w_data     (fifo_dout),
        .i_fifo_empty (fifo_empty),
        .o_fifo_rd_en (fifo_rd_en),
        .o_write_done (wr_done_w), // 이 신호가 Slave로 가서 완료를 알림

        // AXI 표준 포트 연결 (M01 Write Master)
        .M_AXI_ACLK    (m01_axi_aclk),
        .M_AXI_ARESETN (m01_axi_aresetn),
        
        // Write Address Channel
        .M_AXI_AWID    (m01_axi_awid),
        .M_AXI_AWADDR  (m01_axi_awaddr),
        .M_AXI_AWLEN   (m01_axi_awlen),
        .M_AXI_AWSIZE  (m01_axi_awsize),
        .M_AXI_AWBURST (m01_axi_awburst),
        .M_AXI_AWLOCK  (m01_axi_awlock),
        .M_AXI_AWCACHE (m01_axi_awcache),
        .M_AXI_AWPROT  (m01_axi_awprot),
        .M_AXI_AWQOS   (m01_axi_awqos),
        .M_AXI_AWUSER  (m01_axi_awuser),
        .M_AXI_AWVALID (m01_axi_awvalid),
        .M_AXI_AWREADY (m01_axi_awready),
        
        // Write Data Channel
        .M_AXI_WDATA   (m01_axi_wdata),
        .M_AXI_WSTRB   (m01_axi_wstrb),
        .M_AXI_WLAST   (m01_axi_wlast),
        .M_AXI_WUSER   (m01_axi_wuser),
        .M_AXI_WVALID  (m01_axi_wvalid),
        .M_AXI_WREADY  (m01_axi_wready),
        
        // Write Response Channel
        .M_AXI_BID     (m01_axi_bid),
        .M_AXI_BRESP   (m01_axi_bresp),
        .M_AXI_BUSER   (m01_axi_buser),
        .M_AXI_BVALID  (m01_axi_bvalid),
        .M_AXI_BREADY  (m01_axi_bready)
    );

    // =========================================================================
    // [Step 5] FIFO Generator 인스턴스
    // =========================================================================
    fifo_generator_0 FIFO_inst (
        .clk  (s00_axi_aclk),
        .srst (!s00_axi_aresetn),
        .din  (fifo_din),
        .wr_en(fifo_wr_en),
        .rd_en(fifo_rd_en),
        .dout (fifo_dout),
        .full (fifo_full),
        .empty(fifo_empty)
    );
    
    assign real_start = sw_start_w | i_btn_start;
   
    // [중요] 내부 완료 신호와 외부 완료 포트를 연결합니다.
    assign dma_done_w       = wr_done_w; // 쓰기까지 끝나야 전체 DMA 완료
    assign m00_axi_txn_done = rd_done_w; // Read 채널 완료 상태 출력
    assign m01_axi_txn_done = wr_done_w; // Write 채널 완료 상태 출력

    // 에러 신호를 사용하지 않는다면 0으로 고정합니다.
    assign m00_axi_error    = 1'b0;
    assign m01_axi_error    = 1'b0;    
    // =========================================================================
    // [Top_DMA.v 내부] 래퍼에는 없지만, 외부(BD)가 요구하는 신호들 처리
    // =========================================================================
    
    // M00 (Read Master)가 외부로 내보내는 핀들 중, 래퍼(M00_AXI)가 안 쓰는 것들
    assign m00_axi_awid    = 'b0;
    assign m00_axi_awaddr  = 'b0;
    assign m00_axi_awlen   = 'b0;
    assign m00_axi_awsize  = 3'b010; // 4 bytes
    assign m00_axi_awburst = 2'b01;  // INCR
    assign m00_axi_awlock  = 1'b0;
    assign m00_axi_awcache = 4'b0010;
    assign m00_axi_awprot  = 3'b000;
    assign m00_axi_awqos   = 4'b0000;
    assign m00_axi_awuser  = 'b0;
    assign m00_axi_awvalid = 1'b0;
    assign m00_axi_wdata   = 'b0;
    assign m00_axi_wstrb   = 'b0;
    assign m00_axi_wlast   = 1'b0;
    assign m00_axi_wvalid  = 1'b0;
    assign m00_axi_bready  = 1'b0;
    
    // 에러가 났던 AR 관련 미사용 핀들
    assign m00_axi_arlock  = 1'b0;
    assign m00_axi_arcache = 4'b0010;
    assign m00_axi_arprot  = 3'b000;
    assign m00_axi_arqos   = 4'b0000;
    assign m00_axi_aruser  = 'b0;
	// User logic ends

	endmodule