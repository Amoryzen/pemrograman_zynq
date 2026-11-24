"""
Cek hasil simulasi ANN 2-3-2 terhadap golden model Python, lalu buat gambar waveform.

Dipanggil oleh scripts/run_ann_sim.ps1, atau manual dari folder Aproksimasi_Aktivasi:
    python model/ann_check.py

Input : results/ann_<lut|interp>/nn_out.txt, nn_cycles.txt, nn_wave.vcd
Output: results/ann_compare.md, results/ann_waveform_<lut|interp>.png
"""
import re
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sigmoid_models import sigmoid_interp, sigmoid_lut  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
RESULTS = ROOT / "results"
ONE = 1024

# Bobot/bias dan input, sama dengan tb/nn_ann_tb.v (lane 0 = 16 bit terbawah)
WB = [0x0000_B07A_057A_057A, 0x0000_FC66_03E1_0314, 0x0000_FC70_028F_0433,
      0xF5A3_0051_FAC2_1C70, 0x00CC_07E1_0685_E399]
K = [0x1400_1400_2000_2000, 0x1400_2000_1400_2000]

# Output board asli (pynq_part_4/nn.ipynb, versi Full LUT di PYNQ)
BOARD_LUT = [0x0014_002B_002B_03A8, 0x03E8_03CF_03CF_004D]

VARIANTS = {"lut": ("Full LUT 256 (asli)", sigmoid_lut),
            "interp": ("LUT 33 + interpolasi", sigmoid_interp)}


def lanes(word):
    v = np.array([(word >> (16 * i)) & 0xFFFF for i in range(4)], dtype=np.int64)
    return np.where(v >= 0x8000, v - 0x10000, v)


def wrap16(v):
    return ((v + 0x8000) & 0xFFFF) - 0x8000


def matmul_q(w, b):
    """Systolic: y_j = sum_i trunc16((w_i * b_ij) >> 10), penjumlahan 16 bit."""
    prod = wrap16((w[:, :, None] * b[None, :, :]) >> 10)
    return wrap16(prod.sum(axis=1))


def nn_fixed(sig):
    w1 = np.stack([lanes(x) for x in WB[:3]])
    w2 = np.stack([lanes(x) for x in WB[3:]])
    k1 = np.stack([lanes(K[0]), lanes(K[1]), np.full(4, ONE), np.zeros(4, np.int64)])
    a1 = sig(matmul_q(w1, k1))
    k2 = np.vstack([a1, np.full((1, 4), ONE)])
    return sig(matmul_q(w2, k2))


def nn_float():
    w1 = np.stack([lanes(x) for x in WB[:3]]) / ONE
    w2 = np.stack([lanes(x) for x in WB[3:]]) / ONE
    k1 = np.stack([lanes(K[0]), lanes(K[1]), np.full(4, ONE), np.zeros(4)]) / ONE
    a1 = 1 / (1 + np.exp(-(w1 @ k1)))
    k2 = np.vstack([a1, np.ones((1, 4))])
    return 1 / (1 + np.exp(-(w2 @ k2)))


def read_sim(v):
    d = RESULTS / f"ann_{v}"
    words = [int(x, 16) for x in (d / "nn_out.txt").read_text().split()]
    out = np.stack([lanes(w) for w in words])
    cyc = int((d / "nn_cycles.txt").read_text().split()[0])
    return out, cyc


# ------------------------------------------------------------------ VCD
def parse_vcd(path):
    """Kembalikan {nama: [(waktu, nilai_int_or_None)]} untuk sinyal di dut/tb."""
    ids, scope, sig = {}, [], {}
    t = 0
    with open(path) as f:
        for line in f:
            tok = line.split()
            if not tok:
                continue
            if tok[0] == "$scope":
                scope.append(tok[2])
            elif tok[0] == "$upscope":
                scope.pop()
            elif tok[0] == "$var":
                name = ".".join(scope[1:] + [tok[4]])
                ids.setdefault(tok[3], []).append(name)
                sig[name] = []
            elif tok[0].startswith("#"):
                t = int(tok[0][1:])
            elif tok[0][0] in "01xzXZ" and len(tok) == 1 and tok[0][0] != "$":
                val = None if tok[0][0] in "xzXZ" else int(tok[0][0])
                for n in ids.get(tok[0][1:], []):
                    sig[n].append((t, val))
            elif tok[0][0] in "bB":
                bits = tok[0][1:]
                val = None if re.search("[xzXZ]", bits) else int(bits, 2)
                for n in ids.get(tok[1], []):
                    sig[n].append((t, val))
    return sig


def value_at(changes, t):
    v = None
    for tc, val in changes:
        if tc > t:
            break
        v = val
    return v


def plot_waveform(v, title):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    sig = parse_vcd(RESULTS / f"ann_{v}" / "nn_wave.vcd")
    clk = [t for t, val in sig["clk"] if val == 1]
    period = clk[1] - clk[0]
    t_start = next(t for t, val in sig["start"] if val == 1)
    t_done = next(t for t, val in sig["dut.done"] if val == 1)
    t0 = t_start - period
    t1 = t_done + 2 * period

    def s16(x):
        return x - 0x10000 if x is not None and x >= 0x8000 else x

    rows = [
        ("clk", "clk", "bit", None),
        ("start", "start", "bit", None),
        ("cnt_main_reg", "dut.cnt_main_reg", "bus", lambda x: f"{x}"),
        ("sys_in_valid", "dut.sys_in_valid", "bit", None),
        ("sys_out_valid", "dut.sys_out_valid", "bit", None),
        ("y0 (systolic)", "dut.y0", "bus", lambda x: f"{s16(x) / ONE:.2f}"),
        ("s0 (sigmoid)", "dut.s0", "bus", lambda x: f"{x / ONE:.3f}"),
        ("sig_out_valid", "dut.sig_out_valid", "bit", None),
        ("a_ena (tulis out)", "dut.a_ena", "bit", None),
        ("done", "done", "bit", None),
    ]

    fig, ax = plt.subplots(figsize=(16, 0.62 * len(rows) + 1.2))
    h = 0.6
    for r, (label, name, kind, fmt) in enumerate(rows):
        y = len(rows) - 1 - r
        ch = [(t, val) for t, val in sig[name]]
        # titik perubahan di jendela
        pts = [t0] + [t for t, _ in ch if t0 < t < t1] + [t1]
        vals = [value_at(ch, t) for t in pts[:-1]]
        if kind == "bit":
            xs, ys = [], []
            for a, b, val in zip(pts[:-1], pts[1:], vals):
                lvl = y + (h if val else 0)
                xs += [a, b]
                ys += [lvl, lvl]
            ax.plot(xs, ys, color="#1f6fb2", lw=1.3)
        else:
            for a, b, val in zip(pts[:-1], pts[1:], vals):
                d = min(period * 0.15, (b - a) / 3)
                ax.fill([a, a + d, b - d, b, b - d, a + d],
                        [y + h / 2, y + h, y + h, y + h / 2, y, y],
                        facecolor="#e8f1fa", edgecolor="#1f6fb2", lw=1)
                if val is not None and (b - a) >= period * 0.9:
                    ax.text((a + b) / 2, y + h / 2, fmt(val), ha="center",
                            va="center", fontsize=6.5)
        ax.text(t0 - period * 0.3, y + h / 2, label, ha="right", va="center",
                fontsize=9, family="monospace")
    ax.set_xlim(t0 - period * 7.5, t1)
    ax.set_ylim(-0.4, len(rows))
    ax.set_yticks([])
    ticks = [t for t in clk if t0 <= t <= t1][::5]
    ax.set_xticks(ticks)
    ax.set_xticklabels([f"{(t - t_start) // period}" for t in ticks], fontsize=8)
    ax.set_xlabel("clock setelah start")
    for t in clk:
        if t0 <= t <= t1:
            ax.axvline(t, color="#dddddd", lw=0.5, zorder=0)
    for s in ("top", "right", "left"):
        ax.spines[s].set_visible(False)
    ax.set_title(title, fontsize=12)
    fig.tight_layout()
    out = RESULTS / f"ann_waveform_{v}.png"
    fig.savefig(out, dpi=170)
    plt.close(fig)
    return out


def main():
    ref = nn_float()
    samples = [(8, 8), (8, 5), (5, 8), (5, 5)]
    ok = True
    hw = {}
    lines = []
    for v, (name, fn) in VARIANTS.items():
        sim, cyc = read_sim(v)
        gold = nn_fixed(fn)
        match = np.array_equal(sim, gold)
        ok &= match
        hw[v] = (sim, cyc)
        print(f"[{'PASS' if match else 'FAIL'}] {name}: simulasi vs model Python "
              f"bit-exact={match}, start->done = {cyc} clk")
        if not match:
            print("  sim :", sim.tolist()); print("  gold:", gold.tolist())
    board = np.stack([lanes(w) for w in BOARD_LUT])
    print(f"[{'PASS' if np.array_equal(hw['lut'][0], board) else 'FAIL'}] "
          "Simulasi Full LUT == output board PYNQ di nn.ipynb")

    lines.append("| Sampel (x0, x1) | Neuron | Float (ideal) | Full LUT | |err| LUT "
                 "| LUT33+interp | |err| interp | Kelas |")
    lines.append("|---|---|---|---|---|---|---|---|")
    err = {v: [] for v in VARIANTS}
    for n in range(2):
        for j, s in enumerate(samples):
            f = ref[n, j]
            row = [f"({s[0]}, {s[1]})", f"y{n}", f"{f:.4f}"]
            for v in VARIANTS:
                q = hw[v][0][n, j] / ONE
                err[v].append(abs(q - f))
                row += [f"{q:.4f}", f"{abs(q - f):.4f}"]
            row.append(f"{int(round(hw['interp'][0][n, j] / ONE))}")
            lines.append("| " + " | ".join(row) + " |")
    lines.append("")
    lines.append("| Versi | Error maks output | Error rata-rata | Latency start->done |")
    lines.append("|---|---|---|---|")
    for v, (name, _) in VARIANTS.items():
        e = np.array(err[v])
        lines.append(f"| {name} | {e.max():.4f} | {e.mean():.4f} | {hw[v][1]} clk |")
    cls_same = np.array_equal(np.round(hw["lut"][0] / ONE), np.round(hw["interp"][0] / ONE))
    lines.append("")
    lines.append(f"Kelas (pembulatan output) LUT vs interp sama: {cls_same}")
    text = "\n".join(lines)
    (RESULTS / "ann_compare.md").write_text(text + "\n", encoding="utf-8")
    print(text)

    for v, (name, _) in VARIANTS.items():
        p = plot_waveform(v, f"Waveform ANN - sigmoid {name}")
        print("Waveform:", p)
    raise SystemExit(0 if ok else 1)


if __name__ == "__main__":
    main()
