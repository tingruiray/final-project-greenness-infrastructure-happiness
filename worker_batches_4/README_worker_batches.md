# Corrected 4-Worker NDVI Batches

This folder contains corrected worker assignments for the province-level NDVI pipeline.

## Important correction

The previous pinyin index had two confusing files:

- `sha-nxi_ndvi_s3.txt` corresponds to **Shanxi** (山西).
- `shanxi_ndvi_s3.txt` corresponds to **Shaanxi** (陕西).

`shenzhen_ndvi_s3.txt` is dropped because Shenzhen is not an ADM1 province in the China ADM1 boundary file.

## Load balance

| Worker | Tasks | NDVI links |
|---:|---:|---:|
| 1 | 8 | 4,344 |
| 2 | 5 | 4,344 |
| 3 | 8 | 4,345 |
| 4 | 8 | 4,345 |

The maximum difference between workers is only **1 NDVI file**, so the workload is essentially perfectly balanced by manifest size.

## Files

For each worker, the folder includes:

- `worker_XX_tasks.csv`: province, manifest file, and NDVI link count.
- `worker_XX_provinces.txt`: province names to pass into `--province`.
- `worker_XX_manifest_files.txt`: S3 manifest filenames to download.
- `worker_XX_arrays.sh`: bash arrays for scripting.

The summary files are:

- `worker_batches_summary.csv`
- `worker_load_summary.csv`

## Assignments

### Worker 1

Gansu, Sichuan, Jilin, Jiangxi, Henan, Jiangsu, Tianjin, Shanghai

### Worker 2

Inner Mongolia, Ningxia, Hunan, Shandong, Fujian

### Worker 3

Xinjiang, Yunnan, Shanxi, Hubei, Guangxi, Anhui, Chongqing, Beijing

### Worker 4

Heilongjiang, Shaanxi, Qinghai, Guangdong, Guizhou, Zhejiang, Hebei, Liaoning

## Notes for running the pipeline

Use the `province` column from `worker_XX_tasks.csv` as the value for:

```bash
--province "<province>"
```

Use the `manifest_file` column as the S3 manifest filename to download from your manifest bucket/folder.

For example, for Shanxi:

```bash
--province "Shanxi"
manifest_file="sha-nxi_ndvi_s3.txt"
```

For Shaanxi:

```bash
--province "Shaanxi"
manifest_file="shanxi_ndvi_s3.txt"
```
