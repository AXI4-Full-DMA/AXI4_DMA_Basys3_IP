`timescale 1ns / 1ps

module Write_Master # (
    parameter integer C_M_AXI_ADDR_WIDTH = 32,
    parameter integer C_M_AXI_DATA_WIDTH = 32,
    parameter integer C_M_AXI_BURST_LEN = 64
)(
    input wire clk,
    input wire reset_n,

    // Control Signals
    input wire i_start,
    input wire [31:0] i_dst_addr,
    // [2D 추가] Write쪽도 이미지 규격으로 제어합니다.
    input wire [31:0] i_img_width,     // 한 줄에 쓸 바이트 수
    input wire [31:0] i_img_height,    // 총 몇 줄을 쓸 것인가
    input wire [31:0] i_img_stride,    // 목적지 메모리의 실제 가로 폭 (보폭)
    output reg o_write_done,

    // FIFO & AXI Interface (기존과 동일)
    input wire i_fifo_empty,
    output wire o_fifo_rd_en,
    input wire [31:0] i_w_data,
    output wire [C_M_AXI_ADDR_WIDTH-1 : 0] m_axi_awaddr,
    output wire [7 : 0] m_axi_awlen,
    output wire [2 : 0] m_axi_awsize,
    output wire [1 : 0] m_axi_awburst,
    output wire m_axi_awvalid,
    input  wire m_axi_awready,
    output wire [C_M_AXI_DATA_WIDTH-1 : 0] m_axi_wdata,
    output wire [C_M_AXI_DATA_WIDTH/8-1 : 0] m_axi_wstrb,
    output wire m_axi_wlast,
    output wire m_axi_wvalid,
    input  wire m_axi_wready,
    input  wire [1 : 0] m_axi_bresp,
    input  wire m_axi_bvalid,
    output wire m_axi_bready
);

    // FSM States
    localparam IDLE       = 4'b0001;
    localparam AW_PHASE   = 4'b0010;
    localparam W_PHASE    = 4'b0100;
    localparam B_PHASE    = 4'b1000;

    reg [3:0] current_state, next_state;

    // Registers
    reg [31:0] r_current_addr;
    reg [31:0] r_line_start_addr;      // [2D 추가] 현재 행의 시작 주소
    reg [31:0] r_line_bytes_done;      // [2D 추가] 현재 행 전송 완료량
    reg [31:0] r_line_count;           // [2D 추가] 현재 행 번호
    reg [7:0]  r_burst_len;
    reg [7:0]  w_beat_count;
    reg        awvalid_reg;

    // Calculation Wires
    wire [31:0] next_boundary_addr;
    wire [31:0] dist_to_boundary;
    wire [31:0] dist_to_line_end;      // [2D 추가] 줄 끝까지 남은 거리
    wire [31:0] max_burst_bytes;
    wire [31:0] calc_len_bytes;
    wire [31:0] current_transfer_bytes;

    // 1. Calculations
    assign next_boundary_addr = (r_current_addr & 32'hFFFF_F000) + 32'h1000;
    assign dist_to_boundary   = next_boundary_addr - r_current_addr;
    
    // [2D 수정] 현재 행의 잔여 바이트 계산
    assign dist_to_line_end   = i_img_width - r_line_bytes_done;
    
    // [2D 수정] 버스트 크기 결정 (최대 64B, 줄 끝, 4KB 경계 중 최소값) 64byte
    assign max_burst_bytes    = (dist_to_line_end > C_M_AXI_BURST_LEN * 4) ? C_M_AXI_BURST_LEN * 4 : dist_to_line_end;
    assign calc_len_bytes     = (max_burst_bytes > dist_to_boundary) ? dist_to_boundary : max_burst_bytes;
    
    assign current_transfer_bytes = {22'd0, r_burst_len, 2'b00}; 

    // AXI Output Assignments (기존 유지)
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
    assign o_fifo_rd_en  = (m_axi_wvalid && m_axi_wready);

    // FSM Next State Logic
    always @(*) begin
        next_state = current_state;
        case (current_state)
            IDLE:     if (i_start) next_state = AW_PHASE;
            AW_PHASE: if (m_axi_awvalid && m_axi_awready) next_state = W_PHASE;
            W_PHASE:  if (m_axi_wlast && m_axi_wvalid && m_axi_wready) next_state = B_PHASE;
            B_PHASE: begin
                if (m_axi_bvalid && m_axi_bready) begin
                    // [2D 수정] 전체 행 전송 완료 여부 판단
                    if (r_line_count >= i_img_height - 1 && r_line_bytes_done + current_transfer_bytes >= i_img_width)
                        next_state = IDLE;
                    else
                        next_state = AW_PHASE;
                end
            end
            default: next_state = IDLE;
        endcase
    end

    // AWVALID Control (Look-ahead)
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) awvalid_reg <= 0;
        else begin
            case (current_state)
                IDLE:     if (i_start) awvalid_reg <= 1;
                AW_PHASE: if (awvalid_reg && m_axi_awready) awvalid_reg <= 0;
                B_PHASE:  if (m_axi_bvalid && m_axi_bready) begin
                            if (!(r_line_count >= i_img_height - 1 && r_line_bytes_done + current_transfer_bytes >= i_img_width))
                                awvalid_reg <= 1;
                          end
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // 핵심 수정: 2D 주소 업데이트 및 행 관리
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            current_state      <= IDLE;
            r_current_addr     <= 0;
            r_line_start_addr  <= 0;
            r_line_bytes_done  <= 0;
            r_line_count       <= 0;
            w_beat_count       <= 0;
            o_write_done       <= 0;
        end else begin
            current_state <= next_state;
            case (current_state)
                IDLE: begin
                    w_beat_count <= 0;
                    if (i_start) begin
                        o_write_done      <= 0;
                        r_current_addr    <= i_dst_addr;
                        r_line_start_addr <= i_dst_addr;
                        r_line_bytes_done <= 0;
                        r_line_count      <= 0;
                    end
                end

                AW_PHASE: begin
                    if (m_axi_awvalid && m_axi_awready)
                        r_burst_len <= calc_len_bytes[9:2];
                end

                W_PHASE: begin
                    if (m_axi_wvalid && m_axi_wready)
                        w_beat_count <= w_beat_count + 1;
                end

                B_PHASE: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        w_beat_count <= 0;
                        
                        // [2D 핵심] 줄 끝 여부에 따른 주소 업데이트
                        if (r_line_bytes_done + current_transfer_bytes >= i_img_width) begin
                            // 다음 줄 시작점으로 점프
                            r_current_addr    <= r_line_start_addr + i_img_stride;
                            r_line_start_addr <= r_line_start_addr + i_img_stride;
                            r_line_bytes_done <= 0;
                            r_line_count      <= r_line_count + 1;
                            
                            if (r_line_count >= i_img_height - 1) o_write_done <= 1;
                        end else begin
                            // 현재 줄 계속 진행
                            r_current_addr    <= r_current_addr + current_transfer_bytes;
                            r_line_bytes_done <= r_line_bytes_done + current_transfer_bytes;
                        end
                    end
                end
            endcase
        end
    end

endmodule
