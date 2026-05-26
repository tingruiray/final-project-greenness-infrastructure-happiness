from pathlib import Path
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from pathlib import Path

pd.set_option("display.max_columns", 100)

# ---------------------------------------------------------------------
# 1. Locate regression output files
# ---------------------------------------------------------------------
PROJECT_ROOT = Path("C:/Users/26540/Desktop/学习/Uchicago/final-project-greenness-infrastructure-happiness")

def find_latest_file(filename):
    candidates = list(PROJECT_ROOT.rglob(filename))
    if not candidates:
        raise FileNotFoundError(f"Could not find {filename} under {PROJECT_ROOT}")
    candidates = sorted(candidates, key=lambda p: p.stat().st_mtime, reverse=True)
    print(f"Using {filename}: {candidates[0]}")
    return candidates[0]

STATS_FILE = find_latest_file("regression_results_statsmodels_clustered.csv")
SPARK_FILE = find_latest_file("regression_results_spark_ml.csv")

stats = pd.read_csv(STATS_FILE)
spark = pd.read_csv(SPARK_FILE)

# Optional, used for scatter plots
try:
    ANALYSIS_FILE = find_latest_file("analysis_data_compact.csv")
    analysis = pd.read_csv(ANALYSIS_FILE)
except FileNotFoundError:
    analysis = None
    print("analysis_data_compact.csv not found. Scatter plots will be skipped.")

# Output folder for figures
FIG_DIR = PROJECT_ROOT / "visualization"
FIG_DIR.mkdir(parents=True, exist_ok=True)

stats.head()

# ---------------------------------------------------------------------
# 1. Locate regression output files
# ---------------------------------------------------------------------

def find_latest_file(filename):
    candidates = list(PROJECT_ROOT.rglob(filename))
    if not candidates:
        raise FileNotFoundError(f"Could not find {filename} under {PROJECT_ROOT}")
    candidates = sorted(candidates, key=lambda p: p.stat().st_mtime, reverse=True)
    print(f"Using {filename}: {candidates[0]}")
    return candidates[0]

STATS_FILE = find_latest_file("regression_results_statsmodels_clustered.csv")
SPARK_FILE = find_latest_file("regression_results_spark_ml.csv")

stats = pd.read_csv(STATS_FILE)
spark = pd.read_csv(SPARK_FILE)

try:
    ANALYSIS_FILE = find_latest_file("analysis_data_compact.csv")
    analysis = pd.read_csv(ANALYSIS_FILE)
except FileNotFoundError:
    analysis = None
    print("analysis_data_compact.csv not found. Province scatter plots will be skipped.")

print("Statsmodels results:")
print(stats.head())

print("Spark ML results:")
print(spark.head())

# ---------------------------------------------------------------------
# 2. Clean regression results
# ---------------------------------------------------------------------

stats_clean = stats.copy()

# Remove failed model rows
stats_clean = stats_clean[
    ~stats_clean["term"].astype(str).str.contains("__model_status__", na=False)
].copy()

for col in ["estimate", "std_error", "p_value", "n", "r2"]:
    if col in stats_clean.columns:
        stats_clean[col] = pd.to_numeric(stats_clean[col], errors="coerce")

stats_clean = stats_clean.dropna(subset=["estimate"])

SPEC_LABELS = {
    "spec0_ndvi_only": "NDVI only",
    "spec1_demographics": "+ demographics",
    "spec2_income": "+ income",
    "spec3_full_controls": "+ full controls",
}

OUTCOME_LABELS = {
    "happiness": "Happiness",
    "ln_wtp_air3": "Log WTP for air quality",
}

TERM_LABELS = {
    "mean_ndvi": "Mean NDVI",
    "age": "Age",
    "age2": "Age squared",
    "female": "Female",
    "minority": "Ethnic minority",
    "educ_years": "Years of schooling",
    "ln_personal_income": "Log personal income",
    "ln_household_income": "Log household income",
    "health": "Self-rated health",
    "rural_hukou": "Rural hukou",
    "married": "Married",
    "ccp_member": "CCP member",
    "urban_community": "Urban community",
    "const": "Constant",
}

stats_clean["spec_label"] = stats_clean["spec"].map(SPEC_LABELS).fillna(stats_clean["spec"])
stats_clean["outcome_label"] = stats_clean["outcome"].map(OUTCOME_LABELS).fillna(stats_clean["outcome"])
stats_clean["term_label"] = stats_clean["term"].map(TERM_LABELS).fillna(stats_clean["term"])

print(stats_clean.head())

# ---------------------------------------------------------------------
# 3. Main coefficient plot: mean_ndvi across specifications
# ---------------------------------------------------------------------

ndvi_coef = stats_clean[stats_clean["term"] == "mean_ndvi"].copy()

if ndvi_coef.empty:
    print("No mean_ndvi coefficients found.")
else:
    ndvi_coef["ci_low"] = ndvi_coef["estimate"] - 1.96 * ndvi_coef["std_error"]
    ndvi_coef["ci_high"] = ndvi_coef["estimate"] + 1.96 * ndvi_coef["std_error"]

    spec_order_map = {
        "spec0_ndvi_only": 0,
        "spec1_demographics": 1,
        "spec2_income": 2,
        "spec3_full_controls": 3,
    }

    for outcome in ndvi_coef["outcome"].unique():
        d = ndvi_coef[ndvi_coef["outcome"] == outcome].copy()
        d["spec_order"] = d["spec"].map(spec_order_map)
        d = d.sort_values("spec_order")

        x = np.arange(len(d))
        y = d["estimate"]
        yerr = 1.96 * d["std_error"]

        plt.figure(figsize=(8, 5))
        plt.errorbar(x, y, yerr=yerr, fmt="o", capsize=4)
        plt.axhline(0, linestyle="--", linewidth=1)

        plt.xticks(x, d["spec_label"], rotation=25, ha="right")
        plt.ylabel("Coefficient on mean NDVI")
        plt.title(f"Estimated association between NDVI and {OUTCOME_LABELS.get(outcome, outcome)}")
        plt.tight_layout()

        outpath = FIG_DIR / f"coef_mean_ndvi_{outcome}.png"
        plt.savefig(outpath, dpi=300, bbox_inches="tight")
        plt.show()

        print("Saved:", outpath)


# ---------------------------------------------------------------------
# 4. Full-control coefficient plots
# ---------------------------------------------------------------------

def plot_full_control_coefficients(outcome, exclude_terms=("const",)):
    d = stats_clean[
        (stats_clean["outcome"] == outcome) &
        (stats_clean["spec"] == "spec3_full_controls")
    ].copy()

    d = d[~d["term"].isin(exclude_terms)].copy()
    d = d.dropna(subset=["estimate", "std_error"])

    if d.empty:
        print(f"No full-control coefficients found for {outcome}.")
        return

    d["ci_low"] = d["estimate"] - 1.96 * d["std_error"]
    d["ci_high"] = d["estimate"] + 1.96 * d["std_error"]

    d = d.sort_values("estimate")
    y_pos = np.arange(len(d))

    plt.figure(figsize=(8, max(5, 0.4 * len(d))))
    plt.errorbar(
        d["estimate"],
        y_pos,
        xerr=1.96 * d["std_error"],
        fmt="o",
        capsize=4
    )
    plt.axvline(0, linestyle="--", linewidth=1)

    plt.yticks(y_pos, d["term_label"])
    plt.xlabel("Coefficient estimate with 95% CI")
    plt.title(f"Full-control model: {OUTCOME_LABELS.get(outcome, outcome)}")
    plt.tight_layout()

    outpath = FIG_DIR / f"full_controls_coefficients_{outcome}.png"
    plt.savefig(outpath, dpi=300, bbox_inches="tight")
    plt.show()

    print("Saved:", outpath)

plot_full_control_coefficients("happiness")
plot_full_control_coefficients("ln_wtp_air3")

# ---------------------------------------------------------------------
# 6. Province-level scatter plots
# ---------------------------------------------------------------------

if analysis is not None:
    for col in ["mean_ndvi", "happiness", "ln_wtp_air3"]:
        if col in analysis.columns:
            analysis[col] = pd.to_numeric(analysis[col], errors="coerce")

    agg_dict = {
        "mean_ndvi": ("mean_ndvi", "mean"),
        "n": ("mean_ndvi", "size"),
    }

    if "happiness" in analysis.columns:
        agg_dict["happiness"] = ("happiness", "mean")

    if "ln_wtp_air3" in analysis.columns:
        agg_dict["ln_wtp_air3"] = ("ln_wtp_air3", "mean")

    province_mean = (
        analysis
        .groupby("province_key", as_index=False)
        .agg(**agg_dict)
    )

    print(province_mean.head())

    def plot_province_scatter(y_col, y_label):
        d = province_mean.dropna(subset=["mean_ndvi", y_col]).copy()

        if len(d) < 2:
            print(f"Too few provinces for scatter plot: {y_col}")
            return

        plt.figure(figsize=(7, 5))
        plt.scatter(d["mean_ndvi"], d[y_col], s=np.sqrt(d["n"]) * 8, alpha=0.7)

        coef = np.polyfit(d["mean_ndvi"], d[y_col], deg=1)
        x_line = np.linspace(d["mean_ndvi"].min(), d["mean_ndvi"].max(), 100)
        y_line = coef[0] * x_line + coef[1]
        plt.plot(x_line, y_line, linewidth=1)

        for _, row in d.iterrows():
            plt.annotate(
                row["province_key"],
                (row["mean_ndvi"], row[y_col]),
                fontsize=8,
                alpha=0.8
            )

        plt.xlabel("Province-level mean NDVI")
        plt.ylabel(y_label)
        plt.title(f"Province-level relationship: NDVI and {y_label}")
        plt.tight_layout()

        outpath = FIG_DIR / f"province_scatter_ndvi_{y_col}.png"
        plt.savefig(outpath, dpi=300, bbox_inches="tight")
        plt.show()

        print("Saved:", outpath)

    if "happiness" in province_mean.columns:
        plot_province_scatter("happiness", "Mean happiness")

    if "ln_wtp_air3" in province_mean.columns:
        plot_province_scatter("ln_wtp_air3", "Mean log WTP")

else:
    print("Skipping province scatter plots because analysis_data_compact.csv was not found.")

# ---------------------------------------------------------------------
# 7. Export compact NDVI coefficient table
# ---------------------------------------------------------------------

main_table = stats_clean[stats_clean["term"] == "mean_ndvi"].copy()

main_table = main_table[
    [
        "outcome_label",
        "spec_label",
        "estimate",
        "std_error",
        "p_value",
        "n",
        "r2",
        "cov_type",
    ]
].copy()

main_table["estimate"] = main_table["estimate"].round(6)
main_table["std_error"] = main_table["std_error"].round(6)
main_table["p_value"] = main_table["p_value"].round(4)
main_table["r2"] = main_table["r2"].round(4)

print(main_table)

outpath = FIG_DIR / "main_ndvi_coefficients_table.csv"
main_table.to_csv(outpath, index=False)

print("Saved:", outpath)
print("All visualization outputs are in:", FIG_DIR)
