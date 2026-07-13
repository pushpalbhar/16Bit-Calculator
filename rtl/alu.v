// ============================================================//
module alu_16bit (
    input  [15:0] A,
    input  [15:0] B,
    input  [3:0]  opcode,
    output [15:0] result,
    output        Z, N, V, C
); 
    // Explicit control wires
    wire is_sub = (opcode == 4'b0001);
    wire is_slt = (opcode == 4'b1010);
    wire do_sub = is_sub | is_slt;   // both SUB and SLT need A-B

    // Bitwise
    wire [15:0] and_out = A & B;
    wire [15:0] or_out  = A | B;
    wire [15:0] xor_out = A ^ B;
    wire [15:0] not_out = ~A;

    // Unified adder/subtractor - used by ADD, SUB, SLT
    wire [15:0] b_eff    = do_sub ? ~B : B;
    wire [16:0] add_full = {1'b0,A} + {1'b0,b_eff} + do_sub;
    wire [15:0] sum      = add_full[15:0];
    wire        cout     = add_full[16];

    // Overflow: same-sign inputs produce opposite-sign result
    wire ov = (A[15] == (B[15] ^ do_sub)) && (sum[15] != A[15]);

    // SLT: A < B (signed) = sign of result XOR overflow
    wire [15:0] slt_out = {15'b0, sum[15] ^ ov};

    // Shifters
    wire [15:0] lsl_out = A << B[3:0];
    wire [15:0] lsr_out = A >> B[3:0];
    wire [15:0] asr_out = $signed(A) >>> B[3:0];

    // Result MUX
    reg [15:0] mux_out;
    always @(*) begin
        case (opcode)
            4'b0000: mux_out = sum;
            4'b0001: mux_out = sum;
            4'b0010: mux_out = and_out;
            4'b0011: mux_out = or_out;
            4'b0100: mux_out = xor_out;
            4'b0101: mux_out = not_out;
            4'b0110: mux_out = lsl_out;
            4'b0111: mux_out = lsr_out;
            4'b1000: mux_out = lsl_out;
            4'b1001: mux_out = asr_out;
            4'b1010: mux_out = slt_out;
            4'b1011: mux_out = (A == B) ? 16'h0001 : 16'h0000;
            4'b1100: mux_out = (A >  B) ? 16'h0001 : 16'h0000;
            default: mux_out = 16'b0;
        endcase
    end

    assign result = mux_out;

    // Flags - only valid for ADD and SUB (not SLT)
    assign Z = ~|result;
    assign N = result[15];
    assign C = cout & (opcode == 4'b0000 || opcode == 4'b0001);
    assign V = (opcode == 4'b0000 || opcode == 4'b0001) ? ov : 1'b0;

endmodule
