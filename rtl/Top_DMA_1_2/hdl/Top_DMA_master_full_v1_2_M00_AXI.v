`timescale 1 ns / 1 ps

/**
 * Top_DMA_master_full_v1_0_M00_AXI Module
 * 기능: DMA의 Read Master 채널을 담당하는 최상위 래퍼(Wrapper).
 * 특징: 
 * 1. 실질적인 읽기 로직은 하위 모듈인 'Read_Master'에서 수행함.
 * 2. AXI4-Full 규격을 준수하기 위해 미사용 쓰기 채널(AW, W, B) 포트를 포함함.
 * 3. 쓰기 채널은 모두 비활성(Tie-off) 처리하여 오동작을 방지함.
 */
module Top_DMA_master_full_v1_2_M00_AXI #
(
    // --- [1] 파라미터 영역 (AXI 규격 설정) ---
    parameter integer C_M_AXI_BURST_LEN	= 16,     // 기본 버스트 길이
    parameter integer C_M_AXI_ID_WIDTH	= 1,      // AXI ID 폭
    parameter integer C_M_AXI_ADDR_WIDTH	= 32, // 주소 버스 폭
    parameter integer C_M_AXI_DATA_WIDTH	= 32, // 데이터 버스 폭
    parameter integer C_M_AXI_ARUSER_WIDTH	= 0,  // 사용자 정의 AR 채널 폭
    parameter integer C_M_AXI_RUSER_WIDTH	= 0   // 사용자 정의 R 채널 폭
)
(
    // --- [2] 사용자 인터페이스 (DMA 제어 및 FIFO 연결) ---
    input  wire        i_start,      // DMA 동작 시작 신호
    input  wire [31:0] i_src_addr,   // 소스 메모리 시작 주소
    input  wire [31:0] i_total_len,  // 전송할 총 바이트 수
    output wire        o_fifo_push,  // FIFO 쓰기 활성화 신호
    output wire [31:0] o_r_data,     // FIFO 데이터 입력선
    input  wire        i_fifo_full,  // FIFO 가득 참 (Backpressure)
    output wire        o_read_done,  // 모든 데이터 읽기 완료 알림

    // --- [3] AXI4-Full 표준 포트 (Read Channel) ---
    input  wire        M_AXI_ACLK,    // 시스템 클럭
    input  wire        M_AXI_ARESETN, // 리셋 (Active Low)
    output wire        M_AXI_ARID,    // Read Address ID
    output wire [C_M_AXI_ADDR_WIDTH-1 : 0] M_AXI_ARADDR,  // Read Address
    output wire [7 : 0] M_AXI_ARLEN,                      // Burst Length
    output wire [2 : 0] M_AXI_ARSIZE,                     // Burst Size
    output wire [1 : 0] M_AXI_ARBURST,                    // Burst Type
    output wire        M_AXI_ARVALID,                     // Read Address Valid
    input  wire        M_AXI_ARREADY,                     // Read Address Ready
    input  wire [C_M_AXI_DATA_WIDTH-1 : 0] M_AXI_RDATA,   // Read Data
    input  wire        M_AXI_RLAST,                       // Read Last
    input  wire        M_AXI_RVALID,                      // Read Data Valid
    output wire        M_AXI_RREADY,                      // Read Data Ready
     
    // --- [4] 쓰기 채널 포트 (IP 인터페이스 무결성을 위해 유지) ---
    // Read 전용 마스터이나, Vivado AXI 인터페이스 선언을 위해 반드시 포함되어야 함
    output wire [C_M_AXI_ID_WIDTH-1 : 0]    M_AXI_AWID,
    output wire [C_M_AXI_ADDR_WIDTH-1 : 0]  M_AXI_AWADDR, 
    output wire [7 : 0]                     M_AXI_AWLEN,
    output wire [2 : 0]                     M_AXI_AWSIZE,
    output wire [1 : 0]                     M_AXI_AWBURST,
    output wire                             M_AXI_AWLOCK,
    output wire [3 : 0]                     M_AXI_AWCACHE,
    output wire [2 : 0]                     M_AXI_AWPROT,
    output wire [3 : 0]                     M_AXI_AWQOS,
    output wire                             M_AXI_AWVALID, 
    input  wire                             M_AXI_AWREADY, 
    
    output wire [C_M_AXI_DATA_WIDTH-1 : 0]  M_AXI_WDATA,  
    output wire [C_M_AXI_DATA_WIDTH/8-1 : 0] M_AXI_WSTRB,
    output wire                             M_AXI_WLAST,
    output wire                             M_AXI_WVALID,  
    input  wire                             M_AXI_WREADY,  
    
    input  wire [C_M_AXI_ID_WIDTH-1 : 0]    M_AXI_BID,
    input  wire [1 : 0]                     M_AXI_BRESP,
    input  wire                             M_AXI_BVALID,  
    output wire                             M_AXI_BREADY   
);

    // =========================================================================
    // [핵심 로직] Read_Master 코어 인스턴스화
    // =========================================================================
    // 상위 래퍼의 포트들을 실제 동작을 담당하는 u_read_master_core에 매핑함
    
    Read_Master # (
        .C_M_AXI_ADDR_WIDTH(C_M_AXI_ADDR_WIDTH),
        .C_M_AXI_DATA_WIDTH(C_M_AXI_DATA_WIDTH)
    ) u_read_master_core (
        .clk             (M_AXI_ACLK),    
        .reset_n         (M_AXI_ARESETN),
        
        // --- 사용자 제어 및 데이터 연결 ---
        .i_start         (i_start),
        .i_src_addr      (i_src_addr),
        .i_total_len     (i_total_len),
        .o_read_done     (o_read_done),
        .o_fifo_push     (o_fifo_push),
        .o_r_data        (o_r_data),
        .i_fifo_full     (i_fifo_full),
        
        // --- AXI 표준 읽기 채널 연결 ---
        .m_axi_araddr    (M_AXI_ARADDR),
        .m_axi_arlen     (M_AXI_ARLEN),
        .m_axi_arsize    (M_AXI_ARSIZE),
        .m_axi_arburst   (M_AXI_ARBURST),
        .m_axi_arvalid   (M_AXI_ARVALID),
        .m_axi_arready   (M_AXI_ARREADY),
        .m_axi_rdata     (M_AXI_RDATA),
        .m_axi_rlast     (M_AXI_RLAST),
        .m_axi_rvalid    (M_AXI_RVALID),
        .m_axi_rready    (M_AXI_RREADY)
    );

    // =========================================================================
    // [보안 로직] 미사용 쓰기 채널 비활성화 (Tie-off)
    // =========================================================================
    // Read 전용 마스터이므로 쓰기 관련 신호는 모두 안전하게 무효화 처리함
    assign M_AXI_AWID    = 'b0;
    assign M_AXI_AWADDR  = 'b0;
    assign M_AXI_AWLEN   = 'b0;
    assign M_AXI_AWSIZE  = 3'b010; // 4 Bytes (기본 폭)
    assign M_AXI_AWBURST = 2'b01;  // INCR
    assign M_AXI_AWLOCK  = 1'b0;
    assign M_AXI_AWCACHE = 4'b0010;
    assign M_AXI_AWPROT  = 3'b000;
    assign M_AXI_AWQOS   = 4'b0000;
    assign M_AXI_AWVALID = 1'b0;    // 중요: 쓰기 요청을 영구적으로 차단
    
    assign M_AXI_WDATA   = 'b0;
    assign M_AXI_WSTRB   = 'b0;
    assign M_AXI_WLAST   = 1'b0;
    assign M_AXI_WVALID  = 1'b0;    // 중요: 쓰기 데이터 유효 신호 차단
    
    assign M_AXI_BREADY  = 1'b0;    // 쓰기 응답 수신 거부
    assign M_AXI_ARID    = 'b0;     // 읽기 ID 0번 고정

endmodule