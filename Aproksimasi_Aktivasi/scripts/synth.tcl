# Synthesis out-of-context untuk setiap modul sigmoid + laporan utilization,
# timing, dan power. Tidak butuh board.
#
# Jalankan dari folder Aproksimasi_Aktivasi:
#   vivado -mode batch -nojournal -nolog -source scripts/synth.tcl -tclargs <part>
#
# <part> default: xc7z010clg400-1 (Zynq-7000, mis. Zybo Z7-10).
# Contoh lain   : xc7z020clg400-1 (Zybo Z7-20 / PYNQ-Z2).
# Kalau device Zynq tidak terinstal, pakai Artix-7 (fabric PL Zynq-7000 = Artix-7),
# mis. xc7a35tcpg236-1.

set part   [expr {[llength $argv] > 0 ? [lindex $argv 0] : "xc7z010clg400-1"}]
set period 10.0   ;# target clock 100 MHz

set root [file normalize [file dirname [file dirname [info script]]]]
set repo [file dirname $root]
set out  [file join $root results synth_$part]
file mkdir $out

set designs {
    sigmoid        {pynq_part_4/sigmoid.v}
    sigmoid_hard   {Aproksimasi_Aktivasi/rtl/sigmoid_hard.v}
    sigmoid_plan   {Aproksimasi_Aktivasi/rtl/sigmoid_plan.v}
    sigmoid_interp {Aproksimasi_Aktivasi/rtl/sigmoid_interp.v}
}

set summary [open [file join $out summary.csv] w]
puts $summary "module,LUT,FF,DSP,BRAM,WNS_ns,Fmax_MHz,total_power_W"

foreach {top file} $designs {
    close_project -quiet
    create_project -in_memory -part $part
    read_verilog [file join $repo pynq_part_4 register.v]
    read_verilog [file join $repo $file]
    synth_design -top $top -part $part -mode out_of_context

    # Constraint: semua path input -> register -> output diukur terhadap clk
    create_clock -name clk -period $period [get_ports clk]
    set ins [get_ports -filter {DIRECTION == IN && NAME != clk}]
    set_input_delay  0 -clock clk $ins
    set_output_delay 0 -clock clk [all_outputs]

    report_utilization    -file [file join $out ${top}_utilization.rpt]
    report_timing_summary -file [file join $out ${top}_timing.rpt]
    report_power          -file [file join $out ${top}_power.rpt]

    # Angka resource diambil dari laporan utilization (Slice LUTs, dst.)
    set fp [open [file join $out ${top}_utilization.rpt] r]
    set ut [read $fp]
    close $fp
    regexp {\|\s*Slice LUTs\*?\s*\|\s*([0-9]+)} $ut -> lut
    regexp {\|\s*Slice Registers\s*\|\s*([0-9]+)} $ut -> ff
    regexp {\|\s*DSPs\s*\|\s*([0-9]+)} $ut -> dsp
    regexp {\|\s*Block RAM Tile\s*\|\s*([0-9.]+)} $ut -> bram
    set wns  [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
    set fmax [format %.1f [expr {1000.0 / ($period - $wns)}]]
    set pwr  "?"
    set fp [open [file join $out ${top}_power.rpt] r]
    regexp {Total On-Chip Power \(W\)\s*\|\s*([0-9.]+)} [read $fp] -> pwr
    close $fp
    puts $summary "$top,$lut,$ff,$dsp,$bram,$wns,$fmax,$pwr"
    puts "== $top: LUT=$lut FF=$ff DSP=$dsp BRAM=$bram WNS=$wns Fmax=$fmax MHz P=$pwr W"
}

close $summary
puts "Ringkasan: [file join $out summary.csv]"
