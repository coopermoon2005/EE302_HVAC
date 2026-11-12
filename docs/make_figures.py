"""Build the print figures and LaTeX tables for the report and slides from the logged data.

Usage (from the repository root):
    python docs/make_figures.py

Reads  matlab/results/*.csv|*.mat  (newest file per controller+scenario)
Writes docs/figures/*.pdf|*.png and docs/tables/*.tex
"""
import glob
import os
import re

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import scipy.io as sio

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.environ.get("HVAC_RESULTS", os.path.join(ROOT, "matlab", "results"))
OUT = os.environ.get("HVAC_FIGURES", os.path.join(ROOT, "docs", "figures"))
os.makedirs(OUT, exist_ok=True)
TAB = os.environ.get("HVAC_TABLES", os.path.join(ROOT, "docs", "tables"))
os.makedirs(TAB, exist_ok=True)

R_TH = 1.3          # detector threshold [degC], same as hvac_params.m
BLUE, RED, GREY, ORANGE, GREEN = "#1f4e9c", "#c0392b", "#7f8c8d", "#e67e22", "#1e8449"

plt.rcParams.update({
    "font.family": "serif", "font.size": 8, "axes.labelsize": 8, "axes.titlesize": 8.5,
    "legend.fontsize": 7, "xtick.labelsize": 7, "ytick.labelsize": 7,
    "axes.grid": True, "grid.alpha": 0.3, "lines.linewidth": 0.9,
    "savefig.bbox": "tight", "savefig.dpi": 300,
})


def newest(pattern):
    files = sorted(glob.glob(os.path.join(RES, pattern)), key=os.path.getmtime)
    if not files:
        raise FileNotFoundError(pattern)
    return files[-1]


def hw(ctrl, scen):
    """Newest hardware run as a dict of arrays (+ events)."""
    d = sio.loadmat(newest(f"hw_{ctrl}_{scen}_*.mat"), squeeze_me=True)
    ev = np.atleast_2d(d["ev"]) if np.size(d["ev"]) else np.zeros((0, 3))
    first = lambda lab: next((t for t, l in zip(d["t"], d["label"]) if l == lab), None)
    det_t = next((t for t, f in zip(d["t"], d["flag"]) if f), None)
    return dict(t=d["t"], ref=d["ref"], Tm=d["Tm"], Tc=d["Tc"], u=d["u"], That=d["That"],
                rf=d["rf"], flag=d["flag"].astype(bool), label=d["label"], ev=ev,
                det_t=det_t, first=first)


def sim(name):
    d = sio.loadmat(os.path.join(RES, f"sim_{name}.mat"), squeeze_me=True)
    return {k: d[k] for k in ("t", "ref", "Tm", "u", "That", "rf", "flag")}


def save(fig, name):
    for ext in ("pdf", "png"):
        fig.savefig(os.path.join(OUT, f"{name}.{ext}"))
    plt.close(fig)
    print("wrote", name)


def shade(ax, ev, kind, color):
    """Shade intervals where event type `kind` (1 = disturbance, 2 = fault plate) is on."""
    on = None
    for t, typ, state in ev:
        if int(typ) != kind:
            continue
        if state and on is None:
            on = t
        elif not state and on is not None:
            ax.axvspan(on, t, color=color, alpha=0.12, lw=0); on = None
    if on is not None:
        ax.axvspan(on, ax.get_xlim()[1] if ax.get_xlim()[1] > on else 1200, color=color, alpha=0.12, lw=0)


# ---------------------------------------------------------------- 1. identification
def fig_identification():
    d = sio.loadmat(newest("step_*.mat"), squeeze_me=True)
    t, u, Tc, Ta = d["t"], d["u"], d["Tc"], d["Ta"]
    Ts = float(d["Ts"]); T_pre = float(d["T_PRE"])
    Ta0 = Ta[t < T_pre].mean(); y = Tc - Ta0; y = y - y[t < T_pre].mean()

    def fo(K, tau, L):
        n = len(u); yh = np.zeros(n); dl = max(int(round(L / Ts)), 1)
        for k in range(n - 1):
            yh[k + 1] = yh[k] + Ts / tau * (K * u[max(k - dl, 0)] - yh[k])
        return yh

    fig, (a1, a2) = plt.subplots(2, 1, figsize=(3.4, 2.6), sharex=True,
                                 gridspec_kw=dict(height_ratios=[2.2, 1]))
    a1.plot(t, y, color=BLUE, label="measured")
    a1.plot(t, fo(1.709, 33.7, 0.5), "--", color=RED, label=r"fit: $K$=1.71, $\tau$=33.7 s")
    a1.plot(t, fo(1.41, 19.6, 0.5), ":", color=GREEN, lw=1.2, label=r"closed-loop refit: $K$=1.41, $\tau$=19.6 s")
    a1.set_ylabel(r"$T-T_a$ [$^\circ$C]"); a1.legend(loc="lower center", bbox_to_anchor=(0.5, 0.02))
    a2.plot(t, u, color=GREY); a2.set_ylabel("$u$ [V]"); a2.set_xlabel("time [s]"); a2.set_ylim(-0.2, 3.5)
    save(fig, "identification")


# ---------------------------------------------------------------- 2. tracking
def fig_tracking():
    fig, ax = plt.subplots(2, 2, figsize=(7.0, 3.0), sharex=True,
                           gridspec_kw=dict(height_ratios=[2, 1]))
    for j, (c, title) in enumerate([("onoff", "ON-OFF (hysteresis 0.6 $^\\circ$C)"), ("pi", "PI (SIMC tuning)")]):
        d = hw(c, "track"); s = sim(f"{c}_track")
        off = d["ref"][0] - s["ref"][0]           # sim uses Ta = 24 C; shift to the run's ambient
        ax[0, j].step(d["t"], d["ref"], where="post", color="k", ls="--", lw=0.8, label="setpoint")
        ax[0, j].plot(s["t"], s["Tm"] + off, color=ORANGE, lw=0.8, alpha=0.9, label="simulation")
        ax[0, j].plot(d["t"], d["Tm"], color=BLUE, label="hardware")
        ax[0, j].set_title(title)
        ax[1, j].plot(d["t"], d["u"], color=RED, lw=0.5)
        ax[1, j].set_xlabel("time [s]"); ax[1, j].set_ylim(-0.2, 5.3)
    ax[0, 0].set_ylabel(r"$T$ [$^\circ$C]"); ax[1, 0].set_ylabel("$u$ [V]")
    ax[0, 0].legend(loc="lower right", ncol=1)
    save(fig, "tracking")


# ---------------------------------------------------------------- 3. disturbance rejection
def fig_disturbance():
    fig, ax = plt.subplots(2, 2, figsize=(7.0, 3.0), sharex=True,
                           gridspec_kw=dict(height_ratios=[2, 1]))
    for j, (c, title) in enumerate([("onoff", "ON-OFF"), ("pi", "PI")]):
        d = hw(c, "dist")
        for a in ax[:, j]:
            a.set_xlim(0, 1200); shade(a, d["ev"], 1, ORANGE)
        ax[0, j].plot(d["t"], d["ref"], "k--", lw=0.8, label="setpoint")
        ax[0, j].plot(d["t"], d["Tm"], color=BLUE, label="measured")
        ax[0, j].set_ylim(d["ref"][-1] - 1.5, d["ref"][-1] + 1.0)
        ax[0, j].set_title(f"{title}: 50 % airflow plate in shaded interval")
        ax[1, j].plot(d["t"], d["u"], color=RED, lw=0.5)
        ax[1, j].set_xlabel("time [s]"); ax[1, j].set_ylim(-0.2, 5.3)
    ax[0, 0].set_ylabel(r"$T$ [$^\circ$C]"); ax[1, 0].set_ylabel("$u$ [V]")
    ax[0, 0].legend(loc="lower right")
    save(fig, "disturbance")


# ---------------------------------------------------------------- 4. fault residuals
def fig_faults():
    runs = [("normal", "fault-free", None), ("restrict", "airflow restricted (50 % plate)", 2),
            ("fanfail", "fan blocked (0 % plate)", 2), ("bias", "sensor bias +2 $^\\circ$C", 3)]
    fig, ax = plt.subplots(2, 2, figsize=(7.0, 3.4), sharex=True, sharey=True)
    for a, (scen, title, kind) in zip(ax.flat, runs):
        d = hw("pi", scen); s = sim(f"pi_{scen}")
        a.set_xlim(0, 1200)
        if kind is not None:
            t_f = next((t for t, typ, st in d["ev"] if int(typ) == kind and st), None)
            if t_f is not None:
                a.axvline(t_f, color="k", lw=0.7, ls=":")
        a.axhspan(-R_TH, R_TH, color=GREEN, alpha=0.07, lw=0)
        a.axhline(R_TH, color=RED, ls="--", lw=0.7); a.axhline(-R_TH, color=RED, ls="--", lw=0.7)
        a.plot(s["t"], s["rf"], color=ORANGE, lw=0.8, label="simulation")
        a.plot(d["t"], d["rf"], color=BLUE, label="hardware")
        if d["det_t"] is not None:
            a.plot(d["det_t"], d["rf"][d["t"] == d["det_t"]][0], "v", color=RED, ms=5, label="alarm raised")
        a.set_title(title)
    for a in ax[1]:
        a.set_xlabel("time [s]")
    for a in ax[:, 0]:
        a.set_ylabel(r"filtered residual $r_f$ [$^\circ$C]")
    ax[0, 0].plot([], [], "v", color=RED, ms=5, label="alarm raised")
    ax[0, 0].legend(loc="upper left", ncol=3)
    ax[0, 0].set_ylim(-1.0, 4.2)
    save(fig, "faults")


# ---------------------------------------------------------------- 5. detector reference fix
def fig_rest_fix():
    """Run 'pi_normal' logged with the ambient-referenced detector vs the chamber-referenced one."""
    old = os.path.join(RES, "archive", "hw_pi_normal_20261111_2315.mat")
    if not os.path.exists(old):
        print("skip rest_fix (no archived run)"); return
    o = sio.loadmat(old, squeeze_me=True); n = hw("pi", "normal")
    fig, a = plt.subplots(figsize=(3.4, 1.9))
    a.axhline(R_TH, color=RED, ls="--", lw=0.7)
    a.plot(o["t"], o["rf"], color=GREY, label="model rests at ambient sensor")
    a.plot(n["t"], n["rf"], color=BLUE, label="model rests at chamber start value")
    a.set_xlabel("time [s]"); a.set_ylabel(r"$r_f$ [$^\circ$C]"); a.set_xlim(0, 1200); a.set_ylim(-0.3, 3.0)
    a.legend(loc="upper center", ncol=1)
    save(fig, "rest_fix")


# ---------------------------------------------------------------- tables
def _fmt(x, nd=1):
    if x is None or not np.isfinite(x):
        return "--"
    s = f"{x:.{nd}f}"
    return s[1:] if s.startswith("-") and float(s) == 0 else s


def table_tracking():
    """Rise/settle/overshoot/ess/ripple per step, hardware (simulation) from analyze_results."""
    import csv
    rows = list(csv.DictReader(open(os.path.join(RES, "hw_metrics.csv"), encoding="utf-8")))
    get = lambda r, k: float(r[k]) if r[k] not in ("", "NaN") else float("nan")
    lines = [r"\begin{tabular}{@{}llccccc@{}}", r"\toprule",
             r" & Step [$^\circ$C] & Rise [s] & Settle [s] & OS [\%] & $e_{ss}$ [$^\circ$C] & Ripple [$^\circ$C] \\",
             r"\midrule"]
    for run, name in (("onoff_track", "ON-OFF"), ("pi_track", "PI")):
        hw_rows = [r for r in rows if r["run"] == run and r["source"] == "hw"]
        sim_rows = {r["step"]: r for r in rows if r["run"] == run and r["source"] == "sim"}
        for i, h in enumerate(hw_rows):
            sm = sim_rows[h["step"]]
            cell = lambda k, nd: f"{_fmt(get(h, k), nd)} ({_fmt(get(sm, k), nd)})"
            step = h["step"].replace("->", r"$\to$").replace("+", "")
            lines.append((name if i == 0 else "") + f" & {step} & {cell('rise_s',1)} & {cell('settle_s',1)} & "
                         f"{cell('overshoot_pct',1)} & {cell('ess_degC',2)} & {cell('ripple_degC',2)} \\\\")
        if run == "onoff_track":
            lines.append(r"\midrule")
    lines += [r"\bottomrule", r"\end{tabular}"]
    open(os.path.join(TAB, "tracking.tex"), "w", encoding="utf-8").write("\n".join(lines) + "\n")
    print("wrote table tracking")


def table_energy():
    """Heater use and true temperature error after the fault (t >= 450 s), PI constant-setpoint runs."""
    lines = [r"\begin{tabular}{@{}lcccc@{}}", r"\toprule",
             r"PI run & $\bar u$ [V] & Duty [\%] & $|e|$ meas./true [$^\circ$C] & $E^\dagger$ [J] \\",
             r"\midrule"]
    for scen, name in (("normal", "fault-free"), ("restrict", r"restricted 50\,\%"),
                       ("fanfail", "fan blocked"), ("bias", "sensor bias")):
        d = sio.loadmat(newest(f"hw_pi_{scen}_*.mat"), squeeze_me=True)
        w = d["t"] >= 450
        e_meas = np.mean(np.abs(d["ref"][w] - d["Tm"][w])); e_true = np.mean(np.abs(d["ref"][w] - d["Tc"][w]))
        u = np.mean(d["u"][w]); E = float(d["E_J"])
        lines.append(f"{name} & {u:.2f} & {u/5*100:.0f} & {e_meas:.2f} / {e_true:.2f} & {E:.0f} \\\\")
    lines += [r"\bottomrule", r"\multicolumn{5}{@{}l}{\footnotesize $^\dagger$whole run; provisional current/voltage scaling}",
              r"\end{tabular}"]
    open(os.path.join(TAB, "energy.tex"), "w", encoding="utf-8").write("\n".join(lines) + "\n")
    print("wrote table energy")


if __name__ == "__main__":
    fig_identification(); fig_tracking(); fig_disturbance(); fig_faults(); fig_rest_fix()
    table_tracking(); table_energy()
