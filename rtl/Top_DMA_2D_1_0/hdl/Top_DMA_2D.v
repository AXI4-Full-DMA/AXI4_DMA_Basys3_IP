`timescale 1 ns / 1 ps

/**
 * Top_DMA Module
 * 기능: AXI-Lite Slave, Read/Write Master, 그리고 FIFO를 통합한 전체 DMA 시스템.
 * 구조:
 * 1. Slave_inst: CPU로부터 전송 주소 및 길이를 설정받고 시작 명령을 전달함.
 * 2. Read_Master_inst: 소스 주소에서 데이터를 읽어 FIFO에 저장함 (M00_AXI).
 * 3. Write_Master_inst: FIFO에서 데이터를 꺼내 목적지 주소에 기록함 (M01_AXI).
 * 4. FIFO_inst: 읽기 전송과 쓰기 전송 사이의 속도 차이를 완충하는 버퍼 역할을 함.
 */
module Top_DMA_2D #
(
    // --- [1] 파라미터 영역: 버스 폭 및 버스트 길이 설정 ---
    parameter integer C_S00_AXI_DATA_WIDTH	= 32,
    parameter integer C_S00_AXI_ADDR_WIDTH	= 5,

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
    // --- [2] 외부 포트: AXI Slave 및 Master 인터페이스 ---
    
    // S00_AXI: CPU 제어용 인터페이스
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

    // M00_AXI: 메모리 읽기(Source)용 인터페이스
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
    output wire m00_axi_arlock,    
    output wire [3 : 0] m00_axi_arcache, 
    output wire [2 : 0] m00_axi_arprot,  
    output wire [3 : 0] m00_axi_arqos,    
    output wire [C_M00_AXI_ARUSER_WIDTH-1 : 0] m00_axi_aruser, 
    input wire [C_M00_AXI_ID_WIDTH-1 : 0] m00_axi_rid,    
    input wire [1 : 0] m00_axi_rresp,   
    input wire [C_M00_AXI_RUSER_WIDTH-1 : 0] m00_axi_ruser, 
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

    // M01_AXI: 메모리 쓰기(Destination)용 인터페이스
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
    output wire  m01_axi_rready    
);
	
// -------------------------------------------------------------------------
// [Step 1] 내부 상호 연결 신호(Internal Wires) 정의
// -------------------------------------------------------------------------
    // CPU 명령(Slave)을 마스터들에게 전달하기 위한 제어 신호들
    wire [31:0] src_addr_w;   // 소스 메모리 주소
    wire [31:0] dst_addr_w;   // 목적지 메모리 주소
    wire [31:0] img_width_w;  // 2D 파라미터 전달용 내부 와이어
    wire [31:0] img_height_w;
    wire [31:0] img_stride_w;
    wire sw_start_w;
    
    // 마스터들의 작업 완료 상태를 슬레이브에 보고하기 위한 신호들
    wire        dma_done_w;   // 전체 DMA 완료 (Write까지 완료 시)
    wire        rd_done_w;    // 읽기 마스터 완료
    wire        wr_done_w;    // 쓰기 마스터 완료
    
    // 마스터들과 FIFO 사이의 데이터 및 상태 신호들 (데이터 통로)
    wire        fifo_wr_en;   // FIFO 쓰기 신호 (Read Master가 활성화)
    wire [31:0] fifo_din;     // FIFO 데이터 입력 (Read Master로부터)
    wire        fifo_full;    // FIFO 가득 참 (Read Master 정지용)
    wire        fifo_rd_en;   // FIFO 읽기 신호 (Write Master가 활성화)
    wire [31:0] fifo_dout;    // FIFO 데이터 출력 (Write Master로 전달)
    wire        fifo_empty;   // FIFO 비어 있음 (Write Master 정지용)

// -------------------------------------------------------------------------
// [Step 2] AXI Lite Slave 인스턴스 (CPU 인터페이스)
// -------------------------------------------------------------------------
    // CPU가 메모리 맵 레지스터를 통해 DMA를 제어하고 상태를 읽어가는 모듈
    Top_DMA_2D_slave_lite_v1_0_S00_AXI # ( 
        .C_S_AXI_DATA_WIDTH(C_S00_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_S00_AXI_ADDR_WIDTH)
    ) Slave_inst (
        .o_src_addr  (src_addr_w),
        .o_dst_addr  (dst_addr_w),
        .o_dma_start (sw_start_w),
        .i_dma_done  (dma_done_w),   // 최종 완료 비트를 slv_reg1에 기록
         
         // Slave에서 레지스터 값을 '출력'해서 Master에게 전달
        .o_img_width (img_width_w), 
        .o_img_height(img_height_w),
        .o_img_stride(img_stride_w),      
        
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
    
// -------------------------------------------------------------------------
// [Step 3] Read Master 인스턴스 (M00: Memory -> FIFO)
// -------------------------------------------------------------------------
    // 메모리에서 소스 데이터를 읽어와 FIFO 입구에 밀어넣는 모듈
    Top_DMA_2D_master_full_v1_0_M00_AXI # (
        .C_M_AXI_BURST_LEN(C_M00_AXI_BURST_LEN),
        .C_M_AXI_ADDR_WIDTH(C_M00_AXI_ADDR_WIDTH),
        .C_M_AXI_DATA_WIDTH(C_M00_AXI_DATA_WIDTH)
    ) Read_Master_inst (
        .i_start      (sw_start_w),
        .i_src_addr   (src_addr_w),
        .o_fifo_push  (fifo_wr_en),
        .o_r_data     (fifo_din),
        .i_fifo_full  (fifo_full),
        .o_read_done  (rd_done_w),
        .i_img_width  (img_width_w),  // Slave에서 나온 와이어 연결
        .i_img_height (img_height_w),
        .i_img_stride (img_stride_w),

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
        .M_AXI_ARID   (m00_axi_arid)
    );

// -------------------------------------------------------------------------
// [Step 4] Write Master 인스턴스 (M01: FIFO -> Memory)
// -------------------------------------------------------------------------
    // FIFO 출구에서 데이터를 꺼내 타겟 메모리에 기록하는 모듈
    Top_DMA_2D_master_full_v1_0_M01_AXI # (
        .C_M_AXI_BURST_LEN(C_M01_AXI_BURST_LEN),
        .C_M_AXI_ADDR_WIDTH(C_M01_AXI_ADDR_WIDTH),
        .C_M_AXI_DATA_WIDTH(C_M01_AXI_DATA_WIDTH)
    ) Write_Master_inst (
        .i_start      (sw_start_w),
        .i_dst_addr   (dst_addr_w),
        .i_w_data     (fifo_dout),
        .i_fifo_empty (fifo_empty),
        .o_fifo_rd_en (fifo_rd_en),
        .o_write_done (wr_done_w),
        .i_img_width  (img_width_w),
        .i_img_height (img_height_w),
        .i_img_stride (img_stride_w),

        .M_AXI_ACLK    (m01_axi_aclk),
        .M_AXI_ARESETN (m01_axi_aresetn),
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
        .M_AXI_WDATA   (m01_axi_wdata),
        .M_AXI_WSTRB   (m01_axi_wstrb),
        .M_AXI_WLAST   (m01_axi_wlast),
        .M_AXI_WUSER   (m01_axi_wuser),
        .M_AXI_WVALID  (m01_axi_wvalid),
        .M_AXI_WREADY  (m01_axi_wready),
        .M_AXI_BID     (m01_axi_bid),
        .M_AXI_BRESP   (m01_axi_bresp),
        .M_AXI_BUSER   (m01_axi_buser),
        .M_AXI_BVALID  (m01_axi_bvalid),
        .M_AXI_BREADY  (m01_axi_bready)
    );

// -------------------------------------------------------------------------
// [Step 5] FIFO Generator 인스턴스 (Bridge)
// -------------------------------------------------------------------------
    // 읽기 속도와 쓰기 속도의 불일치를 완충하는 핵심 저장소
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
   
// -------------------------------------------------------------------------
// [Step 6] 신호 할당 및 프로토콜 준수 처리
// -------------------------------------------------------------------------
    // 전체 동작 완료는 데이터가 목적지에 다 쓰여진(wr_done_w) 시점으로 판단
    assign dma_done_w        = wr_done_w; 
    assign m00_axi_txn_done = rd_done_w; 
    assign m01_axi_txn_done = wr_done_w; 

    // 현재 설계에서는 에러 검출 로직이 비활성화되어 있어 0으로 고정
    assign m00_axi_error    = 1'b0;
    assign m01_axi_error    = 1'b0;    
    
    // M00(Read Master) 채널에서 사용하지 않는 쓰기 포트 및 기타 포트들 접지(Tie-off)
    assign m00_axi_awid    = 'b0;
    assign m00_axi_awaddr  = 'b0;
    assign m00_axi_awlen   = 'b0;
    assign m00_axi_awsize  = 3'b010; // 4 Bytes 고정
    assign m00_axi_awburst = 2'b01;  // INCR
    assign m00_axi_awlock  = 1'b0;
    assign m00_axi_awcache = 4'b0010;
    assign m00_axi_awprot  = 3'b000;
    assign m00_axi_awqos   = 4'b0000;
    assign m00_axi_awuser  = 'b0;
    assign m00_axi_awvalid = 1'b0;   // 중요: 읽기 채널의 쓰기 요청 차단
    assign m00_axi_wdata   = 'b0;
    assign m00_axi_wstrb   = 'b0;
    assign m00_axi_wlast   = 1'b0;
    assign m00_axi_wvalid  = 1'b0;   // 중요: 읽기 채널의 데이터 쓰기 차단
    assign m00_axi_bready  = 1'b0;
    
    // M00 읽기 주소 채널의 미사용 추가 신호들 접지
    assign m00_axi_arlock  = 1'b0;
    assign m00_axi_arcache = 4'b0010;
    assign m00_axi_arprot  = 3'b000;
    assign m00_axi_arqos   = 4'b0000;
    assign m00_axi_aruser  = 'b0;
    
    // M01 (Write Master)는 읽기 동작을 하지 않으므로 AR 채널 비활성화
    assign m01_axi_araddr  = 'b0;
    assign m01_axi_arlen   = 'b0;
    assign m01_axi_arsize  = 3'b010;
    assign m01_axi_arburst = 2'b01;
    assign m01_axi_arvalid = 1'b0;  // 읽기 요청 차단
    assign m01_axi_rready  = 1'b0;
    assign m01_axi_arid    = 'b0;
    assign m01_axi_arlock  = 1'b0;
    assign m01_axi_arcache = 4'b0010;
    assign m01_axi_arprot  = 3'b000;
    assign m01_axi_arqos   = 4'b0000;
    assign m01_axi_aruser  = 'b0;

endmodule
