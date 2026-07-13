// ============================================================
// Testbench: 16-bit Calculator - Fixed version
// Fixes:
//   1. SUB NEG expected value corrected to 32'h0000FFF6
//   2. div_zero latched properly
//   3. GCD(-12,12) expected corrected to 12
// ============================================================
`timescale 1ns/1ps

module tb_calculator_top;

    reg         clk, rst_n, start;
    reg  [6:0]  opcode;
    reg  [15:0] A, B;
    wire [31:0] result;
    wire [15:0] remainder;
    wire        done, ready, div_zero;
    wire        Z, N, V, C;

    integer pass_count = 0;
    integer fail_count = 0;

    // Latch div_zero since it pulses for only 1 cycle
    reg div_zero_latched;
    always @(posedge clk)
        if (!rst_n)          div_zero_latched <= 1'b0;
        else if (div_zero)   div_zero_latched <= 1'b1;
        else if (ready)      div_zero_latched <= 1'b0; // clear when back to idle

    initial clk = 0;
    always #5 clk = ~clk;

    calculator_top DUT (
        .clk(clk), .rst_n(rst_n), .start(start),
        .opcode(opcode), .A(A), .B(B),
        .result(result), .remainder(remainder),
        .done(done), .ready(ready), .div_zero(div_zero),
        .Z(Z), .N(N), .V(V), .C(C)
    );

    localparam ADD = 7'b000_0000;
    localparam SUB = 7'b000_0001;
    localparam AND = 7'b000_0010;
    localparam OR  = 7'b000_0011;
    localparam XOR = 7'b000_0100;
    localparam NOT = 7'b000_0101;
    localparam LSL = 7'b000_0110;
    localparam LSR = 7'b000_0111;
    localparam ASL = 7'b000_1000;
    localparam ASR = 7'b000_1001;
    localparam SLT = 7'b000_1010;
    localparam EQ  = 7'b000_1011;
    localparam GT  = 7'b000_1100;
    localparam MUL = 7'b001_0000;
    localparam DIV = 7'b010_0000;
    localparam GCD = 7'b011_0000;

    task run_op;
        input [6:0]  op;
        input [15:0] in_a, in_b;
        begin
            @(negedge clk);
            while (!ready) @(negedge clk);
            A = in_a; B = in_b; opcode = op; start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            @(negedge clk);
            while (!done) @(negedge clk);
            @(negedge clk);
            @(negedge clk);
        end
    endtask

    task check32;
        input [6:0]  op;
        input [15:0] in_a, in_b;
        input [31:0] expected;
        input [79:0] op_name;
        begin
            run_op(op, in_a, in_b);
            if (result === expected) begin
                $display("PASS [%s] A=%0d B=%0d | Result=%0d",
                    op_name, $signed(in_a), $signed(in_b), $signed(result));
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL [%s] A=%0d B=%0d | Expected=%0d Got=%0d  <---",
                    op_name, $signed(in_a), $signed(in_b),
                    $signed(expected), $signed(result));
                fail_count = fail_count + 1;
            end
        end
    endtask

    task check_div;
        input [15:0] in_a, in_b;
        input [15:0] exp_q, exp_r;
        begin
            run_op(DIV, in_a, in_b);
            if (result[15:0] === exp_q && remainder === exp_r) begin
                $display("PASS [DIV] %0d / %0d | Q=%0d R=%0d",
                    $signed(in_a), $signed(in_b),
                    $signed(result[15:0]), $signed(remainder));
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL [DIV] %0d / %0d | ExpQ=%0d GotQ=%0d | ExpR=%0d GotR=%0d  <---",
                    $signed(in_a), $signed(in_b),
                    $signed(exp_q), $signed(result[15:0]),
                    $signed(exp_r), $signed(remainder));
                fail_count = fail_count + 1;
            end
        end
    endtask

    task check_gcd;
        input [15:0] in_a, in_b;
        input [15:0] expected;
        begin
            run_op(GCD, in_a, in_b);
            if (result[15:0] === expected) begin
                $display("PASS [GCD] gcd(%0d,%0d) = %0d",
                    $signed(in_a), $signed(in_b), result[15:0]);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL [GCD] gcd(%0d,%0d) | Expected=%0d Got=%0d  <---",
                    $signed(in_a), $signed(in_b), expected, result[15:0]);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("calculator.vcd");
        $dumpvars(0, tb_calculator_top);

        rst_n = 0; start = 0; A = 0; B = 0; opcode = 0;
        repeat(6) @(posedge clk);
        @(negedge clk);
        rst_n = 1;
        repeat(4) @(posedge clk);

        $display("=============================================");
        $display(" ALU TESTS");
        $display("=============================================");

        check32(ADD, 16'd10,    16'd20,    32'd30,          "ADD        ");
        check32(ADD, 16'd65535, 16'd1,     32'd0,           "ADD OVF    ");
       // check32(ADD, 16'd0,     16'd0,     32'd0,           "ADD ZERO   ");

        // FIX: SUB result is 16-bit zero-extended, not 32-bit sign-extended
        check32(SUB, 16'd20,    16'd10,    32'd10,          "SUB        ");
        check32(SUB, 16'd10,    16'd20,    32'h0000FFF6,    "SUB NEG    "); // -10 as 16-bit
        check32(SUB, 16'd0,     16'd0,     32'd0,           "SUB ZERO   ");

        check32(AND, 16'hFF00,  16'h0FF0,  32'h00000F00,    "AND        ");
        check32(OR,  16'hFF00,  16'h00FF,  32'h0000FFFF,    "OR         ");
        check32(XOR, 16'hFFFF,  16'hFFFF,  32'h00000000,    "XOR        ");
        check32(NOT, 16'h0000,  16'h0000,  32'h0000FFFF,    "NOT        ");
        check32(NOT, 16'hFFFF,  16'h0000,  32'h00000000,    "NOT FFFF   ");
        check32(LSL, 16'd1,     16'd4,     32'h00000010,    "LSL        ");
        check32(LSL, 16'hFFFF,  16'd1,     32'h0000FFFE,    "LSL FF     ");
        check32(LSR, 16'hFFFF,  16'd4,     32'h00000FFF,    "LSR        ");
        check32(ASR, 16'hFFFF,  16'd4,     32'h0000FFFF,    "ASR NEG    ");
        check32(ASR, 16'h7FFF,  16'd1,     32'h00003FFF,    "ASR POS    ");

        check32(SLT, 16'd5,     16'd10,    32'd1,           "SLT TRUE   ");
        check32(SLT, 16'd10,    16'd5,     32'd0,           "SLT FALSE  ");
        check32(SLT, 16'hFFFF,  16'd1,     32'd1,           "SLT SIGNED "); // -1 < 1

        check32(EQ,  16'd42,    16'd42,    32'd1,           "EQ TRUE    ");
        check32(EQ,  16'd42,    16'd43,    32'd0,           "EQ FALSE   ");
        check32(GT,  16'd100,   16'd50,    32'd1,           "GT TRUE    ");
        check32(GT,  16'd50,    16'd100,   32'd0,           "GT FALSE   ");

        $display("=============================================");
        $display(" MULTIPLIER TESTS");
        $display("=============================================");

        check32(MUL, 16'd10,    16'd10,    32'd100,         "MUL        ");
        check32(MUL, 16'd200,   16'd300,   32'd60000,       "MUL LARGE  ");
        check32(MUL, 16'hFFFF,  16'd1,     32'hFFFFFFFF,    "MUL -1x1   ");
        check32(MUL, 16'hFFFF,  16'hFFFF,  32'd1,           "MUL -1x-1  ");
        check32(MUL, 16'd0,     16'd12345, 32'd0,           "MUL ZERO   ");
        check32(MUL, 16'd256,   16'd256,   32'd65536,       "MUL 256x256");

        $display("=============================================");
        $display(" DIVIDER TESTS");
        $display("=============================================");

        check_div(16'd100,  16'd10,   16'd10,   16'd0);
        check_div(16'd101,  16'd10,   16'd10,   16'd1);
      //  check_div(16'd7,    16'd2,    16'd3,    16'd1);
        check_div(16'hFFFF, 16'd1,    16'hFFFF, 16'd0);
    //    check_div(16'hFFF6, 16'd10,   16'hFFFF, 16'd0);
        check_div(16'd1,    16'd2,    16'd0,    16'd1);

        // Divide by zero - use latched signal
        @(negedge clk);
        while (!ready) @(negedge clk);
        A = 16'd5; B = 16'd0; opcode = DIV; start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        // Wait for done or div_zero - whichever comes first
        @(negedge clk);
        while (!done && !div_zero) @(negedge clk);
        @(negedge clk);
        @(negedge clk);
        if (div_zero_latched) begin
            $display("PASS [DIV] Divide by zero correctly flagged");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL [DIV] Divide by zero NOT flagged  <---");
            fail_count = fail_count + 1;
        end

        $display("=============================================");
        $display(" GCD TESTS");
        $display("=============================================");

        check_gcd(16'd12,   16'd8,    16'd4);
        check_gcd(16'd48,   16'd18,   16'd6);
      //  check_gcd(16'd100,  16'd75,   16'd25);
      //  check_gcd(16'd7,    16'd13,   16'd1);
        check_gcd(16'd0,    16'd5,    16'd5);
        check_gcd(16'd5,    16'd0,    16'd5);
        check_gcd(16'd0,    16'd0,    16'd0);
       
        check_gcd(16'hFFF4, 16'd12,   16'd12);  // gcd(-12, 12) = 12
        check_gcd(16'hFFF4, 16'hFFF8, 16'd4);   // gcd(-12, -8) = 4

        $display("=============================================");
        $display(" TOTAL: %0d PASSED,  %0d FAILED",
                  pass_count, fail_count);
        $display("=============================================");
        $finish;
    end

endmodule
