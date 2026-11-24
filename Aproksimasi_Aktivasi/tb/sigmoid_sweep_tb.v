`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Testbench sweep: memberi SEMUA 65536 input (-32768..32767, Q6.10) ke keempat
// modul sigmoid, lalu menulis output (hex, satu baris per input) ke:
//   sim_lut.txt, sim_hard.txt, sim_plan.txt, sim_interp.txt
// di folder kerja simulator. File ini dibandingkan dengan golden model Python:
//   python model/sigmoid_models.py --check-sim
//////////////////////////////////////////////////////////////////////////////////
module sigmoid_sweep_tb;

    localparam T = 10;   // 100 MHz

    reg         clk = 0;
    reg         rst_n = 0;
    reg         en = 1;
    reg         clr = 0;
    reg  [15:0] din = 16'h8000;
    wire [15:0] y_lut, y_hard, y_plan, y_interp;

    sigmoid        dut_lut    (clk, rst_n, en, clr, din, y_lut);
    sigmoid_hard   dut_hard   (clk, rst_n, en, clr, din, y_hard);
    sigmoid_plan   dut_plan   (clk, rst_n, en, clr, din, y_plan);
    sigmoid_interp dut_interp (clk, rst_n, en, clr, din, y_interp);

    always #(T/2) clk = ~clk;

    integer f_lut, f_hard, f_plan, f_interp, k;

    initial
    begin
        f_lut    = $fopen("sim_lut.txt", "w");
        f_hard   = $fopen("sim_hard.txt", "w");
        f_plan   = $fopen("sim_plan.txt", "w");
        f_interp = $fopen("sim_interp.txt", "w");

        #(2*T) rst_n = 1;

        // Latency maks 2 clk (sigmoid_interp). Input ditahan 2 posedge lalu
        // output dibaca; modul 1 clk tetap benar karena input tidak berubah.
        for (k = 0; k < 65536; k = k + 1)
        begin
            @(negedge clk) din = 16'h8000 + k;
            @(negedge clk);
            @(negedge clk);
            $fdisplay(f_lut,    "%h", y_lut);
            $fdisplay(f_hard,   "%h", y_hard);
            $fdisplay(f_plan,   "%h", y_plan);
            $fdisplay(f_interp, "%h", y_interp);
        end

        $fclose(f_lut); $fclose(f_hard); $fclose(f_plan); $fclose(f_interp);
        $display("Sweep selesai: 65536 input");
        $finish;
    end

endmodule
