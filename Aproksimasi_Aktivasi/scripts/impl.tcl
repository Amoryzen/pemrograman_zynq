# Synthesis + Place & Route (out-of-context) untuk ANN lengkap (top: axis_nn,
# yaitu IP AXI-Stream yang dipasang ke DMA Zynq) dalam dua versi:
#   lut    : pynq_part_4/nn.v + sigmoid Full LUT 256 (asli)
#   interp : ann/nn.v + sigmoid_interp (LUT 33 + interpolasi)
# Tidak butuh board: out-of-context berarti tidak ada pin I/O fisik.
# Top-level adalah ann/axis_nn_ooc.v (timing harness): semua port axis_nn diberi
# register, port top-level di-false-path, sehingga timing yang dilaporkan adalah
# jalur register -> register. Resource diambil dari instance "dut" (axis_nn saja).
#
# Jalankan dari folder Aproksimasi_Aktivasi:
#   vivado -mode batch -nojournal -nolog -source scripts/impl.tcl -tclargs <part>
# <part> default xc7z010clg400-1. Kalau device Zynq tidak terinstal:
#   xc7a35tcpg236-1 (fabric PL Zynq-7000 = Artix-7)

set part   [expr {[llength $argv] > 0 ? [lindex $argv 0] : "xc7z010clg400-1"}]
set period 10.0   ;# 100 MHz, sama dengan FCLK_CLK0 default Zynq PS

set root [file normalize [file dirname [file dirname [info script]]]]
set repo [file dirname $root]
set p4   [file join $repo pynq_part_4]
set out  [file join $root results impl_$part]
file mkdir $out

set common [list $p4/register.v $p4/pe.v $p4/systolic.v $p4/axis_nn.v $root/ann/axis_nn_ooc.v]
set variants [dict create \
    lut    [list $p4/sigmoid.v $p4/nn.v] \
    interp [list $root/rtl/sigmoid_interp.v $root/ann/nn.v]]

set summary [open [file join $out summary.csv] w]
puts $summary "versi,LUT,FF,DSP,BRAM_tile,WNS_ns,WHS_ns,Fmax_MHz,total_power_W,dynamic_power_W"

dict for {v files} $variants {
    close_project -quiet
    create_project -in_memory -part $part
    read_verilog [concat $common $files]
    synth_design -top axis_nn_ooc -part $part -mode out_of_context

    create_clock -name aclk -period $period [get_ports aclk]
    # OOC: clock dimodelkan berasal dari BUFG (seperti FCLK_CLK0 Zynq)
    set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports aclk]
    # Port top-level hanya milik harness, bukan bagian desain
    set_false_path -from [get_ports -filter {DIRECTION == IN && NAME != aclk}]
    set_false_path -to   [all_outputs]

    opt_design
    place_design
    phys_opt_design
    route_design

    report_utilization    -file [file join $out ${v}_utilization_total.rpt]
    report_utilization -cells [get_cells dut] -file [file join $out ${v}_utilization.rpt]
    report_utilization -hierarchical -file [file join $out ${v}_utilization_hier.rpt]
    report_timing_summary -file [file join $out ${v}_timing.rpt]
    report_power          -file [file join $out ${v}_power.rpt]
    write_checkpoint -force [file join $out ${v}_routed.dcp]

    # Angka resource axis_nn (instance dut) dari laporan utilization
    set fp [open [file join $out ${v}_utilization.rpt] r]
    set ut [read $fp]
    close $fp
    regexp {\|\s*Slice LUTs\*?\s*\|\s*([0-9]+)} $ut -> lut
    regexp {\|\s*Slice Registers\s*\|\s*([0-9]+)} $ut -> ff
    regexp {\|\s*DSPs\s*\|\s*([0-9]+)} $ut -> dsp
    regexp {\|\s*Block RAM Tile\s*\|\s*([0-9.]+)} $ut -> bram
    set wns  [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
    set whs  [get_property SLACK [get_timing_paths -max_paths 1 -hold]]
    set fmax [format %.1f [expr {1000.0 / ($period - $wns)}]]
    set fp [open [file join $out ${v}_power.rpt] r]
    set txt [read $fp]
    close $fp
    set pt "?"; set pd "?"
    regexp {Total On-Chip Power \(W\)\s*\|\s*([0-9.]+)} $txt -> pt
    regexp {Dynamic \(W\)\s*\|\s*([0-9.]+)} $txt -> pd
    puts $summary "$v,$lut,$ff,$dsp,$bram,$wns,$whs,$fmax,$pt,$pd"
    puts "== $v: LUT=$lut FF=$ff DSP=$dsp BRAM=$bram WNS=$wns WHS=$whs Fmax=$fmax MHz P=$pt W (dyn $pd W)"
}

close $summary
puts "Ringkasan: [file join $out summary.csv]"
