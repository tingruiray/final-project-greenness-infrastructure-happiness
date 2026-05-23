#!/usr/bin/env python3
"""
launch_ndvi_workers.py

Automate launching EC2 workers for the NDVI SQS pipeline.

This is the NDVI equivalent of the Assignment 2 launch_scrapers.py pattern:
instead of manually clicking in the EC2 console, this script launches N EC2
instances, attaches the AWS Academy instance profile, creates enough EBS storage,
installs the Python/raster environment through UserData, creates EBS-backed swap,
downloads the SQS worker script from S3, and optionally starts the worker in tmux.

Default design:
    SQS queue: us-east-1
    EC2 workers: us-west-2
    NASA HLS S3: us-west-2

Recommended usage, launch-only:
    python launch_ndvi_workers.py ^
      --num-workers 2 ^
      --instance-type m5.large ^
      --volume-size-gb 200 ^
      --swap-gb 32 ^
      --project-bucket final-project-ndvi ^
      --queue-url https://sqs.us-east-1.amazonaws.com/891377197146/ndvi-province-tasks

Then connect to each EC2 instance, configure fresh NASA credentials, and run:
    ~/project/start_worker.sh

Optional fully automatic start:
    Set NASA_ACCESS_KEY_ID, NASA_SECRET_ACCESS_KEY, and NASA_SESSION_TOKEN
    in your local shell, then add --auto-start.

PowerShell example:
    $env:NASA_ACCESS_KEY_ID="..."
    $env:NASA_SECRET_ACCESS_KEY="..."
    $env:NASA_SESSION_TOKEN="..."

    python launch_ndvi_workers.py `
      --num-workers 3 `
      --instance-type m5.large `
      --volume-size-gb 200 `
      --swap-gb 32 `
      --project-bucket final-project-ndvi `
      --queue-url "https://sqs.us-east-1.amazonaws.com/891377197146/ndvi-province-tasks" `
      --auto-start

Security note:
    --auto-start embeds the temporary NASA credentials into EC2 UserData and
    writes them into the EC2 user's AWS profile. This is convenient for an
    AWS Academy project, but UserData can be viewed by users with EC2
    permissions. The NASA credentials expire quickly, so this is usually low
    risk for this coursework setup, but launch-only mode is cleaner.
"""

from __future__ import annotations

import argparse
import base64
import csv
import os
import sys
import time
from pathlib import Path

import boto3
from botocore.exceptions import ClientError


def shell_quote_single(s: str) -> str:
    """Safe single-quote string for bash."""
    return "'" + s.replace("'", "'\"'\"'") + "'"


def get_default_vpc_and_subnet(ec2):
    """Use the default VPC and choose one subnet from it."""
    vpcs = ec2.describe_vpcs(
        Filters=[{"Name": "is-default", "Values": ["true"]}]
    )["Vpcs"]

    if not vpcs:
        raise RuntimeError("No default VPC found in this region.")

    vpc_id = vpcs[0]["VpcId"]

    subnets = ec2.describe_subnets(
        Filters=[
            {"Name": "vpc-id", "Values": [vpc_id]},
            {"Name": "default-for-az", "Values": ["true"]},
        ]
    )["Subnets"]

    if not subnets:
        subnets = ec2.describe_subnets(
            Filters=[{"Name": "vpc-id", "Values": [vpc_id]}]
        )["Subnets"]

    if not subnets:
        raise RuntimeError(f"No subnets found for default VPC {vpc_id}.")

    # Pick the subnet with the most available IPs.
    subnets = sorted(subnets, key=lambda x: x.get("AvailableIpAddressCount", 0), reverse=True)
    subnet_id = subnets[0]["SubnetId"]

    return vpc_id, subnet_id


def get_or_create_security_group(ec2, vpc_id: str, group_name: str, ssh_cidr: str) -> str:
    """Create/reuse a security group allowing SSH so EC2 Instance Connect works."""
    existing = ec2.describe_security_groups(
        Filters=[
            {"Name": "group-name", "Values": [group_name]},
            {"Name": "vpc-id", "Values": [vpc_id]},
        ]
    )["SecurityGroups"]

    if existing:
        sg_id = existing[0]["GroupId"]
        print(f"Security group already exists: {group_name} ({sg_id})")
    else:
        response = ec2.create_security_group(
            GroupName=group_name,
            Description="Security group for NDVI SQS EC2 workers",
            VpcId=vpc_id,
        )
        sg_id = response["GroupId"]
        print(f"Created security group: {group_name} ({sg_id})")

    try:
        ec2.authorize_security_group_ingress(
            GroupId=sg_id,
            IpPermissions=[
                {
                    "IpProtocol": "tcp",
                    "FromPort": 22,
                    "ToPort": 22,
                    "IpRanges": [
                        {
                            "CidrIp": ssh_cidr,
                            "Description": "SSH / EC2 Instance Connect access",
                        }
                    ],
                }
            ],
        )
        print(f"Added SSH rule: tcp/22 from {ssh_cidr}")

    except ClientError as e:
        code = e.response["Error"]["Code"]
        if code == "InvalidPermission.Duplicate":
            print("SSH rule already exists.")
        else:
            raise

    return sg_id


def get_amazon_linux_2023_ami(ssm) -> str:
    """Fetch latest Amazon Linux 2023 x86_64 AMI ID from SSM public parameter."""
    param_name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
    value = ssm.get_parameter(Name=param_name)["Parameter"]["Value"]
    return value


def build_user_data(args, nasa_access_key: str | None, nasa_secret_key: str | None, nasa_session_token: str | None) -> str:
    """Build EC2 UserData bootstrap script."""
    queue_url_q = shell_quote_single(args.queue_url)
    sqs_region_q = shell_quote_single(args.sqs_region)
    project_bucket_q = shell_quote_single(args.project_bucket)
    worker_script_s3_q = shell_quote_single(f"s3://{args.project_bucket}/{args.worker_script_key}")
    script_s3_q = shell_quote_single(f"s3://{args.project_bucket}/{args.processing_script_key}")
    cloud_script_s3_q = shell_quote_single(f"s3://{args.project_bucket}/{args.cloud_processing_script_key}")
    swap_gb = int(args.swap_gb)
    auto_start = "true" if args.auto_start else "false"

    # Optional NASA credentials. Only inserted if --auto-start is requested.
    nasa_block = ""
    if args.auto_start:
        if not (nasa_access_key and nasa_secret_key and nasa_session_token):
            raise ValueError(
                "--auto-start requires NASA_ACCESS_KEY_ID, NASA_SECRET_ACCESS_KEY, "
                "and NASA_SESSION_TOKEN in your local environment."
            )

        nasa_block = f"""
# Configure temporary NASA Earthdata S3 credentials for ec2-user.
mkdir -p /home/ec2-user/.aws
cat > /home/ec2-user/.aws/credentials <<'AWSCREDS'
[nasa]
aws_access_key_id = {nasa_access_key}
aws_secret_access_key = {nasa_secret_key}
aws_session_token = {nasa_session_token}
AWSCREDS

cat > /home/ec2-user/.aws/config <<'AWSCONFIG'
[profile nasa]
region = us-west-2
AWSCONFIG

chown -R ec2-user:ec2-user /home/ec2-user/.aws
chmod 700 /home/ec2-user/.aws
chmod 600 /home/ec2-user/.aws/credentials /home/ec2-user/.aws/config
"""

    user_data = f"""#!/bin/bash
set -euxo pipefail

exec > >(tee -a /var/log/ndvi-bootstrap.log) 2>&1

echo "NDVI worker bootstrap started at $(date)"

dnf update -y
dnf install -y python3 python3-pip python3-devel gcc gcc-c++ make awscli tmux

# Python environment
if [ ! -d /home/ec2-user/ndvi-venv ]; then
    python3 -m venv /home/ec2-user/ndvi-venv
fi
chown -R ec2-user:ec2-user /home/ec2-user/ndvi-venv

su - ec2-user -c 'source /home/ec2-user/ndvi-venv/bin/activate && python -m pip install --upgrade pip setuptools wheel'
su - ec2-user -c 'source /home/ec2-user/ndvi-venv/bin/activate && pip install numpy pandas shapely geopandas rasterio boto3 awscli'

# EBS-backed swap for memory-constrained m5.large instances.
if [ "{swap_gb}" -gt 0 ] && ! swapon --show | grep -q "/swapfile"; then
    rm -f /swapfile || true
    fallocate -l {swap_gb}G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=$(({swap_gb} * 1024))
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
fi

mkdir -p /home/ec2-user/project
chown -R ec2-user:ec2-user /home/ec2-user/project

# Download the current worker script from project S3.
aws s3 cp {worker_script_s3_q} /home/ec2-user/project/worker_poll_sqs_ndvi_old.py --no-progress

# Make sure both processing-script names exist locally for inspection.
aws s3 cp {script_s3_q} /home/ec2-user/project/compute_hls_ndvi_by_province.py --no-progress || true
aws s3 cp {cloud_script_s3_q} /home/ec2-user/project/compute_hls_ndvi_by_province_cloud_coverage.py --no-progress || true

chown -R ec2-user:ec2-user /home/ec2-user/project

# Create a convenient start script for manual or automatic worker start.
cat > /home/ec2-user/project/start_worker.sh <<'STARTWORKER'
#!/usr/bin/env bash
set -euo pipefail
source /home/ec2-user/ndvi-venv/bin/activate
python3 /home/ec2-user/project/worker_poll_sqs_ndvi_old.py --queue-url {args.queue_url} --sqs-region {args.sqs_region} --nasa-profile nasa --visibility-timeout {args.visibility_timeout} --max-empty-polls {args.max_empty_polls}
STARTWORKER

chmod +x /home/ec2-user/project/start_worker.sh
chown ec2-user:ec2-user /home/ec2-user/project/start_worker.sh

# Also save a credential-refresh template.
cat > /home/ec2-user/project/refresh_nasa_credentials_template.sh <<'REFRESH'
#!/usr/bin/env bash
set +o history

aws configure set aws_access_key_id "PASTE_NEW_ACCESS_KEY" --profile nasa
aws configure set aws_secret_access_key "PASTE_NEW_SECRET_KEY" --profile nasa
aws configure set aws_session_token "PASTE_NEW_SESSION_TOKEN" --profile nasa
aws configure set region us-west-2 --profile nasa

set -o history
aws configure list --profile nasa
REFRESH

chmod +x /home/ec2-user/project/refresh_nasa_credentials_template.sh
chown ec2-user:ec2-user /home/ec2-user/project/refresh_nasa_credentials_template.sh

{nasa_block}

if [ "{auto_start}" = "true" ]; then
    # Start worker detached inside tmux.
    su - ec2-user -c 'tmux new-session -d -s ndvi "/home/ec2-user/project/start_worker.sh"'
    echo "Started NDVI worker inside tmux session: ndvi"
else
    echo "Launch-only mode. Connect to this instance, configure NASA credentials, then run:"
    echo "  tmux new -s ndvi"
    echo "  /home/ec2-user/project/start_worker.sh"
fi

echo "NDVI worker bootstrap finished at $(date)"
"""
    return user_data


def launch_instances(args):
    session = boto3.Session(region_name=args.region)
    ec2 = session.client("ec2")
    ssm = session.client("ssm")
    sts = session.client("sts")

    caller = sts.get_caller_identity()
    print("AWS account:", caller["Account"])
    print("Region:", args.region)

    vpc_id, subnet_id = get_default_vpc_and_subnet(ec2)
    print("Default VPC:", vpc_id)
    print("Selected subnet:", subnet_id)

    sg_id = get_or_create_security_group(
        ec2=ec2,
        vpc_id=vpc_id,
        group_name=args.security_group_name,
        ssh_cidr=args.ssh_cidr,
    )

    ami_id = args.ami_id or get_amazon_linux_2023_ami(ssm)
    print("AMI:", ami_id)

    nasa_access_key = os.environ.get("NASA_ACCESS_KEY_ID")
    nasa_secret_key = os.environ.get("NASA_SECRET_ACCESS_KEY")
    nasa_session_token = os.environ.get("NASA_SESSION_TOKEN")

    user_data = build_user_data(
        args=args,
        nasa_access_key=nasa_access_key,
        nasa_secret_key=nasa_secret_key,
        nasa_session_token=nasa_session_token,
    )

    block_device_mappings = [
        {
            "DeviceName": "/dev/xvda",
            "Ebs": {
                "VolumeSize": int(args.volume_size_gb),
                "VolumeType": "gp3",
                "DeleteOnTermination": True,
            },
        }
    ]

    tag_specifications = [
        {
            "ResourceType": "instance",
            "Tags": [
                {"Key": "Name", "Value": args.name_prefix},
                {"Key": "Project", "Value": "NDVI-SQS"},
                {"Key": "Component", "Value": "EC2Worker"},
            ],
        },
        {
            "ResourceType": "volume",
            "Tags": [
                {"Key": "Project", "Value": "NDVI-SQS"},
                {"Key": "Component", "Value": "EC2WorkerVolume"},
            ],
        },
    ]

    launch_kwargs = dict(
        ImageId=ami_id,
        InstanceType=args.instance_type,
        MinCount=int(args.num_workers),
        MaxCount=int(args.num_workers),
        SecurityGroupIds=[sg_id],
        SubnetId=subnet_id,
        BlockDeviceMappings=block_device_mappings,
        IamInstanceProfile={"Name": args.iam_instance_profile},
        UserData=user_data,
        TagSpecifications=tag_specifications,
    )

    if args.key_name:
        launch_kwargs["KeyName"] = args.key_name

    print(f"Launching {args.num_workers} instance(s) of type {args.instance_type}...")
    response = ec2.run_instances(**launch_kwargs)

    instances = response["Instances"]
    instance_ids = [i["InstanceId"] for i in instances]

    print("Launched instance IDs:")
    for iid in instance_ids:
        print(" ", iid)

    if args.wait:
        print("Waiting for instances to enter running state...")
        waiter = ec2.get_waiter("instance_running")
        waiter.wait(InstanceIds=instance_ids)
        print("Instances are running.")

        # Add unique Name tags after launch.
        for idx, iid in enumerate(instance_ids, start=1):
            ec2.create_tags(
                Resources=[iid],
                Tags=[
                    {"Key": "Name", "Value": f"{args.name_prefix}-{idx:02d}"},
                    {"Key": "WorkerIndex", "Value": str(idx)},
                ],
            )

        details = ec2.describe_instances(InstanceIds=instance_ids)["Reservations"]

        rows = []
        for reservation in details:
            for inst in reservation["Instances"]:
                rows.append({
                    "instance_id": inst["InstanceId"],
                    "state": inst["State"]["Name"],
                    "instance_type": inst["InstanceType"],
                    "private_ip": inst.get("PrivateIpAddress", ""),
                    "public_ip": inst.get("PublicIpAddress", ""),
                    "public_dns": inst.get("PublicDnsName", ""),
                    "subnet_id": inst.get("SubnetId", ""),
                    "availability_zone": inst.get("Placement", {}).get("AvailabilityZone", ""),
                })

        out_path = Path(args.output_csv)
        with out_path.open("w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(
                f,
                fieldnames=[
                    "instance_id", "state", "instance_type", "private_ip",
                    "public_ip", "public_dns", "subnet_id", "availability_zone"
                ],
            )
            writer.writeheader()
            writer.writerows(rows)

        print(f"Wrote launch summary: {out_path}")
        for row in rows:
            print(row)

    return instance_ids


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--num-workers", type=int, default=2)
    parser.add_argument("--region", default="us-west-2")
    parser.add_argument("--sqs-region", default="us-east-1")
    parser.add_argument("--queue-url", required=True)
    parser.add_argument("--project-bucket", default="final-project-ndvi")
    parser.add_argument("--worker-script-key", default="scripts/worker_poll_sqs_ndvi_old.py")
    parser.add_argument("--processing-script-key", default="scripts/compute_hls_ndvi_by_province.py")
    parser.add_argument("--cloud-processing-script-key", default="scripts/compute_hls_ndvi_by_province_cloud_coverage.py")
    parser.add_argument("--instance-type", default="m5.large")
    parser.add_argument("--volume-size-gb", type=int, default=200)
    parser.add_argument("--swap-gb", type=int, default=32)
    parser.add_argument("--iam-instance-profile", default="LabInstanceProfile")
    parser.add_argument("--security-group-name", default="ndvi-worker-sg")
    parser.add_argument("--ssh-cidr", default="0.0.0.0/0")
    parser.add_argument("--key-name", default=None)
    parser.add_argument("--ami-id", default=None)
    parser.add_argument("--name-prefix", default="ndvi-worker")
    parser.add_argument("--visibility-timeout", type=int, default=21600)
    parser.add_argument("--max-empty-polls", type=int, default=5)
    parser.add_argument("--auto-start", action="store_true")
    parser.add_argument("--wait", action="store_true", default=True)
    parser.add_argument("--no-wait", dest="wait", action="store_false")
    parser.add_argument("--output-csv", default="launched_ndvi_workers.csv")
    args = parser.parse_args()

    if args.num_workers < 1:
        raise ValueError("--num-workers must be at least 1")

    launch_instances(args)


if __name__ == "__main__":
    main()
