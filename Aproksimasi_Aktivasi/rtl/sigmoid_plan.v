`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// PLAN: Piecewise Linear Approximation of Nonlinearity (Amin dkk., 1997)
// Kelas latency: low (shift-and-add + symmetry-based PWL)
//   |x| >= 5           : y = 1
//   2.375 <= |x| < 5   : y = |x|/32 + 0.84375
//   1     <= |x| < 2.375: y = |x|/8  + 0.625
//   0     <= |x| < 1   : y = |x|/4  + 0.5
//   x < 0              : y = 1 - y(|x|)        (simetri sigmoid)
// Input : din  16 bit signed Q6.10 (1.0 = 1024)
// Output: dout 16 bit Q6.10, rentang 0..1024
// Hardware: shift (wiring), adder, comparator, mux. Tanpa DSP/BRAM.
// Latency: 1 clk
//////////////////////////////////////////////////////////////////////////////////
module sigmoid_plan
    (
        input wire         clk,
        input wire         rst_n,
        input wire         en,
        input wire         clr,
        input wire [15:0]  din,
        output wire [15:0] dout
    );

    wire signed [16:0] x  = {din[15], din};
    wire        [16:0] ax = din[15] ? -x : x;          // |x|, 17 bit agar -32768 aman
    reg         [15:0] y;

    always @*
    begin
        if      (ax >= 17'd5120) y = 16'd1024;          // >= 5.0
        else if (ax >= 17'd2432) y = (ax >> 5) + 16'd864; // >= 2.375
        else if (ax >= 17'd1024) y = (ax >> 3) + 16'd640; // >= 1.0
        else                     y = (ax >> 2) + 16'd512;
    end

    wire [15:0] s = din[15] ? (16'd1024 - y) : y;

    register #(16) reg_dout(clk, rst_n, en, clr, s, dout);

endmodule
