
`timescale 1 ns / 1 ps

module Top_DMA_2D_master_full_v1_0_M01_AXI #
(
    parameter integer C_M_AXI_BURST_LEN     = 16,
    parameter integer C_M_AXI_ID_WIDTH      = 1,
    parameter integer C_M_AXI_ADDR_WIDTH    = 32,
    parameter integer C_M_AXI_DATA_WIDTH    = 32,
    parameter integer C_M_AXI_AWUSER_WIDTH  = 0,
    parameter integer C_M_AXI_WUSER_WIDTH   = 0,
    parameter integer C_M_AXI_BUSER_WIDTH   = 0
)
(
    // --- [1] 사용자 인터페이스 (2D 파라미터로 확장) ---
    input  wire        i_start,
    input  wire [31:0] i_dst_addr,
    // [2D 추가] 기존 i_total_len을 대체하거나 보완합니다.
    input  wire [31:0] i_img_width,  // 한 줄 전송 폭
    input  wire [31:0] i_img_height, // 전송할 행 개수
    input  wire [31:0] i_img_stride, // 목적지 메모리 보폭
    
    input  wire [31:0] i_w_data,
    input  wire        i_fifo_empty,
    output wire        o_fifo_rd_en,
    output wire        o_write_done,

    // --- [2] AXI4-Full 표준 포트 (기존과 동일) ---
    input  wire  M_AXI_ACLK,
    input  wire  M_AXI_ARESETN,

    output wire [C_M_AXI_ID_WIDTH-1 : 0]      M_AXI_AWID,
    output wire [C_M_AXI_ADDR_WIDTH-1 : 0]    M_AXI_AWADDR,
    output wire [7 : 0]                       M_AXI_AWLEN,
    output wire [2 : 0]                       M_AXI_AWSIZE,
    output wire [1 : 0]                       M_AXI_AWBURST,
    output wire                               M_AXI_AWLOCK,
    output wire [3 : 0]                       M_AXI_AWCACHE,
    output wire [2 : 0]                       M_AXI_AWPROT,
    output wire [3 : 0]                       M_AXI_AWQOS,
    output wire [C_M_AXI_AWUSER_WIDTH-1 : 0]  M_AXI_AWUSER,
    output wire                               M_AXI_AWVALID,
    input  wire                               M_AXI_AWREADY,

    output wire [C_M_AXI_DATA_WIDTH-1 : 0]    M_AXI_WDATA,
    output wire [C_M_AXI_DATA_WIDTH/8-1 : 0]  M_AXI_WSTRB,
    output wire                               M_AXI_WLAST,
    output wire [C_M_AXI_WUSER_WIDTH-1 : 0]   M_AXI_WUSER,
    output wire                               M_AXI_WVALID,
    input  wire                               M_AXI_WREADY,

    input  wire [C_M_AXI_ID_WIDTH-1 : 0]      M_AXI_BID,
    input  wire [1 : 0]                       M_AXI_BRESP,
    input  wire [C_M_AXI_BUSER_WIDTH-1 : 0]   M_AXI_BUSER,
    input  wire                               M_AXI_BVALID,
    output wire                               M_AXI_BREADY,

    // --- [3] 읽기 채널 (미사용 접지) ---
    output wire [C_M_AXI_ADDR_WIDTH-1 : 0]    M_AXI_ARADDR,
    output wire                               M_AXI_ARVALID,
    input  wire                               M_AXI_ARREADY,
    output wire                               M_AXI_RREADY,
    input  wire                               M_AXI_RVALID,
    
    output reg                                ERROR 
);

    // =========================================================================
    // [핵심 로직] Write_Master 코어 인스턴스화 (2D 매핑)
    // =========================================================================
    Write_Master # (
        .C_M_AXI_ADDR_WIDTH (C_M_AXI_ADDR_WIDTH),
        .C_M_AXI_DATA_WIDTH (C_M_AXI_DATA_WIDTH)
    ) u_write_master_core (
        .clk             (M_AXI_ACLK),      
        .reset_n         (M_AXI_ARESETN),
        
        // --- 제어 및 상태 신호 연결 (2D 파라미터 전달) ---
        .i_start         (i_start),
        .i_dst_addr      (i_dst_addr),
        // .i_total_len  (i_total_len), // 1D 제거
        .i_img_width     (i_img_width),
        .i_img_height    (i_img_height),
        .i_img_stride    (i_img_stride),
        .o_write_done    (o_write_done),  
        
        // --- FIFO 인터페이스 연결 ---
        .i_fifo_empty    (i_fifo_empty),
        .o_fifo_rd_en    (o_fifo_rd_en),  
        .i_w_data        (i_w_data),      
        
        // --- AXI AW 채널 연결 ---
        .m_axi_awaddr    (M_AXI_AWADDR),
        .m_axi_awlen     (M_AXI_AWLEN),
        .m_axi_awsize    (M_AXI_AWSIZE),
        .m_axi_awburst   (M_AXI_AWBURST),
        .m_axi_awvalid   (M_AXI_AWVALID),
        .m_axi_awready   (M_AXI_AWREADY),
        
        // --- AXI W 채널 연결 ---
        .m_axi_wdata     (M_AXI_WDATA),
        .m_axi_wstrb     (M_AXI_WSTRB),
        .m_axi_wlast     (M_AXI_WLAST),
        .m_axi_wvalid    (M_AXI_WVALID),
        .m_axi_wready    (M_AXI_WREADY),
        
        // --- AXI B 채널 연결 ---
        .m_axi_bresp     (M_AXI_BRESP),
        .m_axi_bvalid    (M_AXI_BVALID),
        .m_axi_bready    (M_AXI_BREADY)
    );

    // [보안 로직] 미사용 표준 신호 고정 (기존과 동일)
    assign M_AXI_AWID    = 'b0;
    assign M_AXI_AWLOCK  = 1'b0;
    assign M_AXI_AWCACHE = 4'b0010; 
    assign M_AXI_AWPROT  = 3'h0;
    assign M_AXI_AWQOS   = 4'h0;
    assign M_AXI_AWUSER  = 'b1;
    assign M_AXI_WUSER   = 'b0;

    // --- 읽기 채널 비활성화 ---
    assign M_AXI_ARADDR  = 'b0;
    assign M_AXI_ARVALID = 1'b0;
    assign M_AXI_RREADY  = 1'b0;

    // --- 에러 핸들링 ---
    always @(posedge M_AXI_ACLK) begin
        if (!M_AXI_ARESETN) ERROR <= 0;
        else ERROR <= 0; 
    end

endmodule
