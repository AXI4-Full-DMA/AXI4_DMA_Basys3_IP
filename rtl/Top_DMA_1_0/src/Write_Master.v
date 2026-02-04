`timescale 1ns / 1ps

module Write_Master # (
    parameter integer C_M_AXI_ADDR_WIDTH = 32,
    parameter integer C_M_AXI_DATA_WIDTH = 32
)(
    input wire clk,
    input wire reset_n,

    // Control Signals
    input wire i_start,
    input wire [31:0] i_dst_addr,
    input wire [31:0] i_total_len,
    output reg o_write_done,

    // FIFO Interface
    input wire i_fifo_empty,
    output wire o_fifo_rd_en,
    input wire [31:0] i_w_data,

    // AXI4-Full Master (AW Channel)
    output wire [C_M_AXI_ADDR_WIDTH-1 : 0] m_axi_awaddr,
    output wire [7 : 0] m_axi_awlen,
    output wire [2 : 0] m_axi_awsize,
    output wire [1 : 0] m_axi_awburst,
    output wire m_axi_awvalid,
    input  wire m_axi_awready,

    // AXI4-Full Master (W Channel)
    output wire [C_M_AXI_DATA_WIDTH-1 : 0] m_axi_wdata,
    output wire [C_M_AXI_DATA_WIDTH/8-1 : 0] m_axi_wstrb,
    output wire m_axi_wlast,
    output wire m_axi_wvalid,
    input  wire m_axi_wready,

    // AXI4-Full Master (B Channel)
    input  wire [1 : 0] m_axi_bresp,
    input  wire m_axi_bvalid,
    output wire m_axi_bready
);

    // FSM States
    localparam IDLE       = 4'b0001;
    localparam AW_PHASE   = 4'b0010;
    localparam W_PHASE    = 4'b0100;
    localparam B_PHASE    = 4'b1000; // Write Response 대기 상태 추가

    reg [3:0] current_state, next_state;

    // Registers
    reg [31:0] r_current_addr;
    reg [31:0] r_remaining_bytes;
    reg [7:0]  r_burst_len;
    reg [7:0]  w_beat_count; // 현재 버스트 내 전송 횟수 카운트
    reg        awvalid_reg;

    // Calculation Wires (Read_Master와 동일 로직) [cite: 46, 47, 48]
    wire [31:0] next_boundary_addr;
    wire [31:0] dist_to_boundary;
    wire [31:0] max_burst_bytes;
    wire [31:0] calc_len_bytes;
    wire [31:0] current_transfer_bytes;

    // -------------------------------------------------------------------------
    // 1. Calculations [cite: 46, 47, 48]
    // -------------------------------------------------------------------------
    assign next_boundary_addr = (r_current_addr & 32'hFFFF_F000) + 32'h1000;
    assign dist_to_boundary   = next_boundary_addr - r_current_addr;
    assign max_burst_bytes    = (r_remaining_bytes > 64) ? 64 : r_remaining_bytes;
    assign calc_len_bytes     = (max_burst_bytes > dist_to_boundary) ? dist_to_boundary : max_burst_bytes;
    assign current_transfer_bytes = {22'd0, r_burst_len, 2'b00}; 

    // -------------------------------------------------------------------------
    // 2. AXI Output Assignments
    // -------------------------------------------------------------------------
    assign m_axi_awsize  = 3'b010;
    assign m_axi_awburst = 2'b01;
    assign m_axi_awaddr  = r_current_addr;
    assign m_axi_awvalid = awvalid_reg;
    assign m_axi_awlen   = (calc_len_bytes[9:2] > 0) ? (calc_len_bytes[9:2] - 1) : 0;

    assign m_axi_wdata   = i_w_data;
    assign m_axi_wstrb   = 4'hF;
    assign m_axi_wvalid  = (current_state == W_PHASE) && (!i_fifo_empty);
    assign m_axi_wlast   = (current_state == W_PHASE) && (w_beat_count == r_burst_len - 1);

    assign m_axi_bready  = (current_state == B_PHASE);

    // -------------------------------------------------------------------------
    // 3. FIFO Interface
    // -------------------------------------------------------------------------
    assign o_fifo_rd_en = (m_axi_wvalid && m_axi_wready);

    // -------------------------------------------------------------------------
    // 4. Next State Logic [cite: 53, 54, 55, 56]
    // -------------------------------------------------------------------------
    always @(*) begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                if (i_start) next_state = AW_PHASE;
            end
            AW_PHASE: begin
                if (m_axi_awvalid && m_axi_awready) 
                    next_state = W_PHASE;
            end
            W_PHASE: begin
                // 마지막 데이터(WLAST) 전송 핸드쉐이크 완료 시 응답 단계로 이동
                if (m_axi_wlast && m_axi_wvalid && m_axi_wready)
                    next_state = B_PHASE;
            end
            B_PHASE: begin
                // Slave로부터 쓰기 완료 응답(BVALID)을 받으면 판단
                if (m_axi_bvalid && m_axi_bready) begin
                    if (r_remaining_bytes == 0)
                        next_state = IDLE;
                    else
                        next_state = AW_PHASE;
                end
            end
            default: next_state = IDLE;
        endcase
    end

    // -------------------------------------------------------------------------
    // 5. AWVALID Control Logic (Look-ahead 적용) [cite: 60, 62, 65]
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            awvalid_reg <= 0;
        else begin
            case (current_state)
                IDLE: begin
                    if (i_start) awvalid_reg <= 1;
                    else         awvalid_reg <= 0;
                end
                AW_PHASE: begin
                    if (awvalid_reg && m_axi_awready)
                        awvalid_reg <= 0;
                end
                B_PHASE: begin
                    // 응답을 받는 시점에 남은 데이터가 있다면 미리 AWVALID를 띄움
                    if (m_axi_bvalid && m_axi_bready && r_remaining_bytes > 0)
                        awvalid_reg <= 1;
                end
                default: awvalid_reg <= 0;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // 6. State Machine & Register Update [cite: 69, 71, 74, 76]
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            current_state     <= IDLE;
            r_current_addr    <= 0;
            r_remaining_bytes <= 0;
            r_burst_len       <= 0;
            w_beat_count      <= 0;
            o_write_done      <= 0;
        end else begin
            current_state <= next_state;
            case (current_state)
                IDLE: begin
                    o_write_done <= 0;
                    if (i_start) begin
                        r_current_addr    <= i_dst_addr;
                        r_remaining_bytes <= i_total_len;
                    end
                end

                AW_PHASE: begin
                    if (m_axi_awvalid && m_axi_awready) begin
                        r_burst_len  <= calc_len_bytes[9:2];
                        w_beat_count <= 0;
                    end
                end

                W_PHASE: begin
                    if (m_axi_wvalid && m_axi_wready) begin
                        w_beat_count <= w_beat_count + 1;
                    end
                end

                B_PHASE: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        r_current_addr <= r_current_addr + current_transfer_bytes;
                        if (r_remaining_bytes > current_transfer_bytes)
                            r_remaining_bytes <= r_remaining_bytes - current_transfer_bytes;
                        else begin
                            r_remaining_bytes <= 0;
                            o_write_done      <= 1;
                        end
                    end
                end
            endcase
        end
    end

endmodule
