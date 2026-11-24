# Simulasi ANN lengkap (xsim) untuk dua versi:
#   lut    : pynq_part_4/nn.v asli + sigmoid Full LUT 256
#   interp : ann/nn.v modifikasi + sigmoid_interp (LUT 33 + interpolasi)
# Hasil per versi di results/ann_<versi>/ : nn_out.txt, nn_cycles.txt, nn_wave.vcd
# Lalu model/ann_check.py membandingkan dengan golden model Python dan membuat
# gambar waveform.
# Jalankan dari folder Aproksimasi_Aktivasi:
#   powershell -ExecutionPolicy Bypass -File scripts/run_ann_sim.ps1
param(
    [string]$VivadoBin = "C:\AMDDesignTools\2026.1\Vivado\bin"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$repo = Split-Path -Parent $root
$p4 = Join-Path $repo "pynq_part_4"

$common = @("$p4\register.v", "$p4\pe.v", "$p4\systolic.v", "$root\tb\nn_ann_tb.v")
$variants = @{
    "lut"    = @("$p4\sigmoid.v", "$p4\nn.v")
    "interp" = @("$root\rtl\sigmoid_interp.v", "$root\ann\nn.v")
}

foreach ($v in $variants.Keys) {
    $work = Join-Path $root "results\ann_$v"
    New-Item -ItemType Directory -Force $work | Out-Null
    Push-Location $work
    try {
        & "$VivadoBin\xvlog.bat" ($common + $variants[$v])
        if ($LASTEXITCODE -ne 0) { throw "xvlog gagal ($v)" }
        & "$VivadoBin\xelab.bat" nn_ann_tb -L xpm -s ann_sim -timescale 1ns/1ps
        if ($LASTEXITCODE -ne 0) { throw "xelab gagal ($v)" }
        & "$VivadoBin\xsim.bat" ann_sim -runall
        if ($LASTEXITCODE -ne 0) { throw "xsim gagal ($v)" }
    } finally {
        Pop-Location
    }
}

python "$root\model\ann_check.py"
