`timescale 1 ns / 1 ps

/**
 * Top_DMA_master_full_v1_0_M01_AXI Module
 * 기능: DMA의 Write Master 채널을 담당하는 최상위 래퍼(Wrapper).
 * 특징: 
 * 1. 실질적인 쓰기 로직과 FSM은 하위 모듈인 'Write_Master'에서 처리함.
 * 2. FIFO로부터 데이터를 읽어와 외부 메모리로 AXI4-Full 프로토콜을 통해 기록함.
 * 3. Write 전용 마스터이므로 미사용 읽기 채널(AR, R)은 비활성(Tie-off) 처리함.
 */
module Top_DMA_master_full_v1_2_M01_AXI #
(
    // --- AXI4-Full 표준 파라미터 ---
    parameter integer C_M_AXI_BURST_LEN     = 16, // 기본 버스트 길이
    parameter integer C_M_AXI_ID_WIDTH      = 1,  // AXI ID 폭
    parameter integer C_M_AXI_ADDR_WIDTH    = 32, // 주소 버스 폭
    parameter integer C_M_AXI_DATA_WIDTH    = 32, // 데이터 버스 폭
    parameter integer C_M_AXI_AWUSER_WIDTH  = 0,  // 사용자 정의 AW 채널 폭
    parameter integer C_M_AXI_WUSER_WIDTH   = 0,  // 사용자 정의 W 채널 폭
    parameter integer C_M_AXI_BUSER_WIDTH   = 0   // 사용자 정의 B 채널 폭
)
(
    // --- [1] 사용자 인터페이스 (DMA 제어 및 FIFO 연결) ---
    input  wire        i_start,      // DMA 동작 시작 트리거 (Write 시작)
    input  wire [31:0] i_dst_addr,   // 데이터를 기록할 목적지 주소
    input  wire [31:0] i_total_len,  // 전송할 총 바이트 수
    input  wire [31:0] i_w_data,     // FIFO로부터 출력된 쓰기 데이터
    input  wire        i_fifo_empty, // FIFO 비어있음 (Backpressure 처리용)
    output wire        o_fifo_rd_en, // FIFO 데이터 읽기 활성화 신호
    output wire        o_write_done, // 모든 데이터 쓰기 완료 플래그

    // --- [2] AXI4-Full 표준 포트 (Write Channels) ---
    input  wire  M_AXI_ACLK,    // 시스템 클럭
    input  wire  M_AXI_ARESETN, // 리셋 (Active Low)

    // Write Address Channel (AW)
    output wire [C_M_AXI_ID_WIDTH-1 : 0]      M_AXI_AWID,    // Write Address ID
    output wire [C_M_AXI_ADDR_WIDTH-1 : 0]    M_AXI_AWADDR,  // Write Address
    output wire [7 : 0]                       M_AXI_AWLEN,   // Burst Length
    output wire [2 : 0]                       M_AXI_AWSIZE,  // Burst Size
    output wire [1 : 0]                       M_AXI_AWBURST, // Burst Type
    output wire                               M_AXI_AWLOCK,  // Lock Type
    output wire [3 : 0]                       M_AXI_AWCACHE, // Cache Type
    output wire [2 : 0]                       M_AXI_AWPROT,  // Protection Type
    output wire [3 : 0]                       M_AXI_AWQOS,   // Quality of Service
    output wire [C_M_AXI_AWUSER_WIDTH-1 : 0]  M_AXI_AWUSER,  // User Signals
    output wire                               M_AXI_AWVALID, // Write Address Valid
    input  wire                               M_AXI_AWREADY, // Write Address Ready

    // Write Data Channel (W)
    output wire [C_M_AXI_DATA_WIDTH-1 : 0]    M_AXI_WDATA,   // Write Data
    output wire [C_M_AXI_DATA_WIDTH/8-1 : 0]  M_AXI_WSTRB,   // Write Strobes
    output wire                               M_AXI_WLAST,   // Write Last
    output wire [C_M_AXI_WUSER_WIDTH-1 : 0]   M_AXI_WUSER,   // User Signals
    output wire                               M_AXI_WVALID,  // Write Valid
    input  wire                               M_AXI_WREADY,  // Write Ready

    // Write Response Channel (B)
    input  wire [C_M_AXI_ID_WIDTH-1 : 0]      M_AXI_BID,     // Response ID
    input  wire [1 : 0]                       M_AXI_BRESP,   // Write Response
    input  wire [C_M_AXI_BUSER_WIDTH-1 : 0]   M_AXI_BUSER,   // User Signals
    input  wire                               M_AXI_BVALID,  // Response Valid
    output wire                               M_AXI_BREADY,  // Response Ready

    // --- [3] 읽기 채널 (Write Master에서는 미사용 처리) ---
    // AXI 표준 인터페이스 준수를 위해 선언만 하고 비활성화 처리함
    output wire [C_M_AXI_ADDR_WIDTH-1 : 0]    M_AXI_ARADDR,
    output wire                               M_AXI_ARVALID,
    input  wire                               M_AXI_ARREADY,
    output wire                               M_AXI_RREADY,
    input  wire                               M_AXI_RVALID,
    
    output reg                                ERROR // 시스템 에러 플래그
);

    // =========================================================================
    // [핵심 로직] Write_Master 코어 인스턴스화
    // =========================================================================
    // 상위 래퍼의 포트들을 실제 동작(FSM, 4KB 경계 계산)을 담당하는 u_write_master_core에 매핑함
    
    Write_Master # (
        .C_M_AXI_ADDR_WIDTH (C_M_AXI_ADDR_WIDTH),
        .C_M_AXI_DATA_WIDTH (C_M_AXI_DATA_WIDTH)
    ) u_write_master_core (
        .clk             (M_AXI_ACLK),      
        .reset_n         (M_AXI_ARESETN),
        
        // --- 제어 및 상태 신호 연결 ---
        .i_start         (i_start),
        .i_dst_addr      (i_dst_addr),
        .i_total_len     (i_total_len),       
        .o_write_done    (o_write_done),  
        
        // --- FIFO 인터페이스 연결 ---
        .i_fifo_empty    (i_fifo_empty),
        .o_fifo_rd_en    (o_fifo_rd_en),  
        .i_w_data        (i_w_data),      
        
        // --- AXI AW (Address Write) 채널 연결 ---
        .m_axi_awaddr    (M_AXI_AWADDR),
        .m_axi_awlen     (M_AXI_AWLEN),
        .m_axi_awsize    (M_AXI_AWSIZE),
        .m_axi_awburst   (M_AXI_AWBURST),
        .m_axi_awvalid   (M_AXI_AWVALID),
        .m_axi_awready   (M_AXI_AWREADY),
        
        // --- AXI W (Data Write) 채널 연결 ---
        .m_axi_wdata     (M_AXI_WDATA),
        .m_axi_wstrb     (M_AXI_WSTRB),
        .m_axi_wlast     (M_AXI_WLAST),
        .m_axi_wvalid    (M_AXI_WVALID),
        .m_axi_wready    (M_AXI_WREADY),
        
        // --- AXI B (Write Response) 채널 연결 ---
        .m_axi_bresp     (M_AXI_BRESP),
        .m_axi_bvalid    (M_AXI_BVALID),
        .m_axi_bready    (M_AXI_BREADY)
    );

    // -------------------------------------------------------------------------
    // [보안 로직] 미사용 표준 신호 고정 (Tie-off)
    // -------------------------------------------------------------------------
    assign M_AXI_AWID    = 'b0;
    assign M_AXI_AWLOCK  = 1'b0;
    assign M_AXI_AWCACHE = 4'b0010; // Normal Non-cacheable Modifiable
    assign M_AXI_AWPROT  = 3'h0;
    assign M_AXI_AWQOS   = 4'h0;
    assign M_AXI_AWUSER  = 'b1;
    assign M_AXI_WUSER   = 'b0;

    // --- 읽기 채널 비활성화 (전기적 안정성 및 버스 충돌 방지) ---
    assign M_AXI_ARADDR  = 'b0;
    assign M_AXI_ARVALID = 1'b0; // 중요: 읽기 요청 원천 차단
    assign M_AXI_RREADY  = 1'b0;

    // --- 에러 핸들링 로직 ---
    always @(posedge M_AXI_ACLK) begin
        if (!M_AXI_ARESETN) ERROR <= 0;
        else ERROR <= 0; // 향후 BRESP 에러 검출 로직 확장 가능 영역
    end

endmodule