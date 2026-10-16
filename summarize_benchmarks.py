#!/usr/bin/env python3
"""Print mean execution times and speedups from the benchmark CSV."""

import argparse
import csv
from collections import defaultdict
from pathlib import Path


WORKLOADS = ("1x", "2x", "4x")
THREADS = (1, 2, 3, 4)
EXPECTED_RUNS = 10


def load_means(csv_path: Path) -> dict[tuple[str, int], float]:
    samples: dict[tuple[str, int], list[float]] = defaultdict(list)

    with csv_path.open(newline="") as input_file:
        reader = csv.DictReader(input_file)
        expected_fields = {"workload", "spp", "threads", "run", "time_seconds"}
        if reader.fieldnames is None or set(reader.fieldnames) != expected_fields:
            raise ValueError(
                f"expected CSV columns {sorted(expected_fields)}, "
                f"found {reader.fieldnames}"
            )

        for row_number, row in enumerate(reader, start=2):
            try:
                workload = row["workload"]
                threads = int(row["threads"])
                float(row["spp"])
                int(row["run"])
                time_seconds = float(row["time_seconds"])
            except (TypeError, ValueError) as error:
                raise ValueError(f"invalid row {row_number}: {row}") from error

            if workload not in WORKLOADS or threads not in THREADS:
                raise ValueError(f"unexpected workload or thread count in row {row_number}")
            if time_seconds <= 0:
                raise ValueError(f"time_seconds must be positive in row {row_number}")

            samples[(workload, threads)].append(time_seconds)

    expected_keys = {(workload, threads) for workload in WORKLOADS for threads in THREADS}
    if set(samples) != expected_keys:
        raise ValueError("CSV does not contain every workload/thread combination")
    for key, values in samples.items():
        if len(values) != EXPECTED_RUNS:
            raise ValueError(
                f"{key[0]} with {key[1]} threads has {len(values)} runs; "
                f"expected {EXPECTED_RUNS}"
            )

    return {key: sum(values) / len(values) for key, values in samples.items()}


def print_table(title: str, values: dict[tuple[str, int], float]) -> None:
    print(title)
    print(f"{'Threads':>8}  {'1x':>12}  {'2x':>12}  {'4x':>12}")
    print("-" * 52)
    for threads in THREADS:
        cells = []
        for workload in WORKLOADS:
            value = values[(workload, threads)]
            cells.append(f"{value:12.4f}")
        print(f"{threads:>8}  {'  '.join(cells)}")
    print()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv_path", type=Path, help="benchmark results CSV")
    args = parser.parse_args()

    means = load_means(args.csv_path)
    speedups = {
        (workload, threads): means[(workload, 1)] / means[(workload, threads)]
        for workload in WORKLOADS
        for threads in THREADS
    }

    print_table("Average Execution Time (seconds)", means)
    print_table("Speedup", speedups)


if __name__ == "__main__":
    main()
