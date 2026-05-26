#!/usr/bin/env python3
"""
run_regressions_emr.py

Run final CGSS-NDVI regressions on EMR.

Inputs:
  --cgss-s3   s3://final-project-ndvi/regression/input/cgss/CGSS2018_clean_main.csv
  --ndvi-s3   s3://final-project-ndvi/regression/input/ndvi/ndvi_province_annual_2018.csv
  --output-s3 s3://final-project-ndvi/regression/output/<run_id>

Main outcomes:
  happiness
  ln_wtp_air3, or log(wtp_air3 + 1) if ln_wtp_air3 is not present

Main treatment:
  mean_ndvi / annual_mean_ndvi / avg_ndvi / ndvi_mean / ndvi, detected from the NDVI file

Identification note:
  The merged NDVI measure varies at the province-year level. Since this project
  uses CGSS 2018 only, province fixed effects would absorb province-level NDVI.
  The default specifications therefore do not include province fixed effects.
"""

from __future__ import annotations

import argparse
import os
import re
import tempfile
from pathlib import Path
from typing import Dict, Iterable, List, Tuple

import boto3
import pandas as pd
import numpy as np

from pyspark.sql import SparkSession, functions as F, types as T
from pyspark.ml.feature import VectorAssembler
from pyspark.ml.regression import LinearRegression


def parse_s3_uri(uri: str) -> Tuple[str, str]:
    if not uri.startswith("s3://"):
        raise ValueError(f"Expected S3 URI, got: {uri}")
    no_scheme = uri[5:]
    bucket, _, key = no_scheme.partition("/")
    return bucket, key.rstrip("/")


def upload_dir_to_s3(local_dir: str | Path, s3_prefix: str) -> None:
    local_dir = Path(local_dir)
    bucket, key_prefix = parse_s3_uri(s3_prefix)
    s3 = boto3.client("s3")
    for path in local_dir.rglob("*"):
        if path.is_file():
            rel = path.relative_to(local_dir).as_posix()
            s3.upload_file(str(path), bucket, f"{key_prefix}/{rel}")


PROVINCE_PATTERNS: Dict[str, List[str]] = {
    "beijing": ["beijing", "bei jing", "北京", "北京市"],
    "tianjin": ["tianjin", "tian jin", "天津", "天津市"],
    "hebei": ["hebei", "he bei", "河北", "河北省"],
    "shanxi": ["shanxi", "shan xi", "山西", "山西省"],
    "inner_mongolia": ["inner_mongolia", "inner mongolia", "neimenggu", "nei meng gu", "内蒙古"],
    "liaoning": ["liaoning", "liao ning", "辽宁", "辽宁省"],
    "jilin": ["jilin", "ji lin", "吉林", "吉林省"],
    "heilongjiang": ["heilongjiang", "hei long jiang", "黑龙江", "黑龙江省"],
    "shanghai": ["shanghai", "shang hai", "上海", "上海市"],
    "jiangsu": ["jiangsu", "jiang su", "江苏", "江苏省"],
    "zhejiang": ["zhejiang", "zhe jiang", "浙江", "浙江省"],
    "anhui": ["anhui", "an hui", "安徽", "安徽省"],
    "fujian": ["fujian", "fu jian", "福建", "福建省"],
    "jiangxi": ["jiangxi", "jiang xi", "江西", "江西省"],
    "shandong": ["shandong", "shan dong", "山东", "山东省"],
    "henan": ["henan", "he nan", "河南", "河南省"],
    "hubei": ["hubei", "hu bei", "湖北", "湖北省"],
    "hunan": ["hunan", "hu nan", "湖南", "湖南省"],
    "guangdong": ["guangdong", "guang dong", "广东", "广东省"],
    "guangxi": ["guangxi", "guang xi", "广西", "广西壮族自治区"],
    "hainan": ["hainan", "hai nan", "海南", "海南省"],
    "chongqing": ["chongqing", "chong qing", "重庆", "重庆市"],
    "sichuan": ["sichuan", "si chuan", "四川", "四川省"],
    "guizhou": ["guizhou", "gui zhou", "贵州", "贵州省"],
    "yunnan": ["yunnan", "yun nan", "云南", "云南省"],
    "tibet": ["tibet", "xizang", "xi zang", "西藏"],
    "shaanxi": ["shaanxi", "shaan xi", "sha-nxi", "陕西", "陕西省"],
    "gansu": ["gansu", "gan su", "甘肃", "甘肃省"],
    "qinghai": ["qinghai", "qing hai", "青海", "青海省"],
    "ningxia": ["ningxia", "ning xia", "宁夏", "宁夏回族自治区"],
    "xinjiang": ["xinjiang", "xin jiang", "新疆", "新疆维吾尔自治区"],
    "shenzhen": ["shenzhen", "shen zhen", "深圳", "深圳市"],
}


def normalize_text(x) -> str:
    if x is None or (isinstance(x, float) and np.isnan(x)):
        return ""
    s = str(x).strip().lower()
    s = s.replace("-", "_")
    s = re.sub(r"\s+", "_", s)
    s = s.replace("province", "").replace("municipality", "")
    s = s.replace("autonomous_region", "")
    s = s.replace("zhuang", "").replace("hui", "").replace("uyghur", "").replace("uighur", "")
    return s.strip("_")


def province_key_python(x) -> str:
    raw = "" if x is None else str(x).strip()
    norm = normalize_text(raw)
    if not norm:
        return ""
    if norm in PROVINCE_PATTERNS:
        return norm
    if norm == "neimenggu":
        return "inner_mongolia"
    if norm in ["sha_nxi", "sha-nxi"]:
        return "shaanxi"

    raw_lower = raw.lower()
    for key, patterns in PROVINCE_PATTERNS.items():
        for p in patterns:
            pp = p.lower()
            if pp in raw_lower or normalize_text(pp) in norm:
                return key
    return norm


def find_col(cols: Iterable[str], candidates: Iterable[str], required: bool = True) -> str | None:
    cols = list(cols)
    lower_map = {c.lower(): c for c in cols}
    for cand in candidates:
        if cand.lower() in lower_map:
            return lower_map[cand.lower()]
    for c in cols:
        lc = c.lower()
        for cand in candidates:
            if cand.lower() in lc:
                return c
    if required:
        raise ValueError(f"Could not find any of {list(candidates)} in columns: {cols}")
    return None


def safe_numeric_spark(df, cols: List[str]):
    out = df
    for c in cols:
        if c in out.columns:
            out = out.withColumn(c, F.col(c).cast("double"))
    return out


def build_controls(cols: List[str]) -> Dict[str, List[str]]:
    base = []
    if "age" in cols:
        base.extend(["age", "age2"])
    for c in ["female", "minority", "educ_years"]:
        if c in cols:
            base.append(c)

    socioeconomic = list(base)
    for c in ["ln_personal_income", "ln_household_income"]:
        if c in cols:
            socioeconomic.append(c)

    full = list(socioeconomic)
    for c in ["health", "rural_hukou", "married", "ccp_member", "urban_community"]:
        if c in cols:
            full.append(c)

    return {
        "spec0_ndvi_only": [],
        "spec1_demographics": base,
        "spec2_income": socioeconomic,
        "spec3_full_controls": full,
    }


def fit_spark_lr(df, y_col: str, x_cols: List[str], spec_name: str) -> pd.DataFrame:
    model_df = df.select([y_col] + x_cols).dropna()
    n = model_df.count()
    if n < max(20, len(x_cols) + 5):
        return pd.DataFrame([{
            "outcome": y_col, "spec": spec_name, "term": "__model_status__",
            "estimate": np.nan, "n": n, "rmse": np.nan, "r2": np.nan,
            "note": "Too few complete observations for Spark LinearRegression",
        }])

    assembler = VectorAssembler(inputCols=x_cols, outputCol="features", handleInvalid="skip")
    assembled = assembler.transform(model_df).select(F.col(y_col).alias("label"), "features")

    lr = LinearRegression(featuresCol="features", labelCol="label", elasticNetParam=0.0, regParam=0.0)
    fit = lr.fit(assembled)

    rows = [{
        "outcome": y_col, "spec": spec_name, "term": "Intercept",
        "estimate": float(fit.intercept), "n": n,
        "rmse": float(fit.summary.rootMeanSquaredError), "r2": float(fit.summary.r2),
        "note": "",
    }]
    for term, coef in zip(x_cols, fit.coefficients):
        rows.append({
            "outcome": y_col, "spec": spec_name, "term": term,
            "estimate": float(coef), "n": n,
            "rmse": float(fit.summary.rootMeanSquaredError), "r2": float(fit.summary.r2),
            "note": "",
        })
    return pd.DataFrame(rows)


def fit_statsmodels(df_pd: pd.DataFrame, y_col: str, x_cols: List[str], spec_name: str) -> pd.DataFrame:
    try:
        import statsmodels.api as sm
    except Exception as e:
        return pd.DataFrame([{
            "outcome": y_col, "spec": spec_name, "term": "__statsmodels_unavailable__",
            "estimate": np.nan, "std_error": np.nan, "p_value": np.nan,
            "n": np.nan, "r2": np.nan, "cov_type": "", "note": repr(e),
        }])

    use_cols = [y_col] + x_cols + ["province_key"]
    d = df_pd[use_cols].copy()
    for c in [y_col] + x_cols:
        d[c] = pd.to_numeric(d[c], errors="coerce")
    d = d.dropna(subset=[y_col] + x_cols)

    if len(d) < max(20, len(x_cols) + 5):
        return pd.DataFrame([{
            "outcome": y_col, "spec": spec_name, "term": "__model_status__",
            "estimate": np.nan, "std_error": np.nan, "p_value": np.nan,
            "n": len(d), "r2": np.nan, "cov_type": "",
            "note": "Too few complete observations for statsmodels OLS",
        }])

    X = sm.add_constant(d[x_cols], has_constant="add")
    y = d[y_col]
    model = sm.OLS(y, X).fit()

    n_clusters = d["province_key"].nunique(dropna=True)
    if n_clusters >= 2:
        fit = model.get_robustcov_results(cov_type="cluster", groups=d["province_key"])
        cov_type = "cluster_by_province"
    else:
        fit = model.get_robustcov_results(cov_type="HC1")
        cov_type = "HC1"

    params = pd.Series(fit.params, index=X.columns)
    bse = pd.Series(fit.bse, index=X.columns)
    pvals = pd.Series(fit.pvalues, index=X.columns)

    rows = []
    for term in X.columns:
        rows.append({
            "outcome": y_col, "spec": spec_name, "term": term,
            "estimate": float(params[term]), "std_error": float(bse[term]),
            "p_value": float(pvals[term]), "n": int(fit.nobs),
            "r2": float(fit.rsquared), "cov_type": cov_type, "note": "",
        })
    return pd.DataFrame(rows)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cgss-s3", required=True)
    parser.add_argument("--ndvi-s3", required=True)
    parser.add_argument("--output-s3", required=True)
    parser.add_argument("--year", type=int, default=2018)
    parser.add_argument("--ndvi-col", default=None)
    args = parser.parse_args()

    spark = SparkSession.builder.appName("CGSS_NDVI_Regression").getOrCreate()
    spark.sparkContext.setLogLevel("WARN")

    out_s3 = args.output_s3.rstrip("/")
    local_out = Path(tempfile.mkdtemp(prefix="cgss_ndvi_regression_"))
    print(f"Local output directory: {local_out}")
    print(f"S3 output prefix: {out_s3}")

    cgss = spark.read.option("header", True).option("inferSchema", True).csv(args.cgss_s3)
    ndvi = spark.read.option("header", True).option("inferSchema", True).csv(args.ndvi_s3)

    print("CGSS columns:", cgss.columns)
    print("NDVI columns:", ndvi.columns)

    cgss_province_col = find_col(cgss.columns, ["province_key", "province_name", "province", "provinces"], required=True)
    ndvi_province_col = find_col(ndvi.columns, ["province_key", "province", "province_name", "region"], required=True)

    if args.ndvi_col:
        ndvi_value_col = args.ndvi_col
    else:
        ndvi_value_col = find_col(ndvi.columns, ["mean_ndvi", "annual_mean_ndvi", "avg_ndvi", "ndvi_mean", "ndvi", "mean"], required=True)

    print(f"Using CGSS province column: {cgss_province_col}")
    print(f"Using NDVI province column: {ndvi_province_col}")
    print(f"Using NDVI value column: {ndvi_value_col}")

    province_key_udf = F.udf(province_key_python, T.StringType())

    cgss = cgss.withColumn("province_raw", F.col(cgss_province_col).cast("string"))
    cgss = cgss.withColumn("province_key", province_key_udf("province_raw"))

    ndvi = ndvi.withColumn("province_raw_ndvi", F.col(ndvi_province_col).cast("string"))
    ndvi = ndvi.withColumn("province_key", province_key_udf("province_raw_ndvi"))
    ndvi = ndvi.withColumn("mean_ndvi", F.col(ndvi_value_col).cast("double"))

    year_cols = [c for c in ndvi.columns if c.lower() == "year"]
    if year_cols:
        ndvi = ndvi.filter(F.col(year_cols[0]).cast("int") == int(args.year))

    ndvi_small = (
        ndvi.filter(F.col("province_key") != "")
        .groupBy("province_key")
        .agg(F.mean("mean_ndvi").alias("mean_ndvi"), F.count("*").alias("ndvi_rows"))
    )

    merged = cgss.join(ndvi_small, on="province_key", how="left")

    if "wtp_air3" in merged.columns and "ln_wtp_air3" not in merged.columns:
        merged = merged.withColumn("wtp_air3", F.col("wtp_air3").cast("double"))
        merged = merged.withColumn("ln_wtp_air3", F.log1p(F.col("wtp_air3")))

    if "age" in merged.columns:
        merged = merged.withColumn("age", F.col("age").cast("double"))
        merged = merged.withColumn("age2", F.col("age") * F.col("age"))

    numeric_candidates = [
        "happiness", "wtp_air3", "ln_wtp_air3", "mean_ndvi",
        "female", "age", "age2", "minority", "educ_years", "health",
        "rural_hukou", "married", "ccp_member", "urban_community",
        "ln_personal_income", "ln_household_income",
    ]
    merged = safe_numeric_spark(merged, numeric_candidates)

    if "happiness" in merged.columns:
        merged = merged.withColumn(
            "happiness",
            F.when((F.col("happiness") >= 1) & (F.col("happiness") <= 5), F.col("happiness")).otherwise(F.lit(None))
        )

    diagnostics = {
        "n_cgss_rows": cgss.count(),
        "n_ndvi_provinces": ndvi_small.count(),
        "n_merged_rows": merged.count(),
        "n_missing_ndvi_after_merge": merged.filter(F.col("mean_ndvi").isNull()).count(),
        "n_provinces_cgss": merged.select("province_key").distinct().count(),
        "n_provinces_with_ndvi": merged.filter(F.col("mean_ndvi").isNotNull()).select("province_key").distinct().count(),
    }
    pd.DataFrame([diagnostics]).to_csv(local_out / "merge_diagnostics.csv", index=False)

    unmatched_cgss = merged.filter(F.col("mean_ndvi").isNull()).select("province_raw", "province_key").distinct().toPandas()
    unmatched_cgss.to_csv(local_out / "unmatched_cgss_provinces.csv", index=False)

    ndvi_keys_pd = ndvi_small.select("province_key").distinct().toPandas()
    cgss_keys_pd = cgss.select("province_key").distinct().toPandas()
    unmatched_ndvi = ndvi_keys_pd[~ndvi_keys_pd["province_key"].isin(cgss_keys_pd["province_key"])]
    unmatched_ndvi.to_csv(local_out / "unmatched_ndvi_provinces.csv", index=False)

    merged.coalesce(1).write.mode("overwrite").option("header", True).csv(f"{out_s3}/analysis_data_spark_csv")

    outcomes = []
    if "happiness" in merged.columns:
        outcomes.append("happiness")
    if "ln_wtp_air3" in merged.columns:
        outcomes.append("ln_wtp_air3")

    controls_by_spec = build_controls(merged.columns)
    needed = set(["province_key", "mean_ndvi"] + outcomes)
    for ctrl_list in controls_by_spec.values():
        needed.update(ctrl_list)
    needed = [c for c in needed if c in merged.columns]

    analysis_pd = merged.select(needed).toPandas()
    analysis_pd.to_csv(local_out / "analysis_data_compact.csv", index=False)

    all_spark_results = []
    all_stats_results = []
    for y in outcomes:
        for spec, controls in controls_by_spec.items():
            x_cols = ["mean_ndvi"] + [c for c in controls if c != "mean_ndvi"]
            x_cols = [c for c in x_cols if c in merged.columns]

            all_spark_results.append(fit_spark_lr(merged, y, x_cols, spec))
            all_stats_results.append(fit_statsmodels(analysis_pd, y, x_cols, spec))

    pd.concat(all_spark_results, ignore_index=True).to_csv(local_out / "regression_results_spark_ml.csv", index=False)
    pd.concat(all_stats_results, ignore_index=True).to_csv(local_out / "regression_results_statsmodels_clustered.csv", index=False)

    notes = f"""CGSS-NDVI regression notes

Year: {args.year}
CGSS input: {args.cgss_s3}
NDVI input: {args.ndvi_s3}
Output: {out_s3}

Main treatment:
  mean_ndvi, province-level annual average NDVI.

Main outcomes:
  happiness
  ln_wtp_air3 when available, otherwise log(wtp_air3 + 1).

Default specifications:
  spec0_ndvi_only: outcome ~ mean_ndvi
  spec1_demographics: + age, age^2, female, minority, education
  spec2_income: + log personal/household income controls where available
  spec3_full_controls: + health, hukou, marriage, CCP membership, community type where available

Province fixed effects are intentionally excluded because the NDVI variable is
measured at the province-year level and CGSS is a single 2018 cross-section.
Including province fixed effects would absorb the main NDVI regressor.

Primary inference table:
  regression_results_statsmodels_clustered.csv

Spark ML coefficient table:
  regression_results_spark_ml.csv
"""
    (local_out / "regression_notes.txt").write_text(notes, encoding="utf-8")

    upload_dir_to_s3(local_out, out_s3)

    print("Regression complete.")
    print("Uploaded outputs to:", out_s3)
    for path in sorted(local_out.iterdir()):
        print(" ", path.name)

    spark.stop()


if __name__ == "__main__":
    main()
