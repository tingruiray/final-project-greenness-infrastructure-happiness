#!/usr/bin/env bash
# Corrected worker assignment.
# Note: sha-nxi_ndvi_s3.txt -> Shanxi; shanxi_ndvi_s3.txt -> Shaanxi.
PROVINCES=(
  "Inner Mongolia"
  "Ningxia"
  "Hunan"
  "Shandong"
  "Fujian"
)

MANIFESTS=(
  "neimenggu_ndvi_s3.txt"
  "ningxia_ndvi_s3.txt"
  "hunan_ndvi_s3.txt"
  "shandong_ndvi_s3.txt"
  "fujian_ndvi_s3.txt"
)

