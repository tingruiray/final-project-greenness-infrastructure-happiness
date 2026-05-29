"""
enqueue_ndvi_tasks.py

Create one SQS message per province-level NDVI task.

Expected task CSV columns:
    province,manifest_file,output_folder

Example PowerShell:
    python .\enqueue_ndvi_tasks.py `
      --queue-url "https://sqs.us-east-1.amazonaws.com/891377197146/ndvi-province-tasks" `
      --tasks-csv "C:\path\to\province_tasks.csv" `
      --bucket final-project-ndvi `
      --sqs-region us-east-1 `
      --year 2018
"""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

import boto3


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--queue-url", required=True)
    parser.add_argument("--tasks-csv", required=True, type=Path)
    parser.add_argument("--bucket", default="final-project-ndvi")
    parser.add_argument("--manifest-prefix", default="manifests")
    parser.add_argument("--output-prefix", default="outputs")
    parser.add_argument("--script-key", default="scripts/compute_hls_ndvi_by_province_optimized.py")
    parser.add_argument("--boundary-key", default="boundaries/geoBoundaries-CHN-ADM1.geojson")
    parser.add_argument("--year", default=2018, type=int)
    parser.add_argument("--sqs-region", default="us-east-1")
    args = parser.parse_args()

    sqs = boto3.client("sqs", region_name=args.sqs_region)

    n = 0
    with args.tasks_csv.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        required = {"province", "manifest_file", "output_folder"}
        missing = required - set(reader.fieldnames or [])
        if missing:
            raise ValueError(f"tasks CSV is missing required columns: {sorted(missing)}")

        for row in reader:
            province = row["province"].strip()
            manifest_file = row["manifest_file"].strip()
            output_folder = row["output_folder"].strip()
            if not province or not manifest_file or not output_folder:
                print(f"Skipping incomplete row: {row}")
                continue

            task = {
                "province": province,
                "year": args.year,
                "manifest_s3": f"s3://{args.bucket}/{args.manifest_prefix}/{manifest_file}",
                "output_s3": f"s3://{args.bucket}/{args.output_prefix}/{output_folder}/",
                "boundary_s3": f"s3://{args.bucket}/{args.boundary_key}",
                "script_s3": f"s3://{args.bucket}/{args.script_key}",
            }
            sqs.send_message(QueueUrl=args.queue_url, MessageBody=json.dumps(task))
            print(f"Enqueued: {province} -> {manifest_file}")
            n += 1

    print(f"Done. Enqueued {n} tasks.")


if __name__ == "__main__":
    main()
