#!/usr/bin/env python3
"""Plot trend of ClickHouse-MATLAB driver perf runs.

Reads every CSV produced by test/run_perf.m under bench_results/ and renders a
two-panel chart (TestInsertPerf | TestQueryPerf) showing median_sec over time,
one line per (test_name, parameter) series. Log Y axis; shaded ±std band.

Usage:
    python3 test/plot_perf.py [bench_results_dir] [--output PATH]

Defaults:
    bench_results_dir = ./bench_results
    output            = <dir>/latest.png

Dependencies:
    pip install pandas matplotlib
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd


def load_runs(bench_dir: Path) -> pd.DataFrame:
    csvs = sorted(bench_dir.glob("*.csv"))
    if not csvs:
        sys.exit(f"no CSV files under {bench_dir}")
    df = pd.concat((pd.read_csv(p) for p in csvs), ignore_index=True)
    df["timestamp"] = pd.to_datetime(df["timestamp"], utc=True)

    # Some CSVs may have the full "Suite/Test(Param)" in test_name with an
    # empty parameter column. Split it back out so the plot can group cleanly.
    extracted = df["test_name"].astype(str).str.extract(
        r"^([^/]+)/([^(]+)\(([^)]*)\)$")
    matched = extracted[0].notna()
    df.loc[matched, "suite"]     = extracted.loc[matched, 0]
    df.loc[matched, "test_name"] = extracted.loc[matched, 1]
    df.loc[matched, "parameter"] = extracted.loc[matched, 2]
    df["parameter"] = df["parameter"].fillna("").astype(str)

    return df.sort_values(["suite", "test_name", "parameter", "timestamp"])


def param_rank(p: str) -> float:
    """Extract the row count encoded in a parameter label (e.g. 'rows_100k' -> 100000)."""
    digits = "".join(c for c in p if c.isdigit() or c == ".")
    mult = 1e3 if "k" in p.lower() else (1e6 if "m" in p.lower() else 1)
    return (float(digits) if digits else 0) * mult


def fmt_sec(s: float) -> str:
    if s < 1e-3:
        return f"{s * 1e6:.0f}µs"
    if s < 1:
        return f"{s * 1e3:.1f}ms"
    return f"{s:.2f}s"


def fmt_rps(r: float) -> str:
    if r >= 1e6:
        return f"{r / 1e6:.2f}M"
    if r >= 1e3:
        return f"{r / 1e3:.0f}k"
    return f"{r:.0f}"


def annotate(ax, xs, ys, fmt) -> None:
    for x, y in zip(xs, ys):
        ax.annotate(fmt(y), (x, y), xytext=(4, 4),
                    textcoords="offset points", fontsize=7)


def plot(df: pd.DataFrame, output: Path) -> None:
    # Derive throughput series: rows per second, with a band derived from std_sec.
    df = df.copy()
    df["rows"] = df["parameter"].map(param_rank)
    df["throughput_rps"]  = df["rows"] / df["median_sec"]
    df["throughput_low"]  = df["rows"] / (df["median_sec"] + df["std_sec"])
    df["throughput_high"] = df["rows"] / (df["median_sec"] - df["std_sec"]).clip(lower=1e-12)

    suites = sorted(df["suite"].unique())
    fig, axes = plt.subplots(2, len(suites), figsize=(6 * len(suites), 9),
                             sharex=True, squeeze=False)

    for col_idx, suite in enumerate(suites):
        ax_t = axes[0][col_idx]  # latency
        ax_r = axes[1][col_idx]  # throughput
        sub = df[df["suite"] == suite]
        params = sorted(sub["parameter"].unique(), key=param_rank)

        for param in params:
            g = sub[sub["parameter"] == param].sort_values("timestamp")
            label = f"{g['test_name'].iloc[0]} [{param}]"

            line, = ax_t.plot(g["timestamp"], g["median_sec"], marker="o",
                              label=label)
            color = line.get_color()
            ax_t.fill_between(g["timestamp"],
                              g["median_sec"] - g["std_sec"],
                              g["median_sec"] + g["std_sec"],
                              color=color, alpha=0.15)
            annotate(ax_t, g["timestamp"], g["median_sec"], fmt_sec)

            ax_r.plot(g["timestamp"], g["throughput_rps"], marker="o",
                      color=color, label=label)
            ax_r.fill_between(g["timestamp"],
                              g["throughput_low"], g["throughput_high"],
                              color=color, alpha=0.15)
            annotate(ax_r, g["timestamp"], g["throughput_rps"], fmt_rps)

        for ax in (ax_t, ax_r):
            ax.set_yscale("log")
            ax.grid(True, which="both", linestyle=":", alpha=0.5)
        ax_t.set_title(suite)
        ax_t.set_ylabel("median seconds (log)")
        ax_r.set_ylabel("rows / sec (log)")
        ax_r.set_xlabel("run timestamp (UTC)")
        ax_t.legend(fontsize=8, loc="best")

    fig.suptitle("clickhouse-matlab driver — perf trend")
    fig.autofmt_xdate()
    fig.tight_layout()
    fig.savefig(output, dpi=150)
    print(f"wrote {output}")


def plot_by_batch(df: pd.DataFrame, output: Path) -> None:
    """One panel per batch size; each panel overlays the suites (insert/query)."""
    df = df.copy()
    df["rows"] = df["parameter"].map(param_rank)
    df["throughput_rps"]  = df["rows"] / df["median_sec"]
    df["throughput_low"]  = df["rows"] / (df["median_sec"] + df["std_sec"])
    df["throughput_high"] = df["rows"] / (df["median_sec"] - df["std_sec"]).clip(lower=1e-12)

    # Normalize batch label across suites: "NumRows=rows_1k" and "Limit=rows_1k"
    # are the same batch size; keep only the value after '='.
    df["batch"] = df["parameter"].astype(str).str.split("=").str[-1]

    batches = sorted(df["batch"].unique(), key=param_rank)
    n = len(batches)
    fig, axes = plt.subplots(2, n, figsize=(5 * n, 9),
                             sharex=True, squeeze=False)

    for col_idx, batch in enumerate(batches):
        ax_t = axes[0][col_idx]
        ax_r = axes[1][col_idx]
        sub = df[df["batch"] == batch]

        for suite in sorted(sub["suite"].unique()):
            g = sub[sub["suite"] == suite].sort_values("timestamp")
            label = f"{suite} / {g['test_name'].iloc[0]}"

            line, = ax_t.plot(g["timestamp"], g["median_sec"], marker="o",
                              label=label)
            color = line.get_color()
            ax_t.fill_between(g["timestamp"],
                              g["median_sec"] - g["std_sec"],
                              g["median_sec"] + g["std_sec"],
                              color=color, alpha=0.15)
            annotate(ax_t, g["timestamp"], g["median_sec"], fmt_sec)

            ax_r.plot(g["timestamp"], g["throughput_rps"], marker="o",
                      color=color, label=label)
            ax_r.fill_between(g["timestamp"],
                              g["throughput_low"], g["throughput_high"],
                              color=color, alpha=0.15)
            annotate(ax_r, g["timestamp"], g["throughput_rps"], fmt_rps)

        for ax in (ax_t, ax_r):
            ax.grid(True, which="both", linestyle=":", alpha=0.5)
        ax_t.set_title(batch)
        ax_t.set_ylabel("median seconds")
        ax_r.set_ylabel("rows / sec")
        ax_r.set_xlabel("run timestamp (UTC)")
        ax_t.legend(fontsize=8, loc="best")

    fig.suptitle("clickhouse-matlab driver — per batch size")
    fig.autofmt_xdate()
    fig.tight_layout()
    fig.savefig(output, dpi=150)
    print(f"wrote {output}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("bench_dir", nargs="?", default="bench_results",
                    help="directory containing perf CSVs (default: ./bench_results)")
    ap.add_argument("--output", "-o", default=None,
                    help="output PNG path (default: <bench_dir>/latest.png)")
    args = ap.parse_args()

    bench_dir = Path(args.bench_dir).resolve()
    if not bench_dir.is_dir():
        sys.exit(f"not a directory: {bench_dir}")
    output = Path(args.output).resolve() if args.output else bench_dir / "latest.png"

    df = load_runs(bench_dir)
    plot(df, output)
    by_batch_output = output.with_name(output.stem + "_by_batch" + output.suffix)
    plot_by_batch(df, by_batch_output)


if __name__ == "__main__":
    main()
