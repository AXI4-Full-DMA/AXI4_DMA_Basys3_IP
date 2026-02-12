`timescale 1ns / 1ps

/**
 * Read_Master Module
 * 기능: AXI4-Full 프로토콜을 사용하여 외부 메모리로부터 데이터를 읽어 내부 FIFO로 전달함.
 * 특징: 4KB Boundary 제약 조건을 자동으로 계산하여 Burst를 분할 전송함.
 */
module Read_Master # (
    parameter integer C_M_AXI_ID_WIDTH   = 1,
    parameter integer C_M_AXI_ADDR_WIDTH = 32,
    parameter integer C_M_AXI_DATA_WIDTH = 32
)(
    input wire clk,
    input wire reset_n,

    // --- 사용자 제어 신호 (User Control) ---
    input wire i_start,                // DMA 읽기 동작 시작 트리거
    input wire [31:0] i_src_addr,      // 읽기 시작할 소스 메모리 주소
    input wire [31:0] i_total_len,     // 읽을 총 데이터 길이 (Bytes)
    output reg o_read_done,            // 전체 데이터 전송 완료 플래그

    // --- FIFO 인터페이스 ---
    input wire i_fifo_full,            // FIFO 가득 참 신호 (Backpressure 용)
    output wire o_fifo_push,           // FIFO 쓰기 활성화 신호
    output wire [31:0] o_r_data,       // FIFO로 보낼 읽기 데이터

    // --- AXI4-Full: Read Address Channel (AR) ---
    output wire [C_M_AXI_ADDR_WIDTH-1 : 0] m_axi_araddr,  // 읽기 주소
    output wire [7 : 0] m_axi_arlen,                     // 버스트 길이 (AxLEN)
    output wire [2 : 0] m_axi_arsize,                    // 비트 폭 (AxSIZE)
    output wire [1 : 0] m_axi_arburst,                   // 버스트 타입 (AxBURST)
    output wire m_axi_arvalid,                           // 주소 유효 신호
    input  wire m_axi_arready,                           // 슬레이브 준비 완료 신호

    // --- AXI4-Full: Read Data Channel (R) ---
    input  wire [C_M_AXI_DATA_WIDTH-1 : 0] m_axi_rdata,  // 수신 데이터
    input  wire m_axi_rlast,                             // 버스트의 마지막 데이터 표시
    input  wire m_axi_rvalid,                            // 수신 데이터 유효 신호
    output wire m_axi_rready                             // 마스터 준비 완료 신호
);

    // --- FSM 상태 정의 ---
    localparam IDLE       = 3'b001;    // 유휴 상태
    localparam ADDR_PHASE = 3'b010;    // AXI 주소 핸드셰이크 단계
    localparam DATA_PHASE = 3'b100;    // 데이터 수신 및 FIFO 전송 단계

    reg [2:0] current_state, next_state;

    // --- 내부 레지스터 ---
    reg [31:0] r_current_addr;         // 현재 진행 중인 읽기 주소
    reg [31:0] r_remaining_bytes;      // 남은 전체 전송 바이트 수
    reg [7:0]  r_burst_len;            // 현재 버스트에서 전송할 Word 개수
    reg        arvalid_reg;            // m_axi_arvalid 출력을 제어하는 레지스터

    // --- 계산용 와이어 (Burst Size & Boundary Check) ---
    wire [31:0] next_boundary_addr;    // 다음 4KB 경계 주소
    wire [31:0] dist_to_boundary;      // 현재 주소에서 경계까지 남은 거리
    wire [31:0] max_burst_bytes;       // 잔여 데이터와 최대 버스트(64B) 중 최소값
    wire [31:0] calc_len_bytes;        // 경계 제약을 고려한 최종 버스트 바이트 크기
    wire [31:0] current_transfer_bytes;// 이번 버스트로 전송된 총 바이트 수

    // -------------------------------------------------------------------------
    // 1. 계산 로직 (AXI 4KB Boundary 분할 처리 핵심)
    // -------------------------------------------------------------------------
    // 차기 4KB 경계 계산: AXI는 한 번의 버스트가 4KB 경계를 넘을 수 없음
    assign next_boundary_addr = (r_current_addr & 32'hFFFF_F000) + 32'h1000;
    assign dist_to_boundary   = next_boundary_addr - r_current_addr;
    
    // 버스트 크기 결정: 한 번의 버스트는 최대 64바이트 제한
    assign max_burst_bytes    = (r_remaining_bytes > 64) ? 64 : r_remaining_bytes;
    
    // 경계 침범 방지: 경계까지 남은 거리와 계획된 버스트 크기 중 작은 쪽 선택
    assign calc_len_bytes     = (max_burst_bytes > dist_to_boundary) ? dist_to_boundary : max_burst_bytes;
    
    // 현재 전송 바이트 수: (버스트 개수 + 1) * 4바이트 (32bit 폭 기준)
    assign current_transfer_bytes = {22'd0, r_burst_len, 2'b00};

    // -------------------------------------------------------------------------
    // 2. AXI 주소 채널 출력 설정 (Output Logic)
    // -------------------------------------------------------------------------
    assign m_axi_arsize  = 3'b010;     // 4 Bytes (32-bit) 전송 고정
    assign m_axi_arburst = 2'b01;     // INCR 타입 (주소 증가 방식) 버스트
    assign m_axi_araddr  = r_current_addr;
    assign m_axi_arvalid = arvalid_reg; 
    
    // AxLEN 계산: (전송바이트 / 4) - 1 (0이면 1개 전송, 15이면 16개 전송)
    assign m_axi_arlen   = (calc_len_bytes[9:2] > 0) ? (calc_len_bytes[9:2] - 1) : 0;
    
    // RREADY 제어: 데이터 단계이고 FIFO가 가득 차지 않았을 때만 데이터를 받을 준비가 됨
    assign m_axi_rready  = (current_state == DATA_PHASE) && (!i_fifo_full);

    // -------------------------------------------------------------------------
    // 3. FIFO 인터페이스 출력
    // -------------------------------------------------------------------------
    // 슬레이브가 데이터를 주고(rvalid), 마스터가 받을 준비가 되면(rready) FIFO에 Push
    assign o_fifo_push = (m_axi_rvalid && m_axi_rready);
    assign o_r_data    = m_axi_rdata;

    // -------------------------------------------------------------------------
    // 4. 상태 천이 로직 (Next State Combinational Logic)
    // -------------------------------------------------------------------------
    always @(*) begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                if (i_start) next_state = ADDR_PHASE;
            end
            ADDR_PHASE: begin
                // 주소 채널 핸드셰이크 완료 시 데이터 단계로 전환
                if (m_axi_arvalid && m_axi_arready) 
                    next_state = DATA_PHASE;
            end
            DATA_PHASE: begin
                // 마지막 데이터(rlast) 핸드셰이크 완료 시
                if (m_axi_rlast && m_axi_rvalid && m_axi_rready) begin
                    // 잔여 데이터가 없으면 완료(IDLE), 있으면 다음 주소 전송(ADDR_PHASE)
                    if (r_remaining_bytes <= current_transfer_bytes)
                        next_state = IDLE;
                    else
                        next_state = ADDR_PHASE;
                end
            end
            default: next_state = IDLE;
        endcase
    end

    // -------------------------------------------------------------------------
    // 5. ARVALID 제어 로직 (Look-ahead 및 Handshake 관리)
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            arvalid_reg <= 0;
        else begin
            case (current_state)
                IDLE: begin
                    // 동작 시작 즉시 첫 번째 주소 유효 신호 활성화
                    if (i_start) arvalid_reg <= 1;
                    else         arvalid_reg <= 0;
                end

                ADDR_PHASE: begin
                    // 주소 핸드셰이크가 체결되면 즉시 Low (한 번의 버스트에 한 번의 주소)
                    if (arvalid_reg && m_axi_arready)
                        arvalid_reg <= 0;
                end

                DATA_PHASE: begin
                    // 성능 최적화: 버스트가 끝나기 직전 다음 전송이 필요하면 미리 Valid를 준비
                    if (m_axi_rlast && m_axi_rvalid && m_axi_rready) begin
                        if (r_remaining_bytes > current_transfer_bytes)
                            arvalid_reg <= 1; // 차기 주소 단계를 위한 미리 띄우기
                        else
                            arvalid_reg <= 0;
                    end
                end
                
                default: arvalid_reg <= 0;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // 6. 데이터 업데이트 및 레지스터 관리 (Sequential Logic)
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            current_state     <= IDLE;
            r_current_addr    <= 0;
            r_remaining_bytes <= 0;
            r_burst_len       <= 0;
            o_read_done       <= 0;
        end else begin
            current_state <= next_state;

            case (current_state)
                IDLE: begin
                    if (i_start) begin
                            o_read_done <= 0;
                        r_current_addr    <= i_src_addr;   // 초기 주소 로드
                        r_remaining_bytes <= i_total_len;  // 전체 길이 로드
                    end
                end

                ADDR_PHASE: begin
                    // 주소 전송 시 이번 버스트에서 처리할 길이(arlen + 1)를 기록
                    if (m_axi_arvalid && m_axi_arready) begin
                        r_burst_len <= calc_len_bytes[9:2];
                    end
                end

                DATA_PHASE: begin
                    // 한 버스트 완료 시 주소 및 잔여 바이트 업데이트
                    if (m_axi_rlast && m_axi_rvalid && m_axi_rready) begin
                        r_current_addr <= r_current_addr + current_transfer_bytes;
                        
                        if (r_remaining_bytes > current_transfer_bytes)
                            r_remaining_bytes <= r_remaining_bytes - current_transfer_bytes;
                        else begin
                            r_remaining_bytes <= 0;
                            o_read_done       <= 1; // 모든 데이터 전송 완료 알림
                        end
                    end
                end
            endcase
        end
    end
endmodule
