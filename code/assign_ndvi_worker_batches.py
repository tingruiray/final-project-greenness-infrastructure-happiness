"""
Assign province NDVI S3 manifest files to parallel EC2 workers.

Purpose
-------
This script reads a folder of province-specific NDVI manifest files, counts the
number of S3 links in each file, and assigns provinces to workers using a greedy
load-balancing rule.

Load metric:
    number of NDVI .tif links in each manifest

Default behavior:
    - reads *_ndvi_s3.txt files
    - drops Shenzhen
    - corrects Shanxi/Shaanxi naming:
        sha-nxi_ndvi_s3.txt  -> Shanxi
        shanxi_ndvi_s3.txt   -> Shaanxi
    - writes worker_XX_tasks.csv, worker_XX_provinces.txt,
      worker_XX_manifest_files.txt, worker_XX_arrays.sh, and summary CSVs

Example:
    python assign_ndvi_worker_batches.py ^
      --manifest-dir "C:\\Users\\26540\\Desktop\\学习\\Uchicago\\final-project-greenness-infrastructure-happiness\\satellite_data\\ndvi_manifests" ^
      --out-dir "C:\\Users\\26540\\Desktop\\学习\\Uchicago\\final-project-greenness-infrastructure-happiness\\worker_batches" ^
      --n-workers 4
"""

from __future__ import annotations

import argparse
import csv
import re
from dataclasses import dataclass
from pathlib import Path


# Corrected province-name mapping from manifest filename stem to ADM1 boundary name.
# Important:
#   sha-nxi = 山西 = Shanxi
#   shanxi  = 陕西 = Shaanxi
PROVINCE_NAME_MAP = {
    "anhui": "Anhui",
    "beijing": "Beijing",
    "chongqing": "Chongqing",
    "fujian": "Fujian",
    "gansu": "Gansu",
    "guangdong": "Guangdong",
    "guangxi": "Guangxi",
    "guizhou": "Guizhou",
    "hainan": "Hainan",
    "hebei": "Hebei",
    "heilongjiang": "Heilongjiang",
    "henan": "Henan",
    "hubei": "Hubei",
    "hunan": "Hunan",
    "jiangsu": "Jiangsu",
    "jiangxi": "Jiangxi",
    "jilin": "Jilin",
    "liaoning": "Liaoning",
    "neimenggu": "Inner Mongolia",
    "ningxia": "Ningxia",
    "qinghai": "Qinghai",
    "sha-nxi": "Shanxi",
    "shanxi": "Shaanxi",
    "shandong": "Shandong",
    "shanghai": "Shanghai",
    "sichuan": "Sichuan",
    "tianjing": "Tianjin",   # keep this because your manifest filename uses tianjing
    "tianjin": "Tianjin",
    "xinjiang": "Xinjiang",
    "yunnan": "Yunnan",
    "zhejiang": "Zhejiang",
    "xizang": "Tibet",
    "tibet": "Tibet",
}


DEFAULT_DROP_KEYS = {"shenzhen"}


@dataclass(frozen=True)
class Task:
    province: str
    manifest_file: str
    manifest_path: Path
    ndvi_links: int
    key: str


def normalize_manifest_key(path: Path) -> str:
    """
    Convert a manifest filename to a normalized key.

    Examples:
        shanghai_ndvi_s3.txt -> shanghai
        sha-nxi_ndvi_s3.txt  -> sha-nxi
        6973200432-download_ndvi_s3.txt -> 6973200432-download
    """
    stem = path.stem

    for suffix in ["_ndvi_s3", "-ndvi-s3", "_NDVI_S3"]:
        if stem.endswith(suffix):
            stem = stem[: -len(suffix)]

    return stem.strip().lower()


def infer_province_name(key: str) -> str:
    """
    Infer ADM1 province name from normalized manifest key.

    Uses PROVINCE_NAME_MAP when possible. For unknown keys, falls back to a
    readable title-case version.
    """
    if key in PROVINCE_NAME_MAP:
        return PROVINCE_NAME_MAP[key]

    # Fallback: turn underscores/hyphens into spaces and title-case.
    return re.sub(r"[_-]+", " ", key).title()


def count_links(path: Path) -> int:
    """Count non-empty S3 links in a manifest file."""
    n = 0
    with path.open("r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            line = line.strip()
            if line:
                n += 1
    return n


def discover_tasks(manifest_dir: Path, pattern: str, drop_keys: set[str]) -> list[Task]:
    """Find manifest files and turn them into Task objects."""
    files = sorted(manifest_dir.glob(pattern))

    if not files:
        raise FileNotFoundError(f"No manifest files matching {pattern!r} found in {manifest_dir}")

    tasks: list[Task] = []

    for path in files:
        key = normalize_manifest_key(path)

        if key in drop_keys:
            print(f"Dropping {path.name} because key={key!r} is in drop list.")
            continue

        n_links = count_links(path)

        if n_links == 0:
            print(f"Skipping {path.name} because it contains 0 links.")
            continue

        province = infer_province_name(key)

        tasks.append(
            Task(
                province=province,
                manifest_file=path.name,
                manifest_path=path,
                ndvi_links=n_links,
                key=key,
            )
        )

    if not tasks:
        raise ValueError("No non-empty manifest tasks remain after dropping/skipping files.")

    return tasks


def assign_lpt(tasks: list[Task], n_workers: int) -> list[list[Task]]:
    """
    Assign tasks to workers using LPT greedy bin-packing.

    LPT = Longest Processing Time first:
        1. sort tasks from largest to smallest by NDVI link count
        2. assign each task to the currently lightest worker

    This is simple, deterministic, and works well when tasks are independent.
    """
    workers: list[list[Task]] = [[] for _ in range(n_workers)]
    loads = [0 for _ in range(n_workers)]

    # Sort by descending workload, then province name for deterministic output.
    sorted_tasks = sorted(tasks, key=lambda t: (-t.ndvi_links, t.province))

    for task in sorted_tasks:
        # Choose the worker with the smallest current load.
        # Tie-breaker: fewer current tasks, then worker index.
        best_worker = min(
            range(n_workers),
            key=lambda i: (loads[i], len(workers[i]), i),
        )

        workers[best_worker].append(task)
        loads[best_worker] += task.ndvi_links

    return workers


def write_worker_outputs(workers: list[list[Task]], out_dir: Path) -> None:
    """Write per-worker task files and summary files."""
    out_dir.mkdir(parents=True, exist_ok=True)

    summary_rows = []
    batch_rows = []

    for i, tasks in enumerate(workers, start=1):
        worker_id = f"worker_{i:02d}"
        total_links = sum(t.ndvi_links for t in tasks)

        # Sort within each worker by descending links so the largest province runs first.
        tasks = sorted(tasks, key=lambda t: (-t.ndvi_links, t.province))

        # worker_XX_tasks.csv
        task_csv = out_dir / f"{worker_id}_tasks.csv"
        with task_csv.open("w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(
                f,
                fieldnames=["worker", "province", "manifest_file", "ndvi_links", "key"],
            )
            writer.writeheader()
            for t in tasks:
                writer.writerow(
                    {
                        "worker": worker_id,
                        "province": t.province,
                        "manifest_file": t.manifest_file,
                        "ndvi_links": t.ndvi_links,
                        "key": t.key,
                    }
                )

        # worker_XX_provinces.txt
        provinces_txt = out_dir / f"{worker_id}_provinces.txt"
        provinces_txt.write_text(
            "\n".join(t.province for t in tasks) + "\n",
            encoding="utf-8",
            newline="\n",
        )

        # worker_XX_manifest_files.txt
        manifests_txt = out_dir / f"{worker_id}_manifest_files.txt"
        manifests_txt.write_text(
            "\n".join(t.manifest_file for t in tasks) + "\n",
            encoding="utf-8",
            newline="\n",
        )

        # worker_XX_arrays.sh
        arrays_sh = out_dir / f"{worker_id}_arrays.sh"
        lines = [
            "#!/usr/bin/env bash",
            "# Auto-generated worker assignment.",
            "# Use matching indices: PROVINCES[i] corresponds to MANIFESTS[i].",
            "",
            "PROVINCES=(",
        ]
        for t in tasks:
            lines.append(f'  "{t.province}"')
        lines.extend([
            ")",
            "",
            "MANIFESTS=(",
        ])
        for t in tasks:
            lines.append(f'  "{t.manifest_file}"')
        lines.extend([
            ")",
            "",
        ])
        arrays_sh.write_text("\n".join(lines), encoding="utf-8", newline="\n")

        summary_rows.append(
            {
                "worker": worker_id,
                "n_tasks": len(tasks),
                "ndvi_links": total_links,
                "provinces": "; ".join(t.province for t in tasks),
            }
        )

        for t in tasks:
            batch_rows.append(
                {
                    "worker": worker_id,
                    "province": t.province,
                    "manifest_file": t.manifest_file,
                    "ndvi_links": t.ndvi_links,
                    "key": t.key,
                }
            )

    # worker_load_summary.csv
    with (out_dir / "worker_load_summary.csv").open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=["worker", "n_tasks", "ndvi_links", "provinces"],
        )
        writer.writeheader()
        writer.writerows(summary_rows)

    # worker_batches_summary.csv
    with (out_dir / "worker_batches_summary.csv").open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=["worker", "province", "manifest_file", "ndvi_links", "key"],
        )
        writer.writeheader()
        writer.writerows(batch_rows)

    # README
    loads = [row["ndvi_links"] for row in summary_rows]
    readme = [
        "# NDVI Worker Batches",
        "",
        "These worker batches were generated by `assign_ndvi_worker_batches.py`.",
        "",
        "## Rule",
        "",
        "Tasks are assigned using LPT greedy load balancing:",
        "",
        "1. Count the number of NDVI links in each province manifest.",
        "2. Sort tasks from largest to smallest.",
        "3. Assign each task to the currently lightest worker.",
        "",
        "## Important naming correction",
        "",
        "- `sha-nxi_ndvi_s3.txt` corresponds to **Shanxi**.",
        "- `shanxi_ndvi_s3.txt` corresponds to **Shaanxi**.",
        "- `shenzhen_ndvi_s3.txt` is dropped by default.",
        "",
        "## Load summary",
        "",
        "| Worker | Tasks | NDVI links | Provinces |",
        "|---:|---:|---:|---|",
    ]

    for row in summary_rows:
        readme.append(
            f"| {row['worker']} | {row['n_tasks']} | {row['ndvi_links']} | {row['provinces']} |"
        )

    readme.extend([
        "",
        f"Max-min NDVI-link difference: {max(loads) - min(loads)}",
        "",
    ])

    (out_dir / "README_worker_batches.md").write_text(
        "\n".join(readme) + "\n",
        encoding="utf-8",
        newline="\n",
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--manifest-dir",
        required=True,
        type=Path,
        help="Folder containing *_ndvi_s3.txt files.",
    )
    parser.add_argument(
        "--out-dir",
        required=True,
        type=Path,
        help="Folder where worker assignment files will be written.",
    )
    parser.add_argument(
        "--n-workers",
        default=4,
        type=int,
        help="Number of parallel workers. Default: 4.",
    )
    parser.add_argument(
        "--pattern",
        default="*_ndvi_s3.txt",
        help="Glob pattern for manifest files. Default: *_ndvi_s3.txt.",
    )
    parser.add_argument(
        "--drop",
        default="shenzhen",
        help=(
            "Comma-separated normalized manifest keys to drop. "
            "Default: shenzhen. Use empty string to drop none."
        ),
    )

    args = parser.parse_args()

    if args.n_workers < 1:
        raise ValueError("--n-workers must be at least 1.")

    drop_keys = {
        x.strip().lower()
        for x in args.drop.split(",")
        if x.strip()
    }

    tasks = discover_tasks(
        manifest_dir=args.manifest_dir,
        pattern=args.pattern,
        drop_keys=drop_keys,
    )

    workers = assign_lpt(tasks, args.n_workers)
    write_worker_outputs(workers, args.out_dir)

    print(f"Discovered tasks: {len(tasks)}")
    print(f"Workers:          {args.n_workers}")
    print(f"Output directory: {args.out_dir}")
    print()

    for i, worker_tasks in enumerate(workers, start=1):
        total_links = sum(t.ndvi_links for t in worker_tasks)
        provinces = ", ".join(t.province for t in sorted(worker_tasks, key=lambda t: (-t.ndvi_links, t.province)))
        print(f"worker_{i:02d}: {len(worker_tasks)} tasks, {total_links} NDVI links")
        print(f"  {provinces}")

    loads = [sum(t.ndvi_links for t in w) for w in workers]
    print()
    print(f"Max load: {max(loads)}")
    print(f"Min load: {min(loads)}")
    print(f"Max-min difference: {max(loads) - min(loads)}")


if __name__ == "__main__":
    main()
