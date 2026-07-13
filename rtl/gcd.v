`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 13.06.2026 22:35:29
// Design Name: 
// Module Name: Gcd16bit
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
// Module: GCD 16-bit Signed (Binary Stein Algorithm)
// Fixed: zero-input edge case (b register now initialized)
//        signed input handling
// ============================================================
module gcd_16bit (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               start,
    input  wire signed [15:0] A,
    input  wire signed [15:0] B,
    output reg  [15:0]        gcd_out,
    output wire               ready,
    output reg                done
);

    localparam IDLE         = 3'd0;
    localparam STRIP_COMMON = 3'd1;
    localparam STRIP_A      = 3'd2;
    localparam STRIP_B      = 3'd3;
    localparam SUBTRACT     = 3'd4;
    localparam FINISH       = 3'd5;

    reg [2:0]  state;
    reg [15:0] a, b;
    reg [3:0]  shift;

    assign ready = (state == IDLE);

    // Absolute value - handle 16'h8000 (-32768) safely
    wire [15:0] A_abs = A[15] ? (A == 16'h8000 ? 16'd32768 : (~A + 1'b1)) : A;
    wire [15:0] B_abs = B[15] ? (B == 16'h8000 ? 16'd32768 : (~B + 1'b1)) : B;

    always @(posedge clk) begin
        if (!rst_n) begin
            state   <= IDLE;
            a       <= 16'd0;
            b       <= 16'd0;
            shift   <= 4'd0;
            gcd_out <= 16'd0;
            done    <= 1'b0;
        end else begin
            done <= 1'b0;   // default deassert

            case (state)

                IDLE: begin
                    if (start) begin
                        shift <= 4'd0;
                        // Edge cases: one or both inputs are zero
                        if (A == 16'sd0 && B == 16'sd0) begin
                            a     <= 16'd0;
                            b     <= 16'd0;   // FIX: initialize b
                            state <= FINISH;
                        end else if (A == 16'sd0) begin
                            a     <= B_abs;
                            b     <= 16'd0;   // FIX: initialize b
                            state <= FINISH;
                        end else if (B == 16'sd0) begin
                            a     <= A_abs;
                            b     <= 16'd0;   // FIX: initialize b
                            state <= FINISH;
                        end else begin
                            a     <= A_abs;
                            b     <= B_abs;
                            state <= STRIP_COMMON;
                        end
                    end
                end

                // Both even: divide both by 2, count shared factor
                STRIP_COMMON: begin
                    if (!a[0] && !b[0]) begin
                        a     <= a >> 1;
                        b     <= b >> 1;
                        shift <= shift + 1'b1;
                    end else
                        state <= STRIP_A;
                end

                // Make a odd
                STRIP_A: begin
                    if (!a[0]) a <= a >> 1;
                    else       state <= STRIP_B;
                end

                // Make b odd
                STRIP_B: begin
                    if (!b[0]) b <= b >> 1;
                    else       state <= SUBTRACT;
                end

                // Both odd: subtract smaller from larger
                SUBTRACT: begin
                    if (a == b) begin
                        state <= FINISH;
                    end else if (a > b) begin
                        a <= b;
                        b <= a - b;         // b = old_a - old_b
                        state <= STRIP_B;   // result may be even
                    end else begin
                        // a < b
                        b <= b - a;
                        state <= STRIP_B;
                    end
                end

                FINISH: begin
                    gcd_out <= a << shift;
                    done    <= 1'b1;
                    state   <= IDLE;
                end

            endcase
        end
    end

endmodule

