`timescale 1ns / 1ps

/**
 * Write_Master Module
 * 기능: 내부 FIFO로부터 데이터를 읽어 AXI4-Full 프로토콜을 통해 외부 메모리에 기록함.
 * 특징: 
 * 1. AXI4 규격에 따른 4KB Boundary 분할 전송 기능 포함.
 * 2. Write Response(B Channel)를 확인하여 전송 완료 및 차기 버스트 진행 결정.
 * 3. AWVALID 신호에 Look-ahead 로직을 적용하여 전송 효율 최적화.
 */
module Write_Master # (
    parameter integer C_M_AXI_ADDR_WIDTH = 32,
    parameter integer C_M_AXI_DATA_WIDTH = 32
)(
    input wire clk,         // 시스템 클럭
    input wire reset_n,     // 리셋 신호 (Active Low)

    // --- 사용자 제어 신호 (User Control) ---
    input wire i_start,               // DMA 쓰기 동작 시작 트리거
    input wire [31:0] i_dst_addr,     // 데이터를 기록할 목적지 메모리 주소
    input wire [31:0] i_total_len,    // 전송할 총 데이터 길이 (Bytes)
    output reg o_write_done,          // 전체 데이터 기록 완료 플래그

    // --- FIFO 인터페이스 ---
    input wire i_fifo_empty,          // FIFO 비어있음 신호 (전송 중단/대기 제어)
    output wire o_fifo_rd_en,         // FIFO 데이터 읽기 활성화 신호
    input wire [31:0] i_w_data,       // FIFO로부터 공급받은 쓰기 데이터

    // --- AXI4-Full: Write Address Channel (AW) ---
    output wire [C_M_AXI_ADDR_WIDTH-1 : 0] m_axi_awaddr,  // 쓰기 시작 주소
    output wire [7 : 0] m_axi_awlen,                     // 버스트 길이 (AxLEN)
    output wire [2 : 0] m_axi_awsize,                    // 전송 크기 (4Bytes 고정)
    output wire [1 : 0] m_axi_awburst,                   // 버스트 타입 (Increment)
    output wire m_axi_awvalid,                           // 주소 유효 신호
    input  wire m_axi_awready,                           // 슬레이브 주소 수신 준비 완료

    // --- AXI4-Full: Write Data Channel (W) ---
    output wire [C_M_AXI_DATA_WIDTH-1 : 0] m_axi_wdata,  // 기록할 데이터
    output wire [C_M_AXI_DATA_WIDTH/8-1 : 0] m_axi_wstrb,// 바이트 스트로브 (4'hF: 전체 유효)
    output wire m_axi_wlast,                             // 버스트의 마지막 데이터 표시
    output wire m_axi_wvalid,                            // 데이터 유효 신호
    input  wire m_axi_wready,                            // 슬레이브 데이터 수신 준비 완료

    // --- AXI4-Full: Write Response Channel (B) ---
    input  wire [1 : 0] m_axi_bresp,                     // 쓰기 응답 상태 (OKAY, EXOKAY 등)
    input  wire m_axi_bvalid,                            // 응답 유효 신호
    output wire m_axi_bready                             // 마스터 응답 수신 준비 완료
);

    // --- FSM 상태 정의 ---
    localparam IDLE       = 4'b0001;   // 유휴 상태
    localparam AW_PHASE   = 4'b0010;   // 주소 전송 단계
    localparam W_PHASE    = 4'b0100;   // 데이터 전송 단계
    localparam B_PHASE    = 4'b1000;   // 쓰기 완료 응답 대기 단계

    reg [3:0] current_state, next_state;

    // --- 내부 레지스터 ---
    reg [31:0] r_current_addr;         // 현재 진행 중인 쓰기 주소
    reg [31:0] r_remaining_bytes;      // 남은 잔여 바이트 수
    reg [7:0]  r_burst_len;            // 현재 버스트에서 전송할 데이터 개수
    reg [7:0]  w_beat_count;           // 버스트 내 현재 전송 횟수 카운터
    reg        awvalid_reg;            // m_axi_awvalid 제어용 레지스터

    // --- 계산용 와이어 (AXI 4KB Boundary Check) ---
    wire [31:0] next_boundary_addr;    // 차기 4KB 경계 주소
    wire [31:0] dist_to_boundary;      // 현재 위치에서 4KB 경계까지의 거리
    wire [31:0] max_burst_bytes;       // 최대 허용 버스트 크기(64B) 내 잔여량
    wire [31:0] calc_len_bytes;        // 최종 결정된 버스트 바이트 크기
    wire [31:0] current_transfer_bytes;// 이번 버스트로 전송 완료된 바이트 수

    // -------------------------------------------------------------------------
    // 1. 계산 로직 (4KB Boundary Violations 방지)
    // -------------------------------------------------------------------------
    // 차기 4KB 경계 주소 계산 (AXI 규격: 한 버스트는 4KB 경계를 넘을 수 없음)
    assign next_boundary_addr = (r_current_addr & 32'hFFFF_F000) + 32'h1000;
    assign dist_to_boundary   = next_boundary_addr - r_current_addr;
    
    // 전송 효율과 FIFO 안정을 위해 최대 버스트 크기를 64바이트로 제한
    assign max_burst_bytes    = (r_remaining_bytes > 64) ? 64 : r_remaining_bytes;
    
    // 경계까지의 거리와 계획된 크기 중 최소값을 이번 버스트 크기로 선택
    assign calc_len_bytes     = (max_burst_bytes > dist_to_boundary) ? dist_to_boundary : max_burst_bytes;
    
    // 현재 버스트 전송 바이트 계산: 버스트 개수 * 4 (32-bit 기준)
    assign current_transfer_bytes = {22'd0, r_burst_len, 2'b00}; 

    // -------------------------------------------------------------------------
    // 2. AXI 주소 및 데이터 채널 출력 설정
    // -------------------------------------------------------------------------
    // AW Channel
    assign m_axi_awsize  = 3'b010;     // 4 Bytes 전송 고정
    assign m_axi_awburst = 2'b01;     // INCR (주소 자동 증가)
    assign m_axi_awaddr  = r_current_addr;
    assign m_axi_awvalid = awvalid_reg;
    assign m_axi_awlen   = (calc_len_bytes[9:2] > 0) ? (calc_len_bytes[9:2] - 1) : 0;

    // W Channel
    assign m_axi_wdata   = i_w_data;   // FIFO 출력 데이터를 그대로 전송
    assign m_axi_wstrb   = 4'hF;       // 모든 바이트(4Bytes) 유효함
    assign m_axi_wvalid  = (current_state == W_PHASE) && (!i_fifo_empty);
    // 현재 전송 횟수가 (계획된 길이 - 1)에 도달하면 마지막(WLAST) 신호 생성
    assign m_axi_wlast   = (current_state == W_PHASE) && (w_beat_count == r_burst_len - 1);

    // B Channel
    assign m_axi_bready  = (current_state == B_PHASE);

    // -------------------------------------------------------------------------
    // 3. FIFO 인터페이스 (읽기 제어)
    // -------------------------------------------------------------------------
    // AXI 데이터 채널에서 핸드셰이크가 발생할 때만 FIFO에서 다음 데이터를 꺼냄
    assign o_fifo_rd_en = (m_axi_wvalid && m_axi_wready);

    // -------------------------------------------------------------------------
    // 4. 상태 천이 로직 (FSM)
    // -------------------------------------------------------------------------
    
    always @(*) begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                if (i_start) next_state = AW_PHASE;
            end
            AW_PHASE: begin
                // 주소 전송 완료(핸드셰이크) 시 데이터 전송 단계로 이동
                if (m_axi_awvalid && m_axi_awready) 
                    next_state = W_PHASE;
            end
            W_PHASE: begin
                // 버스트의 마지막 데이터(WLAST) 전송 완료 시 응답 대기 단계로 이동
                if (m_axi_wlast && m_axi_wvalid && m_axi_wready)
                    next_state = B_PHASE;
            end
            B_PHASE: begin
                // 슬레이브가 쓰기 완료 응답(BVALID)을 보내면
                if (m_axi_bvalid && m_axi_bready) begin
                    // 모든 데이터 전송 완료 여부에 따라 IDLE 또는 다음 AW 단계로 결정
                    if (r_remaining_bytes <= current_transfer_bytes)
                        next_state = IDLE;
                    else
                        next_state = AW_PHASE;
                end
            end
            default: next_state = IDLE;
        endcase
    end

    // -------------------------------------------------------------------------
    // 5. AWVALID 제어 로직 (Look-ahead 및 Self-clearing)
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            awvalid_reg <= 0;
        else begin
            case (current_state)
                IDLE: begin
                    // 시작 신호 수신 즉시 첫 번째 주소 유효화
                    if (i_start) awvalid_reg <= 1;
                    else         awvalid_reg <= 0;
                end
                AW_PHASE: begin
                    // 주소 핸드셰이크 체결 시 즉시 Low (버스트당 한 번의 AW)
                    if (awvalid_reg && m_axi_awready)
                        awvalid_reg <= 0;
                end
                B_PHASE: begin
                    // 이전 버스트의 응답을 받는 시점에 남은 데이터가 있다면
                    // 차기 전송을 위해 미리 AWVALID를 띄워 대기 시간 최소화(Look-ahead)
                    if (m_axi_bvalid && m_axi_bready) begin
                        if(r_remaining_bytes > current_transfer_bytes) awvalid_reg <= 1;
                        else awvalid_reg <= 0;
                    end
                end
                default: awvalid_reg <= 0;
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
            w_beat_count      <= 0;
            o_write_done      <= 0;
        end else begin
            current_state <= next_state;
            case (current_state)
                IDLE: begin
                    w_beat_count <= 0;
                    o_write_done <= 0;
                    if (i_start) begin
                        r_current_addr    <= i_dst_addr;   // 초기 목적지 주소 저장
                        r_remaining_bytes <= i_total_len;  // 전송 총량 저장
                    end
                end

                AW_PHASE: begin
                    // 주소 전송 시 이번 버스트에서 보낼 길이(Word 단위) 확정
                    if (m_axi_awvalid && m_axi_awready) begin
                        r_burst_len  <= calc_len_bytes[9:2];
                    end
                end

                W_PHASE: begin
                    // 데이터 핸드셰이크 시마다 버스트 내 전송 횟수 카운트
                    if (m_axi_wvalid && m_axi_wready) begin
                        w_beat_count <= w_beat_count + 1;
                    end
                end

                B_PHASE: begin
                    // 응답 수신 완료 시 주소 및 잔여 바이트 수 업데이트
                    if (m_axi_bvalid && m_axi_bready) begin
                        w_beat_count <= 0; // 카운터 초기화
                        r_current_addr <= r_current_addr + current_transfer_bytes;
                        
                        if (r_remaining_bytes > current_transfer_bytes)
                            r_remaining_bytes <= r_remaining_bytes - current_transfer_bytes;
                        else begin
                            r_remaining_bytes <= 0;
                            o_write_done      <= 1; // 모든 전송 완료 알림
                        end
                    end
                end
            endcase
        end
    end
endmodule
