#!/usr/bin/env bash
# Corrected worker assignment.
# Note: sha-nxi_ndvi_s3.txt -> Shanxi; shanxi_ndvi_s3.txt -> Shaanxi.
PROVINCES=(
  "Xinjiang"
  "Yunnan"
  "Shanxi"
  "Hubei"
  "Guangxi"
  "Anhui"
  "Chongqing"
  "Beijing"
)

MANIFESTS=(
  "xinjiang_ndvi_s3.txt"
  "yunnan_ndvi_s3.txt"
  "sha-nxi_ndvi_s3.txt"
  "hubei_ndvi_s3.txt"
  "guangxi_ndvi_s3.txt"
  "anhui_ndvi_s3.txt"
  "chongqing_ndvi_s3.txt"
  "beijing_ndvi_s3.txt"
)

