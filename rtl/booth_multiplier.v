`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 13.06.2026 22:36:41
// Design Name: 
// Module Name: Mul_div
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


// ============================================================
// Module: Booth Radix-2 Multiplier (combinational)
// Inputs : A, B signed 16-bit
// Output : mul signed 32-bit
// ============================================================
module booth_multiplier (
    input  wire signed [15:0] A,
    input  wire signed [15:0] B,
    output wire signed [31:0] mul
);
    reg signed [33:0] acc;
    integer i;

    always @(*) begin
        acc = {18'b0, B, 1'b0};
        for (i = 0; i < 16; i = i + 1) begin
            case (acc[1:0])
                2'b01: acc = acc + {{2{A[15]}}, A, 17'b0};
                2'b10: acc = acc - {{2{A[15]}}, A, 17'b0};
                default: ;
            endcase
            acc = acc >>> 1;
        end
    end

    assign mul = acc[32:1];
endmodule


// ============================================================
// Module: Non-Restoring Signed Divider
// Inputs : A (dividend), B (divisor) signed 16-bit
// Outputs: Q (quotient), rem (remainder) signed 16-bit
//          done, ready, div_zero
// Latency: ~20 clock cycles
// ============================================================
module nrestoring_divider_signed (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [15:0] A,
    input  wire [15:0] B,
    output reg  [15:0] Q,
    output reg  [15:0] rem,
    output wire        ready,
    output reg         done,
    output reg         div_zero
);
    localparam IDLE    = 3'd0;
    localparam SIGN    = 3'd1;
    localparam RUNNING = 3'd2;
    localparam ADJUST  = 3'd3;
    localparam UNSIGN  = 3'd4;
    localparam FINISH  = 3'd5;

    reg [2:0]  state;
    reg        sign_a, sign_b, result_sign, rem_sign;
    reg [16:0] P;
    reg [15:0] Q_reg, B_reg;
    reg [4:0]  cnt;

    assign ready = (state == IDLE);

    wire [16:0] P_shifted = {P[15:0], Q_reg[15]};
    wire        q_bit     = ~P_shifted[16];
    wire [16:0] P_sub     = P_shifted - {1'b0, B_reg};
    wire [16:0] P_add     = P_shifted + {1'b0, B_reg};
    wire        P_neg     = P[16];
    wire [15:0] Q_nr2bin  = (Q_reg << 1) - 16'hFFFF;
    wire [16:0] P_restored = P + {1'b0, B_reg};
    wire [15:0] A_neg     = (~A)     + 16'd1;
    wire [15:0] B_neg     = (~B)     + 16'd1;
    wire [15:0] Q_neg     = (~Q_reg) + 16'd1;
    wire [15:0] rem_neg   = (~P[15:0]) + 16'd1;

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE; P <= 17'd0; Q_reg <= 16'd0; B_reg <= 16'd0;
            cnt <= 5'd0; sign_a <= 0; sign_b <= 0;
            result_sign <= 0; rem_sign <= 0;
            Q <= 16'd0; rem <= 16'd0; done <= 0; div_zero <= 0;
        end else begin
            done <= 1'b0;
            case (state)
                IDLE: begin
                    div_zero <= 1'b0;
                    if (start) begin
                        if (B == 16'd0) begin
                            div_zero <= 1'b1;
                            done     <= 1'b1;
                        end else
                            state <= SIGN;
                    end
                end
                SIGN: begin
                    sign_a      <= A[15];
                    sign_b      <= B[15];
                    result_sign <= A[15] ^ B[15];
                    rem_sign    <= A[15];
                    P     <= 17'd0;
                    Q_reg <= A[15] ? A_neg : A;
                    B_reg <= B[15] ? B_neg : B;
                    cnt   <= 5'd0;
                    state <= RUNNING;
                end
                RUNNING: begin
                    P     <= q_bit ? P_sub : P_add;
                    Q_reg <= {Q_reg[14:0], q_bit};
                    cnt   <= cnt + 1'b1;
                    if (cnt == 5'd15) state <= ADJUST;
                end
                ADJUST: begin
                    if (P_neg) begin
                        P     <= P_restored;
                        Q_reg <= Q_nr2bin - 16'd1;
                    end else
                        Q_reg <= Q_nr2bin;
                    state <= UNSIGN;
                end
                UNSIGN: begin
                    Q_reg   <= result_sign ? Q_neg : Q_reg;
                    P[15:0] <= (rem_sign && P[15:0] != 16'd0) ? rem_neg : P[15:0];
                    state   <= FINISH;
                end
                FINISH: begin
                    Q     <= Q_reg;
                    rem   <= P[15:0];
                    done  <= 1'b1;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule

