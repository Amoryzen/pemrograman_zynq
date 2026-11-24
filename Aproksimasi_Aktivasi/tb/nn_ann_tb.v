`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Testbench ANN 2-3-2 (4 sampel) berdasarkan pynq_part_4/nn_tb.v, ditambah:
//   - pembacaan output BRAM setelah done
//   - output ditulis ke nn_out.txt (2 baris hex 64 bit, neuron 0 lalu neuron 1)
//   - jumlah clock start -> done ditulis ke nn_cycles.txt
//   - waveform ditulis ke nn_wave.vcd
// Testbench yang sama dipakai untuk nn.v asli (Full LUT) dan nn.v modifikasi
// (sigmoid_interp); bedanya hanya file sumber yang dikompilasi.
//////////////////////////////////////////////////////////////////////////////////
module nn_ann_tb();
    localparam T = 10;

    reg clk;
    reg rst_n;
    reg en;
    reg clr;

    wire ready;
    reg start;
    wire done;

    reg wb_ena;
    reg [2:0] wb_addra;
    reg [63:0] wb_dina;
    reg [7:0] wb_wea;

    reg k_ena;
    reg [1:0] k_addra;
    reg [63:0] k_dina;
    reg [7:0] k_wea;

    reg a_enb;
    reg [1:0] a_addrb;
    wire [63:0] a_doutb;

    nn dut
    (
        .clk(clk), .rst_n(rst_n), .en(en), .clr(clr),
        .ready(ready), .start(start), .done(done),
        .wb_ena(wb_ena), .wb_addra(wb_addra), .wb_dina(wb_dina), .wb_wea(wb_wea),
        .k_ena(k_ena), .k_addra(k_addra), .k_dina(k_dina), .k_wea(k_wea),
        .a_enb(a_enb), .a_addrb(a_addrb), .a_doutb(a_doutb)
    );

    always
    begin
        clk = 0;
        #(T/2);
        clk = 1;
        #(T/2);
    end

    integer f_out, f_cyc, n_cyc;

    initial
    begin
        $dumpfile("nn_wave.vcd");
        $dumpvars(2, nn_ann_tb);   // sinyal tb + sinyal internal nn (dut)

        en = 1; clr = 0; start = 0;
        wb_ena = 1; wb_addra = 0; wb_dina = 0; wb_wea = 0;
        k_ena = 1;  k_addra = 0;  k_dina = 0;  k_wea = 0;
        a_enb = 0;  a_addrb = 0;

        rst_n = 0;
        #(T*5);
        rst_n = 1;
        #(T*5);

        // *** Bobot dan bias (sama dengan pynq_part_4/nn_tb.v) ***
        wb_wea = 8'hff;
        wb_addra = 0; wb_dina = 64'h0000_B07A_057A_057A; #T;
        wb_addra = 1; wb_dina = 64'h0000_FC66_03E1_0314; #T;
        wb_addra = 2; wb_dina = 64'h0000_FC70_028F_0433; #T;
        wb_addra = 3; wb_dina = 64'hF5A3_0051_FAC2_1C70; #T;
        wb_addra = 4; wb_dina = 64'h00CC_07E1_0685_E399; #T;
        wb_wea = 8'h00; wb_addra = 0; wb_dina = 0;
        #T;

        // *** Input: x0 = [8 8 5 5], x1 = [8 5 8 5] ***
        k_wea = 8'hff;
        k_addra = 0; k_dina = 64'h1400_1400_2000_2000; #T;
        k_addra = 1; k_dina = 64'h1400_2000_1400_2000; #T;
        k_wea = 8'h00; k_addra = 0; k_dina = 0;
        #T;

        // *** Start dan hitung clock sampai done ***
        start = 1;
        #T;
        start = 0;
        n_cyc = 1;
        while (!done)
        begin
            #T;
            n_cyc = n_cyc + 1;
        end
        #(T*2);

        // *** Baca output BRAM (latency baca 1 clk) ***
        f_out = $fopen("nn_out.txt", "w");
        a_enb = 1;
        a_addrb = 0; #T; #1 $fdisplay(f_out, "%h", a_doutb); #(T-1);
        a_addrb = 1; #T; #1 $fdisplay(f_out, "%h", a_doutb); #(T-1);
        a_enb = 0;
        $fclose(f_out);

        f_cyc = $fopen("nn_cycles.txt", "w");
        $fdisplay(f_cyc, "%0d", n_cyc);
        $fclose(f_cyc);

        $display("ANN selesai: start->done = %0d clk", n_cyc);
        #(T*5);
        $finish;
    end

endmodule
