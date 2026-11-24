`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// LUT kecil + interpolasi linear (kelas latency: low)
//   - Simetri: hanya |x| di [0, 8) yang disimpan, x < 0 -> 1 - y(|x|)
//   - 33 titik dengan jarak 0.25: T[i] = round(sigmoid(i/4) * 2^14)
//   - i = |x|[12:8], f = |x|[7:0]
//     y14 = T[i] + ((T[i+1] - T[i]) * f) >> 8
//     y   = round(y14 / 16)            (Q.14 -> Q.10)
//   - |x| >= 8 -> y = 1
// Input : din  16 bit signed Q6.10 (1.0 = 1024)
// Output: dout 16 bit Q6.10, rentang 0..1024
// Hardware: ROM 33 x 15 bit (LUT), 1 pengali 10x8 bit, adder.
// Latency: 2 clk (versi 1 clk tidak memenuhi 100 MHz di 7-series speed grade -1)
//////////////////////////////////////////////////////////////////////////////////
module sigmoid_interp
    (
        input wire         clk,
        input wire         rst_n,
        input wire         en,
        input wire         clr,
        input wire [15:0]  din,
        output wire [15:0] dout
    );

    wire signed [16:0] x  = {din[15], din};
    wire        [16:0] ax = din[15] ? -x : x;   // |x|
    wire        [4:0]  i  = ax[12:8];
    wire        [7:0]  f  = ax[7:0];

    function [14:0] tbl;
        input [5:0] k;
        case (k)
            6'd0 : tbl = 15'd8192;  6'd1 : tbl = 15'd9211;
            6'd2 : tbl = 15'd10198; 6'd3 : tbl = 15'd11128;
            6'd4 : tbl = 15'd11978; 6'd5 : tbl = 15'd12735;
            6'd6 : tbl = 15'd13395; 6'd7 : tbl = 15'd13958;
            6'd8 : tbl = 15'd14431; 6'd9 : tbl = 15'd14822;
            6'd10: tbl = 15'd15141; 6'd11: tbl = 15'd15400;
            6'd12: tbl = 15'd15607; 6'd13: tbl = 15'd15772;
            6'd14: tbl = 15'd15904; 6'd15: tbl = 15'd16008;
            6'd16: tbl = 15'd16089; 6'd17: tbl = 15'd16154;
            6'd18: tbl = 15'd16204; 6'd19: tbl = 15'd16243;
            6'd20: tbl = 15'd16274; 6'd21: tbl = 15'd16298;
            6'd22: tbl = 15'd16317; 6'd23: tbl = 15'd16332;
            6'd24: tbl = 15'd16343; 6'd25: tbl = 15'd16352;
            6'd26: tbl = 15'd16359; 6'd27: tbl = 15'd16365;
            6'd28: tbl = 15'd16369; 6'd29: tbl = 15'd16372;
            6'd30: tbl = 15'd16375; 6'd31: tbl = 15'd16377;
            default: tbl = 15'd16379;               // k = 32
        endcase
    endfunction

    // ---- Tahap 1: |x|, ambil dua titik tabel, hitung selisih
    wire [14:0] t0  = tbl({1'b0, i});
    wire [14:0] t1  = tbl({1'b0, i} + 6'd1);
    wire [9:0]  d   = t1 - t0;                       // selisih maks 1019 (10 bit)
    wire [14:0] t0p = t0 + 15'd8;                    // +8 = konstanta pembulatan Q.14 -> Q.10
    wire        sat = (ax >= 17'd8192);

    wire [14:0] t0p_r;
    wire [9:0]  d_r;
    wire [7:0]  f_r;
    wire        neg_r, sat_r;
    register #(35) reg_s1(clk, rst_n, en, clr,
                          {t0p, d, f, din[15], sat},
                          {t0p_r, d_r, f_r, neg_r, sat_r});

    // ---- Tahap 2: interpolasi + pembulatan dalam satu DSP (P = C + A*B), simetri
    //   yr = floor(((t0+8)*256 + d*f) / 4096) = round((t0 + floor(d*f/256)) / 16)
    wire [23:0] acc = {t0p_r, 8'd0} + d_r * f_r;
    wire [15:0] yr  = acc[23:12];

    wire [15:0] y = sat_r ? 16'd1024 : yr;
    wire [15:0] s = neg_r ? (16'd1024 - y) : y;

    register #(16) reg_dout(clk, rst_n, en, clr, s, dout);

endmodule
