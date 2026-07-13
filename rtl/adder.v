`timescale 1ns / 1ps
// ============================================================
// Module: 4-bit Carry Lookahead Adder
// ============================================================
module cla_4bit (
    input  [3:0] a, b,
    input        cin,
    output [3:0] sum,
    output       cout
);
    wire [3:0] g, p;
    assign g = a & b;
    assign p = a ^ b;

    wire c1, c2, c3;
    assign c1   = g[0] | (p[0] & cin);
    assign c2   = g[1] | (p[1] & g[0]) | (p[1] & p[0] & cin);
    assign c3   = g[2] | (p[2] & g[1]) | (p[2] & p[1] & g[0])
                       | (p[2] & p[1] & p[0] & cin);
    assign cout = g[3] | (p[3] & g[2]) | (p[3] & p[2] & g[1])
                       | (p[3] & p[2] & p[1] & g[0])
                       | (p[3] & p[2] & p[1] & p[0] & cin);

    assign sum[0] = p[0] ^ cin;
    assign sum[1] = p[1] ^ c1;
    assign sum[2] = p[2] ^ c2;
    assign sum[3] = p[3] ^ c3;
endmodule


// ============================================================
// Module: 4-bit 2:1 MUX
// ============================================================
module mux4_2to1 (
    input  [3:0] in0, in1,
    input        sel,
    output [3:0] out
);
    assign out = sel ? in1 : in0;
endmodule


// ============================================================
// Module: 16-bit Carry Select Adder (using 4-bit CLA blocks)
// ============================================================
module carry_select_adder_16bit (
    input  [15:0] a, b,
    input         cin,
    output [15:0] sum,
    output        cout
);
    // Group 0: bits 3:0
    wire c0_out;
    cla_4bit G0 (.a(a[3:0]),   .b(b[3:0]),   .cin(cin),  .sum(sum[3:0]),   .cout(c0_out));

    // Group 1: bits 7:4
    wire [3:0] s1_0, s1_1;
    wire       c1_0, c1_1, c1_out;
    cla_4bit G1_c0 (.a(a[7:4]),   .b(b[7:4]),   .cin(1'b0), .sum(s1_0), .cout(c1_0));
    cla_4bit G1_c1 (.a(a[7:4]),   .b(b[7:4]),   .cin(1'b1), .sum(s1_1), .cout(c1_1));
    mux4_2to1 MX1  (.in0(s1_0), .in1(s1_1), .sel(c0_out), .out(sum[7:4]));
    assign c1_out = c0_out ? c1_1 : c1_0;

    // Group 2: bits 11:8
    wire [3:0] s2_0, s2_1;
    wire       c2_0, c2_1, c2_out;
    cla_4bit G2_c0 (.a(a[11:8]),  .b(b[11:8]),  .cin(1'b0), .sum(s2_0), .cout(c2_0));
    cla_4bit G2_c1 (.a(a[11:8]),  .b(b[11:8]),  .cin(1'b1), .sum(s2_1), .cout(c2_1));
    mux4_2to1 MX2  (.in0(s2_0), .in1(s2_1), .sel(c1_out), .out(sum[11:8]));
    assign c2_out = c1_out ? c2_1 : c2_0;

    // Group 3: bits 15:12
    wire [3:0] s3_0, s3_1;
    wire       c3_0, c3_1;
    cla_4bit G3_c0 (.a(a[15:12]), .b(b[15:12]), .cin(1'b0), .sum(s3_0), .cout(c3_0));
    cla_4bit G3_c1 (.a(a[15:12]), .b(b[15:12]), .cin(1'b1), .sum(s3_1), .cout(c3_1));
    mux4_2to1 MX3  (.in0(s3_0), .in1(s3_1), .sel(c2_out), .out(sum[15:12]));
    assign cout = c2_out ? c3_1 : c3_0;
endmodule
