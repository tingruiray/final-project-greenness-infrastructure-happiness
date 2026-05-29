"""
worker_poll_sqs_ndvi_old.py

SQS worker for the province-level HLS-VI NDVI pipeline.
Uses the older processing script:
    s3://final-project-ndvi/scripts/compute_hls_ndvi_by_province_optimized.py

Worker logic:
    1. Poll SQS for one province task.
    2. Download script, boundary, and manifest from project S3.
    3. Clean Windows CRLF from manifest.
    4. Download NASA HLS-VI NDVI .tif files using the nasa AWS profile.
    5. Run compute_hls_ndvi_by_province_optimized.py.
    6. Upload outputs to project S3.
    7. Delete the SQS message only after successful completion.
    8. Clean local files.
"""

from __future__ import annotations

import argparse
import json
import shlex
import shutil
import subprocess
import time
from pathlib import Path

import boto3


def run(cmd: list[str], check: bool = True) -> subprocess.CompletedProcess:
    print("+", " ".join(shlex.quote(x) for x in cmd), flush=True)
    return subprocess.run(cmd, check=check)


def s3_cp(src: str, dst: str, profile: str | None = None, region: str | None = None) -> None:
    cmd = ["aws", "s3", "cp", src, dst, "--no-progress"]
    if region:
        cmd.extend(["--region", region])
    if profile:
        cmd.extend(["--profile", profile])
    run(cmd)


def s3_cp_recursive(src: str, dst: str, region: str | None = None) -> None:
    cmd = ["aws", "s3", "cp", src, dst, "--recursive"]
    if region:
        cmd.extend(["--region", region])
    run(cmd)


def safe_name(province: str) -> str:
    return province.lower().replace(" ", "_").replace("/", "_").replace("-", "_")


def clean_manifest(in_path: Path, out_path: Path) -> None:
    text = in_path.read_text(encoding="utf-8", errors="ignore")
    text = text.replace("\r", "")
    out_path.write_text(text, encoding="utf-8")


def download_ndvi_files(manifest_path: Path, raw_dir: Path, nasa_profile: str) -> int:
    raw_dir.mkdir(parents=True, exist_ok=True)
    n = 0
    with manifest_path.open("r", encoding="utf-8") as f:
        for line in f:
            uri = line.strip()
            if not uri:
                continue
            run([
                "aws", "s3", "cp", uri, str(raw_dir) + "/",
                "--profile", nasa_profile,
                "--region", "us-west-2",
                "--no-progress",
            ])
            n += 1
    return n


def process_task(task: dict, nasa_profile: str, work_root: Path, default_script_s3: str) -> None:
    province = task["province"]
    year = int(task.get("year", 2018))
    province_safe = safe_name(province)

    task_dir = work_root / province_safe
    raw_dir = task_dir / "raw"
    out_dir = task_dir / "outputs"
    task_dir.mkdir(parents=True, exist_ok=True)
    raw_dir.mkdir(parents=True, exist_ok=True)
    out_dir.mkdir(parents=True, exist_ok=True)

    script_path = task_dir / "compute_hls_ndvi_by_province.py"
    boundary_path = task_dir / "geoBoundaries-CHN-ADM1.geojson"
    manifest_path = task_dir / "manifest.txt"
    manifest_clean_path = task_dir / "manifest_clean.txt"

    script_s3 = task.get("script_s3") or default_script_s3

    # Project S3 uses the EC2 instance role.
    s3_cp(script_s3, str(script_path))
    s3_cp(task["boundary_s3"], str(boundary_path))
    s3_cp(task["manifest_s3"], str(manifest_path))

    clean_manifest(manifest_path, manifest_clean_path)

    # NASA protected S3 uses temporary NASA credentials/profile.
    n_downloaded = download_ndvi_files(manifest_clean_path, raw_dir, nasa_profile)
    print(f"Downloaded {n_downloaded} NDVI files for {province}", flush=True)

    run([
        "python3",
        str(script_path),
        "--hls-dir", str(raw_dir),
        "--boundary-file", str(boundary_path),
        "--province", province,
        "--year", str(year),
        "--out-dir", str(out_dir),
    ])

    # Upload outputs using the EC2 instance role.
    s3_cp_recursive(str(out_dir) + "/", task["output_s3"])

    # Free EBS space.
    shutil.rmtree(task_dir, ignore_errors=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--queue-url", required=True)
    parser.add_argument("--sqs-region", default="us-east-1")
    parser.add_argument("--nasa-profile", default="nasa")
    parser.add_argument("--work-root", default="~/ndvi_sqs_work")
    parser.add_argument("--wait-time", default=20, type=int)
    parser.add_argument("--visibility-timeout", default=21600, type=int)
    parser.add_argument("--max-empty-polls", default=5, type=int)
    parser.add_argument("--max-tasks", default=None, type=int)
    parser.add_argument("--script-s3", default="s3://final-project-ndvi/scripts/compute_hls_ndvi_by_province_optimized.py")
    args = parser.parse_args()

    work_root = Path(args.work_root).expanduser()
    work_root.mkdir(parents=True, exist_ok=True)
    sqs = boto3.client("sqs", region_name=args.sqs_region)

    empty_polls = 0
    completed_tasks = 0

    while True:
        if args.max_tasks is not None and completed_tasks >= args.max_tasks:
            print(f"Reached --max-tasks={args.max_tasks}. Worker exiting.", flush=True)
            break

        print("Polling SQS...", flush=True)
        response = sqs.receive_message(
            QueueUrl=args.queue_url,
            MaxNumberOfMessages=1,
            WaitTimeSeconds=args.wait_time,
            VisibilityTimeout=args.visibility_timeout,
        )
        messages = response.get("Messages", [])

        if not messages:
            empty_polls += 1
            print(f"No messages. Empty polls: {empty_polls}", flush=True)
            if empty_polls >= args.max_empty_polls:
                print("No more tasks found. Worker exiting.", flush=True)
                break
            continue

        empty_polls = 0
        message = messages[0]
        receipt_handle = message["ReceiptHandle"]
        task = json.loads(message["Body"])
        province = task.get("province", "UNKNOWN")
        print(f"Received task: {province}", flush=True)

        try:
            process_task(task, args.nasa_profile, work_root, args.script_s3)
            sqs.delete_message(QueueUrl=args.queue_url, ReceiptHandle=receipt_handle)
            completed_tasks += 1
            print(f"SUCCESS: {province}. Deleted SQS message.", flush=True)
        except Exception as e:
            print(f"FAILED: {province}: {e}", flush=True)
            print("Leaving message in queue; it will become visible again.", flush=True)
            try:
                sqs.change_message_visibility(
                    QueueUrl=args.queue_url,
                    ReceiptHandle=receipt_handle,
                    VisibilityTimeout=60,
                )
            except Exception as visibility_error:
                print(f"WARNING: could not reset visibility timeout: {visibility_error}", flush=True)
            time.sleep(5)


if __name__ == "__main__":
    main()
