`timescale 1 ns / 1 ps

module Top_DMA_2D_slave_lite_v1_0_S00_AXI #
(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 5
)
(
    // --- [1] 사용자 포트 수정본 ---
    output wire [31:0] o_src_addr,  
    output wire [31:0] o_dst_addr,  
    output wire        o_dma_start,
    input  wire        i_dma_done,  
    output wire        o_interrupt, 
    
    // 2D 파라미터 (반드시 [31:0] 명시)
    output wire [31:0] o_img_width, 
    output wire [31:0] o_img_height,
    output wire [31:0] o_img_stride,
    
    // --- [2] 표준 AXI4-Lite 인터페이스 포트 ---
    input wire  S_AXI_ACLK,
    input wire  S_AXI_ARESETN,
    input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_AWADDR,
    input wire [2 : 0] S_AXI_AWPROT,
    input wire  S_AXI_AWVALID,
    output wire  S_AXI_AWREADY,
    input wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_WDATA,
    input wire [(C_S_AXI_DATA_WIDTH/8)-1 : 0] S_AXI_WSTRB,
    input wire  S_AXI_WVALID,
    output wire  S_AXI_WREADY,
    output wire [1 : 0] S_AXI_BRESP,
    output wire  S_AXI_BVALID,
    input wire  S_AXI_BREADY,
    input wire [C_S_AXI_ADDR_WIDTH-1 : 0] S_AXI_ARADDR,
    input wire [2 : 0] S_AXI_ARPROT,
    input wire  S_AXI_ARVALID,
    output wire  S_AXI_ARREADY,
    output wire [C_S_AXI_DATA_WIDTH-1 : 0] S_AXI_RDATA,
    output wire [1 : 0] S_AXI_RRESP,
    output wire  S_AXI_RVALID,
    input wire  S_AXI_RREADY
);

    // 내부 AXI 제어용 레지스터
    reg [C_S_AXI_ADDR_WIDTH-1 : 0] 	axi_awaddr;
    reg 	axi_awready;
    reg 	axi_wready;
    reg [1 : 0] 	axi_bresp;
    reg 	axi_bvalid;
    reg [C_S_AXI_ADDR_WIDTH-1 : 0] 	axi_araddr;
    reg 	axi_arready;
    reg [C_S_AXI_DATA_WIDTH-1 : 0] 	axi_rdata;
    reg [1 : 0] 	axi_rresp;
    reg 	axi_rvalid;

    localparam integer ADDR_LSB = (C_S_AXI_DATA_WIDTH/32) + 1;
    localparam integer OPT_MEM_ADDR_BITS = 2;

    // 슬레이브 레지스터 정의
    reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg0; // Control (bit 0: Start)
    reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg1; // Status (bit 0: Done) - Read Only for CPU
    reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg2; // Src Addr
    reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg3; // Dst Addr
    reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg4; // Length
    reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg5;
    reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg6;
    reg [C_S_AXI_DATA_WIDTH-1:0]	slv_reg7;
    
    integer	 byte_index;
    wire [2:0] awaddr_index = (S_AXI_AWVALID) ? S_AXI_AWADDR[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB] : axi_awaddr[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB];

    // AXI 출력 할당
    assign S_AXI_AWREADY = axi_awready;
    assign S_AXI_WREADY  = axi_wready;
    assign S_AXI_BRESP   = axi_bresp;
    assign S_AXI_BVALID  = axi_bvalid;
    assign S_AXI_ARREADY = axi_arready;
    assign S_AXI_RDATA   = axi_rdata;
    assign S_AXI_RRESP   = axi_rresp;
    assign S_AXI_RVALID  = axi_rvalid;

    // --- [Step 1] Write Address & Data 제어 로직 ---
    // (기존 FSM 구조를 유지하면서 Ready 신호 최적화)
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_awready <= 1'b0; axi_wready <= 1'b0; axi_bvalid <= 1'b0; axi_awaddr <= 0;
        end else begin
            // Write Address Ready
            if (!axi_awready && S_AXI_AWVALID && S_AXI_WVALID) axi_awready <= 1'b1;
            else axi_awready <= 1'b0;

            if (S_AXI_AWVALID && S_AXI_AWREADY) axi_awaddr <= S_AXI_AWADDR;

            // Write Data Ready
            if (!axi_wready && S_AXI_WVALID && S_AXI_AWVALID) axi_wready <= 1'b1;
            else axi_wready <= 1'b0;

            // Write Response
            if (axi_awready && S_AXI_AWVALID && axi_wready && S_AXI_WVALID && !axi_bvalid) begin
                axi_bvalid <= 1'b1; axi_bresp <= 2'b0;
            end else if (S_AXI_BREADY && axi_bvalid) axi_bvalid <= 1'b0;
        end
    end

    // --- [Step 2] Slave Register Write 로직 (CPU가 레지스터에 쓸 때) ---
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            slv_reg0 <= 0; slv_reg2 <= 0; slv_reg3 <= 0; slv_reg4 <= 0;
            slv_reg5 <= 0; slv_reg6 <= 0; slv_reg7 <= 0;
        end else begin
            if (S_AXI_WVALID && S_AXI_WREADY) begin
                case (awaddr_index)
                    3'h0: for (byte_index = 0; byte_index <= 3; byte_index = byte_index+1)
                            if (S_AXI_WSTRB[byte_index]) slv_reg0[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    // 3'h1: Status 레지스터(slv_reg1)는 여기서 제외 (Read-Only)
                    3'h2: for (byte_index = 0; byte_index <= 3; byte_index = byte_index+1)
                            if (S_AXI_WSTRB[byte_index]) slv_reg2[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    3'h3: for (byte_index = 0; byte_index <= 3; byte_index = byte_index+1)
                            if (S_AXI_WSTRB[byte_index]) slv_reg3[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    3'h4: for (byte_index = 0; byte_index <= 3; byte_index = byte_index+1)
                            if (S_AXI_WSTRB[byte_index]) slv_reg4[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    3'h5: for (byte_index = 0; byte_index <= 3; byte_index = byte_index+1)
                            if (S_AXI_WSTRB[byte_index]) slv_reg5[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    3'h6: for (byte_index = 0; byte_index <= 3; byte_index = byte_index+1)
                            if (S_AXI_WSTRB[byte_index]) slv_reg6[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                    3'h7: for (byte_index = 0; byte_index <= 3; byte_index = byte_index+1)
                            if (S_AXI_WSTRB[byte_index]) slv_reg7[(byte_index*8) +: 8] <= S_AXI_WDATA[(byte_index*8) +: 8];
                endcase
            end else begin
                // [Auto-clear] Start 비트(slv_reg0[0])는 1클럭만 유지하고 0으로 클리어
                slv_reg0[0] <= 1'b0;
            end
        end
    end

    // --- [Step 3] Status Register & Hardware Feedback 로직 ---
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            slv_reg1 <= 32'h0;
        end else begin
            if (i_dma_done)
                slv_reg1[0] <= 1'b1;  // DMA 완료 시 1 세트
            else if (slv_reg0[0])
                slv_reg1[0] <= 1'b0;  // 새로운 DMA 시작 시 Done 비트 클리어
        end
    end

    // --- [Step 4] Read 로직 (CPU가 레지스터를 읽을 때) ---
    always @(posedge S_AXI_ACLK) begin
        if (S_AXI_ARESETN == 1'b0) begin
            axi_arready <= 1'b0; axi_rvalid <= 1'b0; axi_rdata <= 0;
        end else begin
            if (!axi_arready && S_AXI_ARVALID) axi_arready <= 1'b1;
            else axi_arready <= 1'b0;

            if (S_AXI_ARVALID && S_AXI_ARREADY) begin
                axi_rvalid <= 1'b1;
                axi_araddr <= S_AXI_ARADDR;
                case (S_AXI_ARADDR[ADDR_LSB+OPT_MEM_ADDR_BITS:ADDR_LSB])
                    3'h0: axi_rdata <= slv_reg0;
                    3'h1: axi_rdata <= slv_reg1; // Status 읽기 가능
                    3'h2: axi_rdata <= slv_reg2;
                    3'h3: axi_rdata <= slv_reg3;
                    3'h4: axi_rdata <= slv_reg4;
                    3'h5: axi_rdata <= slv_reg5;
                    3'h6: axi_rdata <= slv_reg6;
                    3'h7: axi_rdata <= slv_reg7;
                    default: axi_rdata <= 0;
                endcase
            end else if (axi_rvalid && S_AXI_RREADY) begin
                axi_rvalid <= 1'b0;
            end
        end
    end

    // --- [5] 외부 출력 할당 ---
    assign o_dma_start = slv_reg0[0];
    assign o_src_addr  = slv_reg2;
    assign o_dst_addr  = slv_reg3;
    assign o_img_width = slv_reg4;
    assign o_img_height= slv_reg5;
    assign o_img_stride= slv_reg6;      
    assign o_interrupt = i_dma_done; // 완료 시 인터럽트 발생

endmodule
