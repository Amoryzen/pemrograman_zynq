# Aproksimasi Fungsi Aktivasi Sigmoid di FPGA

Perbandingan beberapa metode aproksimasi sigmoid (Tutorial: Function Approximation)
untuk fixed-point **Q6.10** (16 bit signed, 1.0 = 1024). Semua modul memiliki port yang
sama dengan `pynq_part_4/sigmoid.v`, yaitu `clk, rst_n, en, clr, din, dout`.
Verifikasi dilakukan dengan simulasi, lalu desain disintesis. Board tidak dibutuhkan.

| Modul | Metode | Kelas latency | Latency |
|---|---|---|---|
| `pynq_part_4/sigmoid.v` | Full LUT 256 entri (baseline) | Very low | 1 clk |
| `rtl/sigmoid_hard.v` | Hard sigmoid `clip(x/4 + 0.5)` | Very low | 1 clk |
| `rtl/sigmoid_plan.v` | PLAN shift-and-add (PWL + simetri) | Low | 1 clk |
| `rtl/sigmoid_interp.v` | LUT 33 titik + interpolasi linear + simetri | Low | 2 clk |

## Hasil

### Error (semua 65.536 input, dibandingkan dengan sigmoid floating-point)

| Metode | Error maks | MAE | RMSE |
|---|---|---|---|
| Full LUT 256 (baseline) | 0.01632 | 0.000968 | 0.002049 |
| Hard sigmoid | 0.11951 | 0.006038 | 0.019681 |
| PLAN shift-and-add | 0.01894 | 0.001507 | 0.004127 |
| LUT 33 + interpolasi | 0.00124 | 0.000091 | 0.000200 |

Grafik kurva dan error ada di `results/sigmoid_curves.png`.

### Synthesis (out-of-context, target 100 MHz, `xc7a35tcpg236-1`)

| Modul | LUT | FF | DSP | BRAM | WNS (ns) | Fmax (MHz) |
|---|---|---|---|---|---|---|
| sigmoid (Full LUT) | 43 | 10 | 0 | 0 | 7.501 | 400.2 |
| sigmoid_hard | 30 | 14 | 0 | 0 | 6.462 | 282.6 |
| sigmoid_plan | 108 | 16 | 0 | 0 | 2.669 | 136.4 |
| sigmoid_interp | 90 | 15 | 1 | 0 | 2.807 | 139.0 |

Catatan:
- Device Zynq-7000 tidak terinstal di Vivado yang dipakai, jadi synthesis dijalankan pada
  Artix-7. Fabric PL Zynq-7000 (7z010/7z020) adalah Artix-7 dengan speed grade yang sama,
  sehingga angkanya representatif. Kalau device Zynq terinstal, cukup ganti argumen part.
- Angka ini berasal dari synthesis, bukan place & route. Daya (~0.07 W) didominasi daya
  statis device, jadi kurang berguna untuk membandingkan modul sekecil ini.
- Full LUT 256 hanya memakai 43 LUT karena Vivado meminimalkan ROM menjadi logika
  (banyak bit output yang konstan). Error-nya bias negatif karena alamat LUT diambil
  dengan pemotongan (truncation) `din[13:6]`. Selain itu, entri `mem[8'b0100_1101]`
  sama dengan `mem[8'b0100_1100]`; kemungkinan ini salah salin.
- Versi interpolasi 1 clk menghasilkan WNS -4.2 ns (gagal 100 MHz). Karena itu modulnya
  dipipeline menjadi 2 clk, dan penjumlahan + pembulatannya digabung ke dalam DSP
  (`P = C + A*B`).

## Cara menjalankan

Semua perintah dijalankan dari folder `Aproksimasi_Aktivasi`.

1. **Golden model dan analisis error** (Python + numpy + matplotlib):
   ```
   python model/sigmoid_models.py
   ```
2. **Simulasi sweep dengan xsim dan cek bit-exact** terhadap golden model:
   ```
   powershell -ExecutionPolicy Bypass -File scripts/run_sim.ps1
   ```
   Ubah `-VivadoBin` kalau Vivado tidak berada di `C:\AMDDesignTools\2026.1\Vivado\bin`.
3. **Synthesis dan laporan** (utilization, timing, power) ke `results/synth_<part>/`:
   ```
   vivado -mode batch -nojournal -nolog -source scripts/synth.tcl -tclargs xc7z010clg400-1
   ```
   Ringkasannya ada di `results/synth_<part>/summary.csv`.

## Struktur

```
rtl/      modul Verilog aproksimasi
tb/       testbench sweep 65.536 input
model/    golden model Python bit-exact + analisis error
scripts/  run_sim.ps1 (xsim), synth.tcl (Vivado batch)
results/  tabel error, grafik, laporan synthesis
```
