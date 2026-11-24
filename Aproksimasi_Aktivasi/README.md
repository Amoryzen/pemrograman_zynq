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

## Integrasi ke ANN

Metode yang dipilih adalah **LUT 33 + interpolasi** karena error-nya paling kecil.
Modul ini dipasang ke salinan `nn.v` di `ann/nn.v`; file asli di `pynq_part_4/` tidak
diubah. Karena sigmoid baru 1 clk lebih lambat, ada beberapa penyesuaian:

| Bagian | nn.v asli | ann/nn.v |
|---|---|---|
| Modul aktivasi | `sigmoid` (1 clk) | `sigmoid_interp` (2 clk) |
| Umpan balik layer 1 → 2 | `s*_reg1` | `s*_reg0` (tetap tiba di cnt 16..18) |
| Tulis output BRAM | cnt 29..30 | cnt 30..31 |
| `done` | cnt 33 | cnt 34 |
| `sig_out_valid` | tunda 1 clk | tunda 2 clk |

`axis_nn.v` tidak perlu diubah karena FSM-nya menunggu `nn_ready`.

Hasil simulasi ANN (`results/ann_compare.md`):
- Output kedua versi cocok bit-exact dengan model Python (`model/ann_check.py`).
- Simulasi versi Full LUT sama persis dengan output board PYNQ di `pynq_part_4/nn.ipynb`.
- Error maksimum output terhadap ANN floating-point turun dari 0.0071 menjadi 0.0004.
  Kelas output tidak berubah.
- Waveform: `results/ann_waveform_interp.png` dan `results/ann_waveform_lut.png`.

### Place & route ANN lengkap (`axis_nn`, OOC, `xc7a35tcpg236-1`, 100 MHz)

| Metrik | Full LUT (asli) | LUT 33 + interp |
|---|---|---|
| LUT / FF | 790 / 791 | 896 / 857 |
| DSP48 / BRAM tile | 16 / 8.5 | 20 / 8.5 |
| WNS / WHS | 1.772 / 0.027 ns | 1.719 / 0.019 ns |
| Fmax (perkiraan) | 121.5 MHz | 120.8 MHz |
| Latency satu inferensi | 33 clk | 34 clk |

PnR memakai `ann/axis_nn_ooc.v` sebagai timing harness. Harness ini memberi register
pada semua port dan memodelkan clock dari BUFG, sehingga yang diukur adalah jalur
register → register seperti saat tersambung ke DMA Zynq. Resource di tabel adalah
milik `axis_nn` saja. Laporan lengkap ada di `results/impl_<part>/`. Presentasi ada di
`presentasi/`.

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
4. **Simulasi ANN** (versi lama dan baru) + cek model + gambar waveform:
   ```
   powershell -ExecutionPolicy Bypass -File scripts/run_ann_sim.ps1
   ```
5. **Synthesis + place & route ANN lengkap** (versi lama dan baru):
   ```
   vivado -mode batch -nojournal -nolog -source scripts/impl.tcl -tclargs xc7z010clg400-1
   ```

## Struktur

```
rtl/        modul Verilog aproksimasi
ann/        nn.v dengan sigmoid_interp
tb/         testbench sweep 65.536 input + testbench ANN
model/      golden model Python bit-exact (sigmoid dan ANN) + analisis error
scripts/    run_sim.ps1, run_ann_sim.ps1 (xsim), synth.tcl, impl.tcl (Vivado batch)
results/    tabel error, grafik, waveform, laporan synthesis dan place & route
presentasi/ slide untuk dikumpulkan
```
