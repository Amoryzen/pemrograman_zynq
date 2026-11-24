# Simulasi sweep dengan Vivado xsim, lalu cek bit-exact terhadap golden model Python.
# Jalankan dari folder Aproksimasi_Aktivasi:
#   powershell -ExecutionPolicy Bypass -File scripts/run_sim.ps1
# Ubah -VivadoBin kalau Vivado terpasang di lokasi lain.
param(
    [string]$VivadoBin = "C:\AMDDesignTools\2026.1\Vivado\bin"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$repo = Split-Path -Parent $root
$work = Join-Path $root "results"
New-Item -ItemType Directory -Force $work | Out-Null

$src = @(
    "$repo\pynq_part_4\register.v",
    "$repo\pynq_part_4\sigmoid.v",
    "$root\rtl\sigmoid_hard.v",
    "$root\rtl\sigmoid_plan.v",
    "$root\rtl\sigmoid_interp.v",
    "$root\tb\sigmoid_sweep_tb.v"
)

Push-Location $work
try {
    & "$VivadoBin\xvlog.bat" $src
    if ($LASTEXITCODE -ne 0) { throw "xvlog gagal" }
    & "$VivadoBin\xelab.bat" sigmoid_sweep_tb -s sweep_sim -timescale 1ns/1ps
    if ($LASTEXITCODE -ne 0) { throw "xelab gagal" }
    & "$VivadoBin\xsim.bat" sweep_sim -runall
    if ($LASTEXITCODE -ne 0) { throw "xsim gagal" }
} finally {
    Pop-Location
}

python "$root\model\sigmoid_models.py" --check-sim
