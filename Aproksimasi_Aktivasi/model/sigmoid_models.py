"""
Golden model bit-exact untuk semua metode aproksimasi sigmoid (Q6.10).

Pemakaian (dari folder Aproksimasi_Aktivasi):
    python model/sigmoid_models.py              # tabel error + grafik
    python model/sigmoid_models.py --check-sim  # + bandingkan dengan output simulasi

Output:
    results/error_table.md   tabel error tiap metode
    results/sigmoid_curves.png kurva dan error
"""
import argparse
import math
import re
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
REPO = ROOT.parent
RESULTS = ROOT / "results"
FRAC = 10
ONE = 1 << FRAC  # 1.0 dalam Q6.10

# Semua kemungkinan input 16 bit signed
X_INT = np.arange(-32768, 32768, dtype=np.int64)


# ---------------------------------------------------------------- metode
def sigmoid_lut(x):
    """Baseline: Full LUT 256 entri dari pynq_part_4/sigmoid.v."""
    src = (REPO / "pynq_part_4" / "sigmoid.v").read_text()
    mem = {}
    for addr, val in re.findall(r"mem\[8'b([01_]+)\]\s*=\s*32'b([01_]+);", src):
        mem[int(addr.replace("_", ""), 2)] = int(val.replace("_", ""), 2)
    u = x & 0xFFFF
    top = (u >> 13) & 0b111
    sat = (top != 0b111) & (top != 0)
    addr = (u >> 6) & 0xFF
    addr = np.where(sat, np.where(u >> 15, 0x80, 0x7F), addr)
    lut = np.array([(mem[a] >> 14) & 0xFFFF for a in range(256)], dtype=np.int64)
    return lut[addr]


def sigmoid_hard(x):
    s = (x >> 2) + 512
    return np.clip(s, 0, ONE)


def sigmoid_plan(x):
    ax = np.abs(x)
    y = np.where(ax >= 5120, ONE,
        np.where(ax >= 2432, (ax >> 5) + 864,
        np.where(ax >= 1024, (ax >> 3) + 640,
                             (ax >> 2) + 512)))
    return np.where(x < 0, ONE - y, y)


INTERP_TBL = np.array([round(16384 / (1 + math.exp(-k / 4))) for k in range(33)],
                      dtype=np.int64)


def sigmoid_interp(x):
    ax = np.abs(x)
    i = (ax >> 8) & 0x1F
    f = ax & 0xFF
    t0 = INTERP_TBL[i]
    t1 = INTERP_TBL[i + 1]
    y14 = t0 + (((t1 - t0) * f) >> 8)
    y = (y14 + 8) >> 4
    y = np.where(ax >= 8192, ONE, y)
    return np.where(x < 0, ONE - y, y)


METHODS = {
    "lut":    ("Full LUT 256 (baseline)",   sigmoid_lut),
    "hard":   ("Hard sigmoid",              sigmoid_hard),
    "plan":   ("PLAN shift-and-add",        sigmoid_plan),
    "interp": ("LUT 33 + interpolasi",      sigmoid_interp),
}


# ---------------------------------------------------------------- analisis
def true_sigmoid(x_int):
    return 1.0 / (1.0 + np.exp(-x_int / ONE))


def error_stats(y_int, x_int):
    err = np.abs(y_int / ONE - true_sigmoid(x_int))
    return err.max(), err.mean(), np.sqrt((err ** 2).mean())


def write_table():
    RESULTS.mkdir(exist_ok=True)
    rng = np.abs(X_INT) < 8 * ONE   # daerah kerja |x| < 8
    lines = ["| Metode | Error maks | MAE | RMSE | Error maks (|x|<8) | MAE (|x|<8) |",
             "|---|---|---|---|---|---|"]
    for key, (name, fn) in METHODS.items():
        y = fn(X_INT)
        mx, mae, rmse = error_stats(y, X_INT)
        mx8, mae8, _ = error_stats(y[rng], X_INT[rng])
        lines.append(f"| {name} | {mx:.5f} | {mae:.6f} | {rmse:.6f} | {mx8:.5f} | {mae8:.6f} |")
    text = "\n".join(lines)
    (RESULTS / "error_table.md").write_text(text + "\n", encoding="utf-8")
    print(text)


def plot():
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    sel = np.abs(X_INT) <= 8 * ONE
    x = X_INT[sel]
    xf = x / ONE
    fig, (a1, a2) = plt.subplots(2, 1, figsize=(9, 8), sharex=True)
    a1.plot(xf, true_sigmoid(x), "k", lw=2, label="sigmoid asli")
    for key, (name, fn) in METHODS.items():
        y = fn(x) / ONE
        a1.plot(xf, y, lw=1, label=name)
        a2.plot(xf, y - true_sigmoid(x), lw=1, label=name)
    a1.set_ylabel("y"); a1.legend(); a1.grid(alpha=.3)
    a1.set_title("Aproksimasi sigmoid (Q6.10)")
    a2.set_ylabel("error (aproksimasi - asli)"); a2.set_xlabel("x")
    a2.grid(alpha=.3); a2.legend()
    fig.tight_layout()
    fig.savefig(RESULTS / "sigmoid_curves.png", dpi=150)
    print(f"Grafik: {RESULTS / 'sigmoid_curves.png'}")


def check_sim():
    """Bandingkan output testbench (results/sim_<metode>.txt) dengan golden model."""
    ok = True
    for key, (name, fn) in METHODS.items():
        path = RESULTS / f"sim_{key}.txt"
        if not path.exists():
            print(f"[SKIP] {path.name} tidak ada (jalankan simulasi dulu)")
            ok = False
            continue
        sim = np.array([int(l, 16) for l in path.read_text().split()], dtype=np.int64)
        gold = fn(X_INT)
        mism = np.nonzero(sim != gold)[0]
        if len(sim) != len(gold):
            print(f"[FAIL] {name}: jumlah data {len(sim)} != {len(gold)}")
            ok = False
        elif len(mism):
            i = mism[0]
            print(f"[FAIL] {name}: {len(mism)} beda, contoh x={X_INT[i]} "
                  f"sim={sim[i]} gold={gold[i]}")
            ok = False
        else:
            print(f"[PASS] {name}: 65536/65536 bit-exact")
    return ok


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--check-sim", action="store_true")
    args = ap.parse_args()
    write_table()
    plot()
    if args.check_sim:
        raise SystemExit(0 if check_sim() else 1)
