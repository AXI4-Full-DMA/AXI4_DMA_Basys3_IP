`timescale 1ns / 1ps

module Read_Master # (
    parameter integer C_M_AXI_ID_WIDTH   = 1,
    parameter integer C_M_AXI_ADDR_WIDTH = 32,
    parameter integer C_M_AXI_DATA_WIDTH = 32
)(
    input wire clk,
    input wire reset_n,

    // --- 사용자 제어 신호 ---
    input wire i_start,
    input wire [31:0] i_src_addr,      
    // [2D 추가] 이미지 파라미터
    input wire [31:0] i_img_width,     // 한 줄에서 읽을 바이트 수 (Crop Width)
    input wire [31:0] i_img_height,    // 총 읽을 행의 수 (Crop Height)
    input wire [31:0] i_img_stride,    // 원본 이미지의 실제 가로 폭 (Stride)
    output reg o_read_done,

    // --- FIFO & AXI 인터페이스 (기존과 동일) ---
    input wire i_fifo_full,
    output wire o_fifo_push,
    output wire [31:0] o_r_data,
    output wire [C_M_AXI_ADDR_WIDTH-1 : 0] m_axi_araddr,
    output wire [7 : 0] m_axi_arlen,
    output wire [2 : 0] m_axi_arsize,
    output wire [1 : 0] m_axi_arburst,
    output wire m_axi_arvalid,
    input  wire m_axi_arready,
    input  wire [C_M_AXI_DATA_WIDTH-1 : 0] m_axi_rdata,
    input  wire m_axi_rlast,
    input  wire m_axi_rvalid,
    output wire m_axi_rready
);

    // --- FSM 상태 ---
    localparam IDLE       = 3'b001;
    localparam ADDR_PHASE = 3'b010;
    localparam DATA_PHASE = 3'b100;
    reg [2:0] current_state, next_state;

    // --- 내부 레지스터 ---
    reg [31:0] r_current_addr;
    reg [31:0] r_line_start_addr;      // [2D 추가] 현재 행의 시작 주소 기록
    reg [31:0] r_line_bytes_done;      // [2D 추가] 현재 행에서 전송 완료된 바이트 수
    reg [31:0] r_line_count;           // [2D 추가] 현재 몇 번째 행인지 카운트
    reg [7:0]  r_burst_len;
    reg        arvalid_reg;

    // --- 계산용 와이어 ---
    wire [31:0] next_boundary_addr;
    wire [31:0] dist_to_boundary;
    wire [31:0] dist_to_line_end;      // [2D 추가] 현재 줄 끝까지 남은 거리
    wire [31:0] max_burst_bytes;
    wire [31:0] calc_len_bytes;
    wire [31:0] current_transfer_bytes;

    // 1. 계산 로직 수정
    assign next_boundary_addr = (r_current_addr & 32'hFFFF_F000) + 32'h1000;
    assign dist_to_boundary   = next_boundary_addr - r_current_addr;
    
    // [2D 수정] 이번 줄에서 남은 바이트 계산
    assign dist_to_line_end   = i_img_width - r_line_bytes_done;
    
    // [2D 수정] 버스트 크기 결정: 256바이트(64회), 줄 끝, 4KB 경계 중 가장 작은 값 선택
    // 56바이트 버스트(64 beats * 4)
    assign max_burst_bytes    = (dist_to_line_end > 256) ? 256 : dist_to_line_end;
    assign calc_len_bytes     = (max_burst_bytes > dist_to_boundary) ? dist_to_boundary : max_burst_bytes;
    
    assign current_transfer_bytes = {22'd0, r_burst_len, 2'b00};

    // AXI 출력 및 FIFO 인터페이스 (기존과 동일)
    assign m_axi_arsize  = 3'b010;
    assign m_axi_arburst = 2'b01;
    assign m_axi_araddr  = r_current_addr;
    assign m_axi_arvalid = arvalid_reg;
    assign m_axi_arlen   = (calc_len_bytes[9:2] > 0) ? (calc_len_bytes[9:2] - 1) : 0;
    assign m_axi_rready  = (current_state == DATA_PHASE) && (!i_fifo_full);
    assign o_fifo_push   = (m_axi_rvalid && m_axi_rready);
    assign o_r_data      = m_axi_rdata;

    // FSM (상태 천이 로직은 기존 유지 - Sequential에서 점프 처리)
    always @(*) begin
        next_state = current_state;
        case (current_state)
            IDLE:       if (i_start) next_state = ADDR_PHASE;
            ADDR_PHASE: if (m_axi_arvalid && m_axi_arready) next_state = DATA_PHASE;
            DATA_PHASE: begin
                if (m_axi_rlast && m_axi_rvalid && m_axi_rready) begin
                    // [2D 수정] 모든 행을 다 보냈는지 체크
                    if (r_line_count >= i_img_height - 1 && r_line_bytes_done + current_transfer_bytes >= i_img_width)
                        next_state = IDLE;
                    else
                        next_state = ADDR_PHASE;
                end
            end
            default: next_state = IDLE;
        endcase
    end

    // ARVALID 제어 (기존과 동일)
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) arvalid_reg <= 0;
        else begin
            case (current_state)
                IDLE:       if (i_start) arvalid_reg <= 1;
                ADDR_PHASE: if (arvalid_reg && m_axi_arready) arvalid_reg <= 0;
                DATA_PHASE: if (m_axi_rlast && m_axi_rvalid && m_axi_rready) begin
                                if (!(r_line_count >= i_img_height - 1 && r_line_bytes_done + current_transfer_bytes >= i_img_width))
                                    arvalid_reg <= 1;
                            end
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // 핵심 수정: 주소 업데이트 및 행 관리 (Sequential Logic)
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            current_state      <= IDLE;
            r_current_addr     <= 0;
            r_line_start_addr  <= 0;
            r_line_bytes_done  <= 0;
            r_line_count       <= 0;
            o_read_done        <= 0;
        end else begin
            current_state <= next_state;
            case (current_state)
                IDLE: begin
                    if (i_start) begin
                        o_read_done       <= 0;
                        r_current_addr    <= i_src_addr;
                        r_line_start_addr <= i_src_addr; // 첫 번째 줄 시작 주소
                        r_line_bytes_done <= 0;
                        r_line_count      <= 0;
                    end
                end

                ADDR_PHASE: begin
                    if (m_axi_arvalid && m_axi_arready)
                        r_burst_len <= calc_len_bytes[9:2];
                end

                DATA_PHASE: begin
                    if (m_axi_rlast && m_axi_rvalid && m_axi_rready) begin
                        // 1. 현재 줄에서의 진행도 업데이트
                        r_line_bytes_done <= r_line_bytes_done + current_transfer_bytes;

                        // 2. 주소 계산 로직 (줄 끝인가 아닌가?)
                        if (r_line_bytes_done + current_transfer_bytes >= i_img_width) begin
                            // [2D 핵심] 한 줄 끝남 -> Stride 만큼 점프!
                            r_current_addr    <= r_line_start_addr + i_img_stride;
                            r_line_start_addr <= r_line_start_addr + i_img_stride;
                            r_line_bytes_done <= 0;
                            r_line_count      <= r_line_count + 1;

                            if (r_line_count >= i_img_height - 1) o_read_done <= 1;
                        end else begin
                            // 아직 줄이 안 끝남 -> 그냥 다음 주소로
                            r_current_addr <= r_current_addr + current_transfer_bytes;
                        end
                    end
                end
            endcase
        end
    end
endmodule
