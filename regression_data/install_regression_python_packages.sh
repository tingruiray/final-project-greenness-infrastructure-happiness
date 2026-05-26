#!/usr/bin/env bash
set -euxo pipefail
sudo python3 -m pip install --upgrade pip
sudo python3 -m pip install --upgrade pandas numpy statsmodels pyarrow boto3
