## NDVI EC2 Testing Workflow

### local testing

Before moving the workflow to AWS, I first tested the full NDVI-processing pipeline locally using the Shanghai sample. I downloaded the HLS-VI files returned by Earthdata Search for Shanghai in 2018, then filtered the 140 downloaded files to the 14 files ending in .NDVI.tif, since the other files corresponded to additional vegetation or water indices such as EVI, NDWI, SAVI, and NBR. Using the China ADM1 boundary file, I selected the Shanghai Municipality polygon and verified that the NDVI GeoTIFFs were correctly georeferenced. The local script parsed each HLS filename to identify the sensing date and MGRS tile, grouped tiles by date, mosaicked same-date tiles, clipped the resulting raster to the Shanghai boundary, removed HLS fill values and invalid NDVI values, and computed a daily mean NDVI for Shanghai. I then averaged the valid daily means to produce a Shanghai-level 2018 NDVI summary.

### EC2 testing

Before generalizing to all provinces, I conducted a AWS EC2 testing workflow for computing NDVI measure for Shanghai. The goal of the test is to verify the cloud pipeline before scaling from one municipality to all Chinese provinces.

the workflow is:

```text
Earthdata Search download script
        ↓
Extract NDVI-only NASA S3 links
        ↓
Upload code, boundary file, and link manifest to user S3 bucket
        ↓
Launch EC2 instance in us-west-2
        ↓
Create Python geospatial environment
        ↓
Download project files from user S3 to EC2
        ↓
Configure NASA temporary S3 credentials
        ↓
Clean Windows line endings from S3 manifest
        ↓
Download 14 NDVI GeoTIFF files from NASA S3 to EC2
        ↓
Run NDVI processing script
        ↓
Upload output CSVs to user S3 bucket
```

**Step 1. Convert Earthdata download script to S3 manifests**

The NASA Earthdata Search download script contained about 140 file links:

```text
14 granules × about 10 layers = 140 files
```

Only NDVI was needed. The converter script extracted all Earthdata HTTPS URLs, converted them to S3 URIs, and saved three manifest files:

```text
shanghai_all_s3.txt       All 140 S3 links
shanghai_ndvi_s3.txt      14 NDVI-only S3 links
shanghai_fmask_s3.txt     14 Fmask-only S3 links
```

**Step 2. Upload project files to user S3 bucket**

Upload these files to the user bucket:
```text
s3://final-project-ndvi/
```

Files:

```text
compute_hls_ndvi_by_province.py
geoBoundaries-CHN-ADM1.geojson
shanghai_ndvi_s3.txt
```

This can be done through the AWS Console or with AWS CLI:

```bash
aws s3 cp compute_hls_ndvi_by_province.py s3://final-project-ndvi/
aws s3 cp geoBoundaries-CHN-ADM1.geojson s3://final-project-ndvi/
aws s3 cp shanghai_ndvi_s3.txt s3://final-project-ndvi/
```

---

**Step 3. Launch EC2 instance**

Use:

```text
Region: us-west-2 / Oregon
Connection: EC2 Instance Connect browser terminal
IAM role: LabInstanceProfile, if available
```

**Step 4. Set up Python environment on EC2**

Conda solving was unstable on the EC2 instance, so the working setup used `venv` and `pip`.

```bash
cd ~

sudo dnf update -y
sudo dnf install -y python3 python3-pip python3-devel gcc gcc-c++ make awscli

python3 -m venv ndvi-venv
source ~/ndvi-venv/bin/activate

python -m pip install --upgrade pip setuptools wheel
pip install numpy pandas shapely geopandas rasterio boto3 awscli
```

Test:

```bash
python -c "import geopandas, rasterio, pandas, numpy; print('NDVI environment ready')"
```

Expected:

```text
NDVI environment ready
```

**Step 5. Download project files from user S3 bucket to EC2**

```bash
mkdir -p ~/project
cd ~/project

aws s3 cp s3://final-project-ndvi/compute_hls_ndvi_by_province.py .
aws s3 cp s3://final-project-ndvi/geoBoundaries-CHN-ADM1.geojson .
aws s3 cp s3://final-project-ndvi/shanghai_ndvi_s3.txt .
```

Check:

```bash
ls -lh
head shanghai_ndvi_s3.txt
wc -l shanghai_ndvi_s3.txt
```

Expected:

```text
14 shanghai_ndvi_s3.txt
```

**Step 6. Configure NASA temporary S3 credentials**

Get temporary AWS credentials from the NASA Earthdata Search **AWS S3 Access** tab. Save the NASA credentials as a local JSON file. On EC2:

cd ~/project
nano nasa_creds.json

Paste the JSON credentials into the file, then save:

Ctrl + O
Enter
Ctrl + X

Configure an AWS profile called nasa. Run this:

python - <<'PY'
import json
import subprocess

with open("nasa_creds.json", "r") as f:
    creds = json.load(f)

profile = "nasa"

items = {
    "aws_access_key_id": creds["accessKeyId"],
    "aws_secret_access_key": creds["secretAccessKey"],
    "aws_session_token": creds["sessionToken"],
    "region": "us-west-2",
}

for key, value in items.items():
    subprocess.run(
        ["aws", "configure", "set", key, value, "--profile", profile],
        check=True
    )

print("Configured AWS profile: nasa")
print("Credential expiration:", creds.get("expiration"))
PY


Then, test NASA S3 access. The working NASA S3 prefix was:

```text
s3://lp-prod-protected/HLSS30_VI.020/
```

Test one granule directory:

```bash
cd ~/project
mkdir -p ~/project/Shanghai

aws s3 ls s3://lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T51SUR.2018301T022811.v2.0/ \
  --profile nasa \
  --region us-west-2

echo $?
```

Expected listing includes:

```text
HLS-VI.S30.T51SUR.2018301T022811.v2.0.EVI.tif
HLS-VI.S30.T51SUR.2018301T022811.v2.0.MSAVI.tif
HLS-VI.S30.T51SUR.2018301T022811.v2.0.NBR.tif
HLS-VI.S30.T51SUR.2018301T022811.v2.0.NDVI.tif
HLS-VI.S30.T51SUR.2018301T022811.v2.0.NDWI.tif
HLS-VI.S30.T51SUR.2018301T022811.v2.0.SAVI.tif
HLS-VI.S30.T51SUR.2018301T022811.v2.0.TVI.tif
HLS-VI.S30.T51SUR.2018301T022811.v2.0.cmr.xml
```

Expected exit code:

```text
0
```

Then test copying one NDVI file:

```bash
aws s3 cp \
  s3://lp-prod-protected/HLSS30_VI.020/HLS-VI.S30.T51SUR.2018301T022811.v2.0/HLS-VI.S30.T51SUR.2018301T022811.v2.0.NDVI.tif \
  ~/project/Shanghai/ \
  --profile nasa \
  --region us-west-2 \
  --no-progress

echo $?
ls -lh ~/project/Shanghai/
```

Expected:

```text
download: s3://lp-prod-protected/...NDVI.tif to Shanghai/...NDVI.tif
0
```

---

**Step 8. Clean Windows line endings from the manifest**

The original manifest was created on Windows and had CRLF line endings. This caused AWS CLI loop downloads to fail with 404 errors because each URI ended with a hidden carriage return.

Error symptom:

```text
An error occurred (404) when calling the HeadObject operation:
Key "...NDVI.tif\r" does not exist
```

Fix:

```bash
cd ~/project

tr -d '\r' < shanghai_ndvi_s3.txt > shanghai_ndvi_s3_clean.txt

wc -l shanghai_ndvi_s3.txt
wc -l shanghai_ndvi_s3_clean.txt
head -n 2 shanghai_ndvi_s3_clean.txt
```

Expected:

```text
14 shanghai_ndvi_s3_clean.txt
```

---

**Step 8. Download all 14 Shanghai NDVI files from NASA S3**

Use the cleaned manifest:

```bash
mkdir -p ~/project/Shanghai

while IFS= read -r uri; do
  echo "Downloading: $uri"
  aws s3 cp "$uri" ~/project/Shanghai/ \
    --profile nasa \
    --region us-west-2 \
    --no-progress
done < ~/project/shanghai_ndvi_s3_clean.txt
```

Check:

```bash
ls ~/project/Shanghai/*.NDVI.tif | wc -l
ls -lh ~/project/Shanghai/
```

Expected:

```text
14
```

---

**Step 9. Run the Shanghai NDVI computation**

Activate the environment:

```bash
source ~/ndvi-venv/bin/activate
```

Run the script:

```bash
mkdir -p ~/project/ndvi_outputs

python ~/project/compute_hls_ndvi_by_province.py \
  --hls-dir ~/project/Shanghai \
  --boundary-file ~/project/geoBoundaries-CHN-ADM1.geojson \
  --province "Shanghai" \
  --year 2018 \
  --out-dir ~/project/ndvi_outputs
```
---

**Step 10. Successful EC2 output**

The successful EC2 run found:

```text
Found 14 NDVI files after year filtering.
Distinct dates before spatial filtering: 7
Kept 14 NDVI files intersecting Shanghai.
Distinct dates after spatial filtering: 7
```

The script processed:

```text
2018-01-11: 1 tile  ['T51RUP']
2018-02-13: 2 tiles ['T51RTQ', 'T51RUQ']
2018-03-10: 1 tile  ['T51RUP']
2018-04-09: 3 tiles ['T51RTQ', 'T51RUP', 'T51RUQ']
2018-04-19: 4 tiles ['T51RTQ', 'T51RUP', 'T51RUQ', 'T51RVQ']
2018-10-01: 1 tile  ['T51RUQ']
2018-10-28: 2 tiles ['T51RVQ', 'T51SUR']
```

Final annual result:

```text
province  year  n_valid_dates  n_ndvi_files_used  mean_ndvi_equal_day  mean_ndvi_pixel_weighted  total_valid_pixel_observations  min_daily_ndvi  max_daily_ndvi
Shanghai  2018              7                 14             0.102517                  0.304008                        24606438       -0.524164        0.499692
```

---

**Step 11. Upload outputs to user S3 bucket**
Command:

```bash
aws s3 cp ~/project/ndvi_outputs/ \
  s3://final-project-ndvi/outputs/shanghai/ \
  --recursive
```

Verify:

```bash
aws s3 ls s3://final-project-ndvi/outputs/shanghai/
```

Expected files:

```text
Shanghai_raw_ndvi_manifest.csv
Shanghai_intersecting_ndvi_manifest.csv
Shanghai_daily_ndvi_2018.csv
Shanghai_annual_ndvi_2018.csv
```


## Scaling 

After this test, the same logic can be scaled by assigning each province to a separate task:

```text
one province = one processing task
```

A task can be represented as JSON:

```json
{
  "province": "Shanghai",
  "year": 2018,
  "manifest_s3": "s3://final-project-ndvi/manifests/shanghai_ndvi_s3_clean.txt",
  "boundary_s3": "s3://final-project-ndvi/geoBoundaries-CHN-ADM1.geojson",
  "output_s3": "s3://final-project-ndvi/outputs/shanghai/"
}
```

The full-scale AWS pipeline is now operational and has been validated end-to-end. Province-level NDVI tasks were successfully enqueued into the SQS queue ndvi-province-tasks, with each message containing the province name, the corresponding NDVI S3 manifest, the boundary file location, the processing script location, and the intended S3 output folder. An EC2 worker was then launched with the required geospatial Python environment and IAM permissions. The worker successfully polled tasks from SQS, downloaded the processing script, China ADM1 boundary file, and province-specific NDVI manifest from s3://final-project-ndvi/, used temporary NASA Earthdata S3 credentials to download the required HLS-VI .NDVI.tif files from lp-prod-protected, ran the province-level NDVI processing script, uploaded the resulting daily and annual NDVI CSV files back to S3, and deleted the SQS message only after successful completion. Beijing was successfully processed, producing Beijing_annual_ndvi_2018.csv and related diagnostic files under s3://final-project-ndvi/outputs/beijing/. This confirms that the distributed SQS–EC2–S3 workflow works as intended: province tasks can be scheduled through SQS, processed independently by EC2 workers, and stored as province-level NDVI outputs in S3. For larger provinces, the same pipeline remains valid, though larger-memory workers or the multi-CRS patched script may be needed to handle heavier mosaicking workloads.




set +o history

aws configure set aws_access_key_id "ASIAZLX6ZES4TKL43RAB" --profile nasa
aws configure set aws_secret_access_key "jWqjV0LbAaM30800keyN1U08Xxxvgg9LOOVHbUjz" --profile nasa
aws configure set aws_session_token "IQoJb3JpZ2luX2VjEGEaCXVzLXdlc3QtMiJHMEUCIQDyoeUCqwbD2uVJ3ECXbtkzVb0EZUvLKJoq1HwSercGLgIgPVOhDrf2HY95/O6BV3wrSbhZY4eXBEtMxsmEW4jjyjwqggMIKhADGgw2NDM3MDU2NzY5ODUiDFmENb9lRnf1VrzVMirfAuvTVdhTRSw5xjT4qRRsNRpoDopGg7vmYzsjoRAcfXgRtR99ErAIXkheXleh53wvCur/vvpToNZK/nJ/sQtH6XJE07Lbs9BS5VQpcxeDH1cclcKeesU4F76lsw49schzopDXNYp20QXu4Zk+fJmgH0IHhzH4NnJaBQa0co0BlL5w8hhfQz++4RejP//IdST/8KkCHzZoY2Jy3cnkJpQDR9OgBpP8Dg6dYhmwXpzG/wefuEQK4heTOaze5DdlnUnZDKASmLwd/wDqNH2r0Wb6SD9wH/ur6u5Q/o1afVNH8Js97rYwgwe6MRegZZKjOED5HSPQ0cAlDNMefhyg2t4S7CqcQF/D3SDKTqVWhaADt2zyPaX3/rwcqzsdio8E9wFn+MTMgaXhu3vhbSlfaXnYxJjfxPdJH4J9U67gF0LtOygx5PrU7ho/JuypQ8Q3exMpakN5cVDmXu7cMIuaP8LiwTDE5sPQBjqdAWCO88px4MYsrIDnI201HouOjC/vEHDhEWp0SmWOT2qkM9pgp1by0BRlbNLdNgITqjV1TLrXIQYBiPfsD5OMrnhBgN7/qzV0UQUv8hzWvDMUb6dJeF+70lUpfx2cxNfJtmVJyzGsXGUhXCoXw5+MsYHCsyRdHH4yxyuuZGy5ueQ/gNV7TtcD4GJYtTbmykgQmw1Xo83iYuw73PtRaMg=" --profile nasa
aws configure set region us-west-2 --profile nasa

set -o history




https://sqs.us-east-1.amazonaws.com/891377197146/ndvi-province-tasks