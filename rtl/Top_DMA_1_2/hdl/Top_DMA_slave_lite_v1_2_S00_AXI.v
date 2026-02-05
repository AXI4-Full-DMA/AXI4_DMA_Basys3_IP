`timescale 1 ns / 1 ps

/**
 * Top_DMA_slave_lite_v1_0_S00_AXI Module
 * 기능: CPU(Master)로부터 명령을 받고 상태를 보고하는 AXI4-Lite Slave 인터페이스.
 * 레지스터 맵:
 * - slv_reg0: [Control] bit 0은 DMA Start 신호 (o_dma_start)
 * - slv_reg1: [Status]  bit 0은 DMA Done 신호 (i_dma_done에 의해 세트)
 * - slv_reg2: [Source Address] 읽어올 메모리 시작 주소 (o_src_addr)
 * - slv_reg3: [Destination Address] 저장할 메모리 시작 주소 (o_dst_addr)
 * - slv_reg4: [Transfer Length] 전송할 총 바이트 수 (o_trf_len)
 */
module Top_DMA_slave_lite_v1_2_S00_AXI #
(
    parameter integer C_S_AXI_DATA_WIDTH = 32, // 데이터 폭 (32비트)
    parameter integer C_S_AXI_ADDR_WIDTH = 5   // 주소 폭 (8개 레지스터 접근을 위해 5비트 사용)
)
(
    // --- [1] 사용자 포트 (DMA Core 연결용) ---
    output wire [31:0] o_src_addr,  // DMA Read Master로 전달될 소스 주소
    output wire [31:0] o_dst_addr,  // DMA Write Master로 전달될 목적지 주소
    output wire [31:0] o_trf_len,   // 전송할 데이터 크기
    output wire        o_dma_start, // CPU가 명령한 시작 트리거
    input  wire        i_dma_done,  // 하드웨어 작업 완료 알림 (Status 레지스터 반영용)

    // --- [2] 표준 AXI4-Lite 인터페이스 포트 ---
    input wire  S_AXI_ACLK,
    input wire  S_AXI_ARESETN,
    // 쓰기 주소 채널
    input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_AWADDR,
    input wire [2 : 0] S_AXI_AWPROT,
    input wire  S_AXI_AWVALID,
    output wire  S_AXI_AWREADY,
    // 쓰기 데이터 채널
    input wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_WDATA,
    input wire [(C_S_AXI_DATA_WIDTH/8)-1 : 0] S_AXI_WSTRB,
    input wire  S_AXI_WVALID,
    output wire  S_AXI_WREADY,
    // 쓰기 응답 채널
    output wire [1 : 0] S_AXI_BRESP,
    output wire  S_AXI_BVALID,
    input wire  S_AXI_BREADY,
    // 읽기 주소 채널
    input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_ARADDR,
    input wire [2 : 0] S_AXI_ARPROT,
    input wire  S_AXI_ARVALID,
    output wire  S_AXI_ARREADY,
    // 읽기 데이터 채널
    output wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_RDATA,
    output wire [1 : 0] S_AXI_RRESP,
    output wire  S_AXI_RVALID,
    input wire  S_AXI_RREADY
);

    // --- AXI 내부 레지스터 ---
    reg [C_S_AXI_ADDR_WIDTH-1 : 0] 	axi_awaddr;
    reg 	axi_awready;
    reg 	axi_wready;
    reg [1 : 0] 	axi_bresp;
    reg 	axi_bvalid;
    reg [C_S_AXI_ADDR_WIDTH-1 : 0] 	axi_araddr;
    reg 	axi_arready;
    reg [1 : 0] 	axi_rresp;
    reg 	axi_rvalid;

    // 주소 디코딩을 위한 파라미터
    localparam integer ADDR_LSB = (C_S_AXI_DATA_WIDTH/32) + 1;
    localparam integer OPT_MEM_ADDR_BITS = 2;

    // --- [3] 실제 데이터가 저장되는 8개의 슬레이브 레지스터 ---
    reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg0;
    reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg1;
    reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg2;
    reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg3;
    reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg4;
    reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg5;
    reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg6;
    reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg7;
    integer	 byte_index;

    // AXI 출력 신호 할당
    assign S_AXI_AWREADY	= axi_awready;
    assign S_AXI_WREADY	= axi_wready;
    assign S_AXI_BRESP	= axi_bresp;
    assign S_AXI_BVALID	= axi_bvalid;
    assign S_AXI_ARREADY	= axi_arready;
    assign S_AXI_RRESP	= axi_rresp;
    assign S_AXI_RVALID	= axi_rvalid;

    // FSM 변수 및 파라미터
    reg [1:0] state_write;
    reg [1:0] state_read;
    localparam Idle = 2'b00, Raddr = 2'b10, Rdata = 2'b11, Waddr = 2'b10, Wdata = 2'b11;

    // -------------------------------------------------------------------------
    // [Step 1] Write State Machine (CPU -> Slave 레지스터로 데이터 쓰기)
    // -------------------------------------------------------------------------
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_awready <= 0;
            axi_wready <= 0;
            axi_bvalid <= 0;
            axi_bresp <= 0;
            axi_awaddr <= 0;
            state_write <= Idle;
        end else begin
            case(state_write)
                Idle: begin
                    if(S_AXI_ARESETN == 1'b1) begin
                        axi_awready <= 1'b1;
                        axi_wready <= 1'b1;
                        state_write <= Waddr;
                    end
                end
                Waddr: begin
                    // 주소 채널 핸드셰이크 체결
                    if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                        axi_awaddr <= S_AXI_AWADDR;
                        if(S_AXI_WVALID) begin
                            // 데이터가 주소와 함께 왔을 때
                            axi_awready <= 1'b1;
                            state_write <= Waddr;
                            axi_bvalid <= 1'b1;
                        end else begin
                            // 데이터가 아직 안 왔을 때 (데이터 대기 단계로 이동)
                            axi_awready <= 1'b0;
                            state_write <= Wdata;
                            if (S_AXI_BREADY && axi_bvalid) axi_bvalid <= 1'b0;
                        end
                    end else begin
                        state_write <= state_write;
                        if (S_AXI_BREADY && axi_bvalid) axi_bvalid <= 1'b0;
                    end
                end
                Wdata: begin
                    // 데이터 전송 완료 시 다시 주소 수신 가능 상태로 복귀
                    if (S_AXI_WVALID) begin
                        state_write <= Waddr;
                        axi_bvalid <= 1'b1;
                        axi_awready <= 1'b1;
                    end else begin
                        state_write <= state_write;
                        if (S_AXI_BREADY && axi_bvalid) axi_bvalid <= 1'b0;
                    end
                end
                default: state_write <= Idle;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // [Step 2] Slave Register Write Logic (바이트 스트로브 처리 및 하드웨어 피드백)
    // -------------------------------------------------------------------------
    
    always @( posedge S_AXI_ACLK ) begin
        if ( S_AXI_ARESETN == 1'b0 ) begin
            slv_reg0 <= 0; slv_reg1 <= 0; slv_reg2 <= 0; slv_reg3 <= 0;
            slv_reg4 <= 0; slv_reg5 <= 0; slv_reg6 <= 0; slv_reg7 <= 0;
        end else begin
            if (S_AXI_WVALID) begin
                // 주소에 따른 레지스터 선택 및 바이트 단위(WSTRB) 쓰기 수행
                case ( (S_AXI_AWVALID) ? S_AXI_AWADDR[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] : axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] )
                    3'h0: for ( byte_index = 0; byte_index <= 3; byte_index = byte_index+1 )
                            if ( S_AXI_WSTRB[byte_index] == 1 ) slv_reg0[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    3'h1: for ( byte_index = 0; byte_index <= 3; byte_index = byte_index+1 )
                            if ( S_AXI_WSTRB[byte_index] == 1 ) slv_reg1[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    3'h2: for ( byte_index = 0; byte_index <= 3; byte_index = byte_index+1 )
                            if ( S_AXI_WSTRB[byte_index] == 1 ) slv_reg2[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    3'h3: for ( byte_index = 0; byte_index <= 3; byte_index = byte_index+1 )
                            if ( S_AXI_WSTRB[byte_index] == 1 ) slv_reg3[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    3'h4: for ( byte_index = 0; byte_index <= 3; byte_index = byte_index+1 )
                            if ( S_AXI_WSTRB[byte_index] == 1 ) slv_reg4[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    3'h5: for ( byte_index = 0; byte_index <= 3; byte_index = byte_index+1 )
                            if ( S_AXI_WSTRB[byte_index] == 1 ) slv_reg5[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    3'h6: for ( byte_index = 0; byte_index <= 3; byte_index = byte_index+1 )
                            if ( S_AXI_WSTRB[byte_index] == 1 ) slv_reg6[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    3'h7: for ( byte_index = 0; byte_index <= 3; byte_index = byte_index+1 )
                            if ( S_AXI_WSTRB[byte_index] == 1 ) slv_reg7[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    default : begin
                        slv_reg0 <= slv_reg0; slv_reg1 <= slv_reg1; slv_reg2 <= slv_reg2; slv_reg3 <= slv_reg3;
                        slv_reg4 <= slv_reg4; slv_reg5 <= slv_reg5; slv_reg6 <= slv_reg6; slv_reg7 <= slv_reg7;
                    end
                endcase
            end

            // --- [핵심 기능] 하드웨어 상태 업데이트 로직 ---
            // CPU가 쓰는 동작보다 우선순위가 낮게(또는 별도로) 동작하여 현재 DMA의 진행 상태를 레지스터에 기록
            if (i_dma_done) 
                slv_reg1[0] <= 1'b1;         // DMA 작업 완료 시 Status(slv_reg1) 레지스터의 bit 0을 세트
            else if (slv_reg0[0]) 
                slv_reg1[0] <= 1'b0;         // 새로운 DMA 시작(Control 레지스터 bit 0 = 1) 시 완료 비트 클리어
        end
    end

    // -------------------------------------------------------------------------
    // [Step 3] Read State Machine (Slave 레지스터 -> CPU로 데이터 읽기)
    // -------------------------------------------------------------------------
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_arready <= 1'b0; axi_rvalid <= 1'b0; axi_rresp <= 1'b0; state_read <= Idle;
        end else begin
            case(state_read)
                Idle: begin
                    if (S_AXI_ARESETN == 1'b1) begin
                        state_read <= Raddr; axi_arready <= 1'b1;
                    end
                end
                Raddr: begin
                    // 읽기 주소 핸드셰이크 체결 시 데이터 준비 단계로 이동
                    if (S_AXI_ARVALID && S_AXI_ARREADY) begin
                        state_read <= Rdata; axi_araddr <= S_AXI_ARADDR;
                        axi_rvalid <= 1'b1; axi_arready <= 1'b0;
                    end
                end
                Rdata: begin
                    // CPU가 데이터를 가져가면(RREADY) 다시 주소 대기 상태로 복귀
                    if (S_AXI_RVALID && S_AXI_RREADY) begin
                        axi_rvalid <= 1'b0; axi_arready <= 1'b1; state_read <= Raddr;
                    end
                end
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // [Step 4] Read Data Multiplexing (읽기 요청 주소에 따른 레지스터 선택)
    // -------------------------------------------------------------------------
    assign S_AXI_RDATA = 
    (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 3'h0) ? slv_reg0 : 
    (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 3'h1) ? slv_reg1 : 
    (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 3'h2) ? slv_reg2 : 
    (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 3'h3) ? slv_reg3 : 
    (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 3'h4) ? slv_reg4 : 
    (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 3'h5) ? slv_reg5 : 
    (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 3'h6) ? slv_reg6 : 
    (axi_araddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] == 3'h7) ? slv_reg7 : 0; 

    // --- [5] 유저 로직 할당 (레지스터의 값을 외부 DMA 코어로 출력) ---
    assign o_dma_start = slv_reg0[0]; // slv_reg0의 0번 비트를 시작 신호로 사용
    assign o_src_addr  = slv_reg2;    // slv_reg2 전체를 소스 주소로 사용
    assign o_dst_addr  = slv_reg3;    // slv_reg3 전체를 목적지 주소로 사용
    assign o_trf_len   = slv_reg4;    // slv_reg4 전체를 전송 길이로 사용

endmodule