"""
Buat file tampilan GTKWave (.gtkw + .tcl zoom) untuk VCD simulasi ANN.

Pemakaian (dari folder Aproksimasi_Aktivasi, setelah scripts/run_ann_sim.ps1):
    python scripts/make_gtkw.py

Output per versi di results/ann_<lut|interp>/:
    nn_wave.gtkw       + nn_wave_zoom.tcl     semua sinyal penting (6 grup)
    view_overview.gtkw + view_overview.tcl    ringkas: satu inferensi penuh
    view_pipeline.gtkw + view_pipeline.tcl    zoom ke pipeline sigmoid layer 1

Buka di GTKWave (dari folder results/ann_interp):
    gtkwave nn_wave.vcd nn_wave.gtkw -S nn_wave_zoom.tcl
Skrip -S hanya mengatur zoom; tanpa -S tampilan tetap bisa dipakai (lalu "Zoom Fit").
"""
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESULTS = ROOT / "results"

# Flag format trace GTKWave
BIN, DEC, HEX, SDEC = "@28", "@24", "@22", "@420"
REAL = "@420"   # var bertipe real otomatis ditampilkan sebagai bilangan real
GRP_BEGIN, GRP_END, COMMENT = "@800200", "@1000200", "@200"

TB = "nn_ann_tb"
D = f"{TB}.dut"


def groups(variant):
    sig = f"{D}.sigmoid_0"
    if variant == "interp":
        sig_pipe = [
            ("din = y0 (Q6.10)", [(SDEC, f"{sig}.din[15:0]", 0)]),
            (None, [(DEC, f"{sig}.i[4:0]", 0), (DEC, f"{sig}.f[7:0]", 0)]),
            ("stage 1 -> register", [(DEC, f"{sig}.t0p_r[14:0]", 0), (DEC, f"{sig}.d_r[9:0]", 0),
                                     (DEC, f"{sig}.f_r[7:0]", 0), (BIN, f"{sig}.neg_r", 0),
                                     (BIN, f"{sig}.sat_r", 0)]),
            ("stage 2 -> dout = s0", [(DEC, f"{sig}.dout[15:0]", 3)]),
        ]
    else:
        sig_pipe = [
            ("din = y0 (Q6.10)", [(SDEC, f"{sig}.din[15:0]", 0)]),
            (None, [(HEX, f"{sig}.addr[7:0]", 0)]),
            ("dout = s0", [(DEC, f"{sig}.dout[15:0]", 3)]),
        ]
    return [
        ("1. Control", [
            (None, [(BIN, f"{TB}.clk", 0), (BIN, f"{TB}.rst_n", 0), (BIN, f"{TB}.start", 2),
                    (BIN, f"{TB}.ready", 0), (DEC, f"{D}.cnt_main_reg[5:0]", 0),
                    (BIN, f"{TB}.done", 2)]),
        ]),
        ("2. Systolic (z = W.x + b)", [
            (None, [(BIN, f"{D}.sys_in_valid", 0), (BIN, f"{D}.sys_out_valid", 4),
                    (REAL, f"{TB}.z0_real", 4), (REAL, f"{TB}.z1_real", 0),
                    (REAL, f"{TB}.z2_real", 0), (REAL, f"{TB}.z3_real", 0),
                    (SDEC, f"{D}.y0[15:0]", 0)]),
        ]),
        ("3. Sigmoid (a = sigma(z))", [
            (None, [(BIN, f"{D}.sig_out_valid", 4), (REAL, f"{TB}.a0_real", 3),
                    (REAL, f"{TB}.a1_real", 0), (REAL, f"{TB}.a2_real", 0),
                    (REAL, f"{TB}.a3_real", 0), (DEC, f"{D}.s0[15:0]", 0)]),
        ]),
        ("4. Inside sigmoid_0 (pipeline)", sig_pipe),
        ("5. Feedback layer 1 -> layer 2", [
            (None, [(DEC, f"{D}.b00_reg[15:0]", 0), (DEC, f"{D}.b10_reg[15:0]", 0),
                    (DEC, f"{D}.b20_reg[15:0]", 0), (DEC, f"{D}.b30_reg[15:0]", 0)]),
        ]),
        ("6. Output BRAM", [
            (None, [(BIN, f"{D}.a_ena", 1), (DEC, f"{D}.a_addra[1:0]", 0),
                    (HEX, f"{D}.a_dina[63:0]", 0), (BIN, f"{TB}.a_enb", 0),
                    (DEC, f"{TB}.a_addrb[1:0]", 0), (HEX, f"{TB}.a_doutb[63:0]", 1)]),
        ]),
    ]


def vcd_times(vcd):
    """Waktu (ps) tepi naik pertama start dan done, serta periode clock."""
    ids, t, rises = {}, 0, {}
    for line in vcd.read_text().splitlines():
        tok = line.split()
        if not tok:
            continue
        if tok[0] == "$var" and tok[4] in ("start", "done", "clk") and tok[4] not in ids.values():
            ids[tok[3]] = tok[4]
        elif tok[0].startswith("#"):
            t = int(tok[0][1:])
        elif tok[0][0] == "1" and tok[0][1:] in ids:
            rises.setdefault(ids[tok[0][1:]], []).append(t)
    clk = rises["clk"]
    return rises["start"][0], rises["done"][0], clk[1] - clk[0]


def write_view(d, name, grps, t0, t1, marker, tcl_name, width=1500, sigw=250):
    nrows = sum(2 + sum((1 if lab else 0) + len(sg) for lab, sg in sub) for _, sub in grps)
    size = (width, min(860, 175 + 20 * nrows))
    zoom = -math.log2((t1 - t0) / (size[0] - sigw - 60))
    lines = [
        "[*]",
        "[*] GTKWave view for the ANN simulation (Aproksimasi_Aktivasi)",
        f"[*] Open: gtkwave nn_wave.vcd {name}.gtkw -S {tcl_name}",
        "[*]",
        '[dumpfile] "nn_wave.vcd"',
        f"[timestart] {t0}",
        f"[size] {size[0]} {size[1]}",
        "[pos] 0 0",
        f"*{zoom:.6f} {marker} " + " ".join(["-1"] * 26),
        f"[treeopen] {TB}.",
        f"[treeopen] {D}.",
        "[sst_width] 1",
        f"[signals_width] {sigw}",
        "[sst_expanded] 0",
        "[sst_vpaned_height] 0",
    ]
    for title, sub in grps:
        lines += [GRP_BEGIN, f"-{title}"]
        for label, sigs in sub:
            if label:
                lines += [COMMENT, f"-  {label}"]
            for fmt, sname, color in sigs:
                if color:
                    lines.append(f"[color] {color}")
                lines += [fmt, sname]
        lines += [GRP_END, f"-{title}"]
    lines += ["[pattern_trace] 1", "[pattern_trace] 0"]
    (d / f"{name}.gtkw").write_text("\n".join(lines) + "\n", encoding="utf-8")
    tcl = f"gtkwave::setZoomRangeTimes {t0} {t1}\n"
    if marker >= 0:
        tcl += f"gtkwave::setMarker {marker}\n"
    (d / tcl_name).write_text(tcl, encoding="utf-8")
    print(f"{d / name}.gtkw  ({t0}..{t1} ps)")


def pick(grps, keep):
    """Tampilan ringkas: ambil sinyal yang namanya berakhiran salah satu `keep`."""
    out = []
    for title, sub in grps:
        new = []
        for label, sigs in sub:
            s2 = [x for x in sigs if any(x[1].endswith(k) for k in keep)]
            if s2:
                new.append((label if len(s2) == len(sigs) else None, s2))
        if new:
            out.append((title, new))
    return out


# Tampilan ringkas untuk slide: (nama, sinyal, cnt awal, cnt akhir)
VIEWS = [
    ("view_overview", [".clk", ".start", "cnt_main_reg[5:0]", ".done", "sys_in_valid",
                       "sys_out_valid", "sig_out_valid", ".a_ena"], -1, 36),
    ("view_layer1", [".clk", "cnt_main_reg[5:0]", "sys_out_valid", "z0_real", "z1_real",
                     "z2_real", "z3_real", "sig_out_valid", "a0_real", "a1_real", "a2_real",
                     "a3_real", "b00_reg[15:0]", "b10_reg[15:0]", "b20_reg[15:0]",
                     "b30_reg[15:0]"], 11, 19),
    ("view_pipeline", [".clk", "cnt_main_reg[5:0]", "sys_out_valid", "din[15:0]", ".i[4:0]",
                       ".f[7:0]", "t0p_r[14:0]", "d_r[9:0]", "f_r[7:0]", "addr[7:0]",
                       "dout[15:0]", "sig_out_valid"], 12, 18),
    ("view_layer2", [".clk", "cnt_main_reg[5:0]", ".done", "sys_out_valid", "z0_real",
                     "z1_real", "z2_real", "z3_real", "sig_out_valid", "a0_real", "a1_real",
                     "a2_real", "a3_real", ".a_ena", "a_addra[1:0]", "a_dina[63:0]"], 26, 35),
]


def write_all(variant):
    d = RESULTS / f"ann_{variant}"
    t_start, t_done, period = vcd_times(d / "nn_wave.vcd")
    full = groups(variant)
    write_view(d, "nn_wave", full, t_start - period, t_done + 6 * period, -1,
               "nn_wave_zoom.tcl")
    # cnt_main_reg = k berlaku pada [t_start + (k - 0.5)T, t_start + (k + 0.5)T)
    for name, keep, k0, k1 in VIEWS:
        t0 = t_start + int((k0 - 0.5) * period)
        t1 = t_start + int((k1 + 0.5) * period)
        write_view(d, name, pick(full, keep), t0, t1, -1, f"{name}.tcl")


if __name__ == "__main__":
    for v in ("interp", "lut"):
        write_all(v)
