`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 13.06.2026 22:33:46
// Design Name: 
// Module Name: control_unit
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
// Module: Control Unit FSM
// Handles handshake between ALU (combinational),
// Multiplier (combinational), Divider (~20 cycles),
// GCD (variable cycles)
//
// Opcode Map (7-bit):
//   000_0000 = ADD       000_0001 = SUB
//   000_0010 = AND       000_0011 = OR
//   000_0100 = XOR       000_0101 = NOT
//   000_0110 = LSL       000_0111 = LSR
//   000_1000 = ASL       000_1001 = ASR
//   000_1010 = SLT       000_1011 = EQ
//   000_1100 = GT
//   001_0000 = MUL
//   010_0000 = DIV
//   011_0000 = GCD
// ============================================================
module control_unit (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,
    input  wire [6:0] opcode,

    // Status from slow modules
    input  wire       div_done,
    input  wire       div_ready,
    input  wire       div_zero,
    input  wire       gcd_done,
    input  wire       gcd_ready,

    // Control outputs
    output reg        alu_en,
    output reg        mul_en,
    output reg        div_start,
    output reg        gcd_start,
    output reg        result_sel, // 0=ALU/MUL, 1=DIV/GCD
    output reg        done,
    output wire       ready,
    output reg  [3:0] alu_opcode  // 4-bit opcode sent to ALU
);

    // FSM States
    localparam IDLE       = 3'd0;
    localparam DECODE     = 3'd1;
    localparam EXEC_FAST  = 3'd2;   // ALU or MUL (combinational)
    localparam EXEC_SLOW  = 3'd3;   // DIV or GCD (wait for done)
    localparam WRITEBACK  = 3'd4;

    reg [2:0] state;
    reg [6:0] op_latch;             // latch opcode at start

    assign ready = (state == IDLE);

    // Opcode type decode
    wire is_alu = (op_latch[6:4] == 3'b000);
    wire is_mul = (op_latch == 7'b001_0000);
    wire is_div = (op_latch == 7'b010_0000);
    wire is_gcd = (op_latch == 7'b011_0000);

    always @(posedge clk) begin
        if (!rst_n) begin
            state      <= IDLE;
            op_latch   <= 7'd0;
            alu_en     <= 1'b0;
            mul_en     <= 1'b0;
            div_start  <= 1'b0;
            gcd_start  <= 1'b0;
            result_sel <= 1'b0;
            done       <= 1'b0;
            alu_opcode <= 4'd0;
        end else begin
            // Default deasserts
            done      <= 1'b0;
            div_start <= 1'b0;
            gcd_start <= 1'b0;

            case (state)

                IDLE: begin
                    alu_en <= 1'b0;
                    mul_en <= 1'b0;
                    if (start) begin
                        op_latch <= opcode;
                        state    <= DECODE;
                    end
                end

                DECODE: begin
                    alu_opcode <= op_latch[3:0];  // lower 4 bits for ALU
                    if (op_latch[6:4] == 3'b000) begin
                        // ALU operation
                        alu_en     <= 1'b1;
                        mul_en     <= 1'b0;
                        result_sel <= 1'b0;
                        state      <= EXEC_FAST;
                    end else if (op_latch == 7'b001_0000) begin
                        // MUL - combinational
                        alu_en     <= 1'b0;
                        mul_en     <= 1'b1;
                        result_sel <= 1'b0;
                        state      <= EXEC_FAST;
                    end else if (op_latch == 7'b010_0000) begin
                        // DIV - sequential
                        alu_en     <= 1'b0;
                        mul_en     <= 1'b0;
                        result_sel <= 1'b1;
                        div_start  <= 1'b1;   // pulse start
                        state      <= EXEC_SLOW;
                    end else if (op_latch == 7'b011_0000) begin
                        // GCD - sequential
                        alu_en     <= 1'b0;
                        mul_en     <= 1'b0;
                        result_sel <= 1'b1;
                        gcd_start  <= 1'b1;   // pulse start
                        state      <= EXEC_SLOW;
                    end else begin
                        // Unknown opcode - go idle
                        state <= IDLE;
                    end
                end

                EXEC_FAST: begin
                    // Combinational result ready next cycle
                    state <= WRITEBACK;
                end

                EXEC_SLOW: begin
                    // Wait for done signal from DIV or GCD
                    if ((is_div && div_done) || (is_gcd && gcd_done))
                        state <= WRITEBACK;
                    // Also handle div_zero early exit
                    if (is_div && div_zero)
                        state <= WRITEBACK;
                end

                WRITEBACK: begin
                    done   <= 1'b1;
                    alu_en <= 1'b0;
                    mul_en <= 1'b0;
                    state  <= IDLE;
                end

            endcase
        end
    end

endmodule


// ============================================================
// Module: Calculator Top Module
// Integrates: ALU, Booth Multiplier, NR Divider, GCD
// Result bus: 32-bit unified (upper 16 = 0 for non-MUL ops)
// ============================================================
module calculator_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [6:0]  opcode,
    input  wire [15:0] A,
    input  wire [15:0] B,

    // Outputs
    output reg  [31:0] result,      // unified 32-bit result bus
    output reg  [15:0] remainder,   // valid after DIV only
    output wire        done,
    output wire        ready,
    output wire        div_zero,

    // ALU flags - valid after ALU operations
    output wire        Z, N, V, C
);

    // ---- Internal wires ----

    // Control unit outputs
    wire       alu_en, mul_en;
    wire       div_start, gcd_start;
    wire       result_sel;
    wire [3:0] alu_opcode;

    // ALU
    wire [15:0] alu_result;
    wire        alu_Z, alu_N, alu_V, alu_C;

    // Multiplier
    wire signed [31:0] mul_result;

    // Divider
    wire [15:0] div_Q, div_rem;
    wire        div_done, div_ready, div_zero_wire;

    // GCD
    wire [15:0] gcd_result;
    wire        gcd_done, gcd_ready;

    // ---- Control Unit ----
    control_unit CU (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (start),
        .opcode     (opcode),
        .div_done   (div_done),
        .div_ready  (div_ready),
        .div_zero   (div_zero_wire),
        .gcd_done   (gcd_done),
        .gcd_ready  (gcd_ready),
        .alu_en     (alu_en),
        .mul_en     (mul_en),
        .div_start  (div_start),
        .gcd_start  (gcd_start),
        .result_sel (result_sel),
        .done       (done),
        .ready      (ready),
        .alu_opcode (alu_opcode)
    );

    // ---- ALU ----
    alu_16bit ALU (
        .A      (A),
        .B      (B),
        .opcode (alu_opcode),
        .result (alu_result),
        .Z      (alu_Z),
        .N      (alu_N),
        .V      (alu_V),
        .C      (alu_C)
    );

    // ---- Booth Multiplier ----
    booth_multiplier MUL (
        .A   (A),
        .B   (B),
        .mul (mul_result)
    );

    // ---- Non-Restoring Divider ----
    nrestoring_divider_signed DIV (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (div_start),
        .A        (A),
        .B        (B),
        .Q        (div_Q),
        .rem      (div_rem),
        .ready    (div_ready),
        .done     (div_done),
        .div_zero (div_zero_wire)
    );

    // ---- GCD ----
    gcd_16bit GCD (
        .clk     (clk),
        .rst_n   (rst_n),
        .start   (gcd_start),
        .A       (A),
        .B       (B),
        .gcd_out (gcd_result),
        .ready   (gcd_ready),
        .done    (gcd_done)
    );

    // ---- Output mux - latch results on done ----
    assign div_zero = div_zero_wire;

    // Flag outputs only valid for ALU ops
    assign Z = alu_Z;
    assign N = alu_N;
    assign V = alu_V;
    assign C = alu_C;

    always @(posedge clk) begin
        if (!rst_n) begin
            result    <= 32'd0;
            remainder <= 16'd0;
        end else if (done) begin
            case (opcode[6:4])
                3'b000: begin   // ALU
                    result    <= {16'b0, alu_result};
                    remainder <= 16'd0;
                end
                3'b001: begin   // MUL
                    result    <= mul_result;
                    remainder <= 16'd0;
                end
                3'b010: begin   // DIV
                    result    <= {16'b0, div_Q};
                    remainder <= div_rem;
                end
                3'b011: begin   // GCD
                    result    <= {16'b0, gcd_result};
                    remainder <= 16'd0;
                end
                default: begin
                    result    <= 32'd0;
                    remainder <= 16'd0;
                end
            endcase
        end
    end

endmodule
