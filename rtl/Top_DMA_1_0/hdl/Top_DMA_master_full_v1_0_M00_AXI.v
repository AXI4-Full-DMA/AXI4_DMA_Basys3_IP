`timescale 1 ns / 1 ps

module Top_DMA_master_full_v1_0_M00_AXI #
(
    // [1] 파라미터 영역 (유지)
    parameter integer C_M_AXI_BURST_LEN	= 16,
    parameter integer C_M_AXI_ID_WIDTH	= 1,
    parameter integer C_M_AXI_ADDR_WIDTH	= 32,
    parameter integer C_M_AXI_DATA_WIDTH	= 32,
    parameter integer C_M_AXI_ARUSER_WIDTH	= 0,
    parameter integer C_M_AXI_RUSER_WIDTH	= 0
)
(
    // [2] 사용자 인터페이스 (팀원 이름과 통일 완료)
    input  wire        i_start,      
    input  wire [31:0] i_src_addr,   
    input  wire [31:0] i_total_len,  
    output wire        o_fifo_push,  
    output wire [31:0] o_r_data,     
    input  wire        i_fifo_full,  
    output wire        o_read_done,  

    // [3] AXI 표준 포트 (이름 유지)
    input  wire        M_AXI_ACLK,
    input  wire        M_AXI_ARESETN,
    output wire        M_AXI_ARID,
    output wire [C_M_AXI_ADDR_WIDTH-1 : 0] M_AXI_ARADDR,
    output wire [7 : 0] M_AXI_ARLEN,
    output wire [2 : 0] M_AXI_ARSIZE,
    output wire [1 : 0] M_AXI_ARBURST,
    output wire        M_AXI_ARVALID,
    input  wire        M_AXI_ARREADY,
    input  wire [C_M_AXI_DATA_WIDTH-1 : 0] M_AXI_RDATA,
    input  wire        M_AXI_RLAST,
    input  wire        M_AXI_RVALID,
    output wire        M_AXI_RREADY,
    
    // --- Write Channels (에러 해결을 위해 반드시 추가해야 하는 포트들) ---
    output wire [C_M_AXI_ID_WIDTH-1 : 0]    M_AXI_AWID,
    output wire [C_M_AXI_ADDR_WIDTH-1 : 0]  M_AXI_AWADDR, // 필수
    output wire [7 : 0]                     M_AXI_AWLEN,
    output wire [2 : 0]                     M_AXI_AWSIZE,
    output wire [1 : 0]                     M_AXI_AWBURST,
    output wire                             M_AXI_AWLOCK,
    output wire [3 : 0]                     M_AXI_AWCACHE,
    output wire [2 : 0]                     M_AXI_AWPROT,
    output wire [3 : 0]                     M_AXI_AWQOS,
    output wire                             M_AXI_AWVALID, // 필수
    input  wire                             M_AXI_AWREADY, // 필수
    
    output wire [C_M_AXI_DATA_WIDTH-1 : 0]  M_AXI_WDATA,   // 필수
    output wire [C_M_AXI_DATA_WIDTH/8-1 : 0] M_AXI_WSTRB,
    output wire                             M_AXI_WLAST,
    output wire                             M_AXI_WVALID,  // 필수
    input  wire                             M_AXI_WREADY,  // 필수
    
    input  wire [C_M_AXI_ID_WIDTH-1 : 0]    M_AXI_BID,
    input  wire [1 : 0]                     M_AXI_BRESP,
    input  wire                             M_AXI_BVALID,  // 필수
    output wire                             M_AXI_BREADY   // 필수
);

    // =========================================================================
    // [핵심] 팀원 3의 Read_Master 코드를 연결 (Instantiation)
    // =========================================================================
    // 이제 예전의 always 블록이나 직접 작성한 assign 문은 모두 삭제합니다.
    
    Read_Master # (
        .C_M_AXI_ADDR_WIDTH(C_M_AXI_ADDR_WIDTH),
        .C_M_AXI_DATA_WIDTH(C_M_AXI_DATA_WIDTH)
    ) u_read_master_core (
        .clk             (M_AXI_ACLK),    
        .reset_n         (M_AXI_ARESETN),
        
        // 커스텀 제어 신호 연결
        .i_start         (i_start),
        .i_src_addr      (i_src_addr),
        .i_total_len     (i_total_len),
        .o_read_done     (o_read_done),
        .o_fifo_push     (o_fifo_push),
        .o_r_data        (o_r_data),
        .i_fifo_full     (i_fifo_full),
        
        // AXI 표준 인터페이스 연결
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

    // [참고] 미사용 포트 고정 (쓰기 채널 비활성화)
    assign M_AXI_AWID    = 'b0;
    assign M_AXI_AWADDR  = 'b0;
    assign M_AXI_AWLEN   = 'b0;
    assign M_AXI_AWSIZE  = 3'b010; // 4 bytes
    assign M_AXI_AWBURST = 2'b01;
    assign M_AXI_AWLOCK  = 1'b0;
    assign M_AXI_AWCACHE = 4'b0010;
    assign M_AXI_AWPROT  = 3'b000;
    assign M_AXI_AWQOS   = 4'b0000;
    assign M_AXI_AWVALID = 1'b0;    // 중요: Valid를 0으로 두면 쓰기 동작 안 함
    
    assign M_AXI_WDATA   = 'b0;
    assign M_AXI_WSTRB   = 'b0;
    assign M_AXI_WLAST   = 1'b0;
    assign M_AXI_WVALID  = 1'b0;    // 중요: Valid 0
    
    assign M_AXI_BREADY  = 1'b0;
    assign M_AXI_ARID    = 'b0;     // Read ID도 0으로 고정

endmodule