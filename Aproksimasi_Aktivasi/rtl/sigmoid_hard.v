`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Hard sigmoid (kelas latency: very low)
//   y = clip(x/4 + 0.5, 0, 1)
// Input : din  16 bit signed Q6.10 (1.0 = 1024)
// Output: dout 16 bit Q6.10, rentang 0..1024
// Hardware: 1 shifter (wiring), 1 adder, 2 comparator. Tanpa DSP/BRAM.
// Latency: 1 clk (port sama dengan pynq_part_4/sigmoid.v)
//////////////////////////////////////////////////////////////////////////////////
module sigmoid_hard
    (
        input wire         clk,
        input wire         rst_n,
        input wire         en,
        input wire         clr,
        input wire [15:0]  din,
        output wire [15:0] dout
    );

    wire signed [15:0] x = din;
    wire signed [16:0] s = (x >>> 2) + 17'sd512;   // x/4 + 0.5
    wire        [15:0] y = (s < 0)        ? 16'd0    :
                           (s > 17'sd1024) ? 16'd1024 : s[15:0];

    register #(16) reg_dout(clk, rst_n, en, clr, y, dout);

endmodule
