#!/usr/bin/env bash
# Corrected worker assignment.
# Note: sha-nxi_ndvi_s3.txt -> Shanxi; shanxi_ndvi_s3.txt -> Shaanxi.
PROVINCES=(
  "Heilongjiang"
  "Shaanxi"
  "Qinghai"
  "Guangdong"
  "Guizhou"
  "Zhejiang"
  "Hebei"
  "Liaoning"
)

MANIFESTS=(
  "heilongjiang_ndvi_s3.txt"
  "shanxi_ndvi_s3.txt"
  "qinghai_ndvi_s3.txt"
  "guangdong_ndvi_s3.txt"
  "guizhou_ndvi_s3.txt"
  "zhejiang_ndvi_s3.txt"
  "hebei_ndvi_s3.txt"
  "liaoning_ndvi_s3.txt"
)

