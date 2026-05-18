"""
Compute province/municipality-average NDVI from HLS-VI .NDVI.tif files.

Workflow implemented:
1. Keep only .NDVI.tif files.
2. Group files by sensing date.
3. For each date, combine/mosaic all tiles intersecting the target province.
4. Clip the daily mosaic to the target province boundary.
5. Remove HLS fill values and invalid NDVI values.
6. Compute daily mean NDVI.
7. Average daily means across the year.

Example:
    python compute_hls_ndvi_by_province.py ^
        --hls-dir "C:/path/to/hls_downloads" ^
        --boundary-file "C:/path/to/geoBoundaries-CHN-ADM1.geojson" ^
        --province "Shanghai" ^
        --year 2018 ^
        --out-dir "C:/path/to/output"
"""

from __future__ import annotations

import argparse
import re
from contextlib import ExitStack
from pathlib import Path

import geopandas as gpd
import numpy as np
import pandas as pd
import rasterio
from rasterio.io import MemoryFile
from rasterio.mask import mask
from rasterio.merge import merge
from shapely.geometry import box


FILL_VALUE = -19999
SCALE_FACTOR = 0.0001


def get_union_geometry(gdf: gpd.GeoDataFrame):
    """Return a single unioned geometry, compatible with old and new GeoPandas."""
    if hasattr(gdf.geometry, "union_all"):
        return gdf.geometry.union_all()
    return gdf.unary_union


def choose_name_column(gdf: gpd.GeoDataFrame, requested_col: str | None = None) -> str:
    """Find a plausible administrative-unit name column."""
    if requested_col is not None:
        if requested_col not in gdf.columns:
            raise ValueError(
                f"Requested name column '{requested_col}' is not in the boundary file. "
                f"Available columns: {list(gdf.columns)}"
            )
        return requested_col

    candidates = [
        "shapeName", "shapeName_1", "NAME_1", "NAME", "name", "Name",
        "ADM1_EN", "adm1_en", "province", "Province", "省", "省份"
    ]
    for col in candidates:
        if col in gdf.columns:
            return col

    raise ValueError(
        "Could not automatically identify the province-name column. "
        f"Available columns: {list(gdf.columns)}. "
        "Rerun with --name-col COLUMN_NAME."
    )


def select_target_boundary(
    boundary_file: Path,
    province: str,
    name_col: str | None = None
) -> gpd.GeoDataFrame:
    """Load ADM1 boundaries and select the target province/municipality."""
    adm1 = gpd.read_file(boundary_file)

    if adm1.empty:
        raise ValueError("Boundary file was read successfully but contains no rows.")

    col = choose_name_column(adm1, name_col)
    target = adm1[adm1[col].astype(str).str.contains(province, case=False, na=False)].copy()

    if target.empty:
        names = sorted(adm1[col].dropna().astype(str).unique().tolist())
        preview = names[:50]
        raise ValueError(
            f"Could not find province/municipality matching '{province}' in column '{col}'.\n"
            f"First available names are: {preview}\n"
            f"Try rerunning with an exact name from this list or specify --name-col."
        )

    print(f"Boundary file: {boundary_file}")
    print(f"Using name column: {col}")
    print(f"Matched boundary rows: {target[col].tolist()}")
    print(f"Boundary CRS: {target.crs}")

    return target


def parse_hls_ndvi_filename(path: Path) -> dict | None:
    """
    Parse HLS-VI NDVI filename.

    Example:
        HLS-VI.S30.T51RVQ.2018301T022811.v2.0.NDVI.tif

    Returns:
        dict with sensor, tile, date, timestamp, path
    """
    pattern = re.compile(
        r"HLS-VI\.(?P<sensor>S30|L30)\."
        r"(?P<tile>T\d{2}[A-Z]{3})\."
        r"(?P<julian_date>\d{7})T(?P<hms>\d{6})\."
        r"v(?P<version>[\d.]+)\.NDVI\.tif$",
        flags=re.IGNORECASE,
    )

    m = pattern.search(path.name)
    if m is None:
        return None

    sensing_date = pd.to_datetime(m.group("julian_date"), format="%Y%j")

    return {
        "path": path,
        "filename": path.name,
        "sensor": m.group("sensor").upper(),
        "tile": m.group("tile").upper(),
        "date": sensing_date,
        "julian_date": m.group("julian_date"),
        "hms": m.group("hms"),
    }


def build_manifest(hls_dir: Path, year: int | None = None) -> pd.DataFrame:
    """Find .NDVI.tif files and parse dates/tiles."""
    ndvi_files = sorted(hls_dir.rglob("*.NDVI.tif"))

    if not ndvi_files:
        raise FileNotFoundError(
            f"No .NDVI.tif files found in {hls_dir}. "
            "Make sure you downloaded/extracted the HLS-VI NDVI files."
        )

    records = []
    skipped = []
    for path in ndvi_files:
        rec = parse_hls_ndvi_filename(path)
        if rec is None:
            skipped.append(path.name)
            continue
        records.append(rec)

    if not records:
        raise ValueError(
            "Found .NDVI.tif files, but none matched the expected HLS-VI filename pattern.\n"
            f"Example skipped filenames: {skipped[:10]}"
        )

    manifest = pd.DataFrame(records)

    if year is not None:
        manifest = manifest[manifest["date"].dt.year == year].copy()

    if manifest.empty:
        raise ValueError(f"No parsed NDVI files remain after filtering to year={year}.")

    return manifest.sort_values(["date", "tile", "filename"]).reset_index(drop=True)


def filter_to_intersecting_files(
    manifest: pd.DataFrame,
    target_boundary: gpd.GeoDataFrame,
) -> pd.DataFrame:
    """Keep only rasters whose spatial bounds intersect the target boundary."""
    keep_records = []

    for _, row in manifest.iterrows():
        path = row["path"]
        try:
            with rasterio.open(path) as src:
                raster_bounds = box(*src.bounds)
                raster_bounds_gdf = gpd.GeoDataFrame(
                    {"filename": [path.name]},
                    geometry=[raster_bounds],
                    crs=src.crs,
                )

                boundary_proj = target_boundary.to_crs(src.crs)
                target_geom = get_union_geometry(boundary_proj)
                intersects = bool(raster_bounds_gdf.intersects(target_geom).iloc[0])

                rec = row.to_dict()
                rec.update({
                    "raster_crs": str(src.crs),
                    "raster_left": src.bounds.left,
                    "raster_bottom": src.bounds.bottom,
                    "raster_right": src.bounds.right,
                    "raster_top": src.bounds.top,
                    "intersects_target": intersects,
                })
                keep_records.append(rec)
        except Exception as e:
            rec = row.to_dict()
            rec.update({
                "raster_crs": None,
                "intersects_target": False,
                "read_error": str(e),
            })
            keep_records.append(rec)

    overlap = pd.DataFrame(keep_records)
    overlap = overlap[overlap["intersects_target"]].copy()

    if overlap.empty:
        raise ValueError(
            "No NDVI rasters intersect the target boundary. "
            "Check that the boundary file and raster files are for the same region."
        )

    return overlap.sort_values(["date", "tile", "filename"]).reset_index(drop=True)


def compute_daily_mean_for_date(
    date: pd.Timestamp,
    group: pd.DataFrame,
    target_boundary: gpd.GeoDataFrame,
) -> dict:
    """Mosaic all same-date tiles, clip to target boundary, and compute mean NDVI."""
    paths = list(group["path"])

    with ExitStack() as stack:
        srcs = [stack.enter_context(rasterio.open(path)) for path in paths]

        crs_set = {str(src.crs) for src in srcs}
        if len(crs_set) != 1:
            raise ValueError(
                f"Date {date.date()} has rasters in multiple CRS: {crs_set}. "
                "For Shanghai this should usually not happen. "
                "If it happens for larger provinces, reproject tiles before mosaicking."
            )

        crs = srcs[0].crs
        target_proj = target_boundary.to_crs(crs)
        geoms = list(target_proj.geometry)

        # Mosaic same-date tiles. Overlapping pixels are taken from the first valid source.
        mosaic, out_transform = merge(srcs, nodata=FILL_VALUE)

        profile = srcs[0].profile.copy()
        profile.update({
            "height": mosaic.shape[1],
            "width": mosaic.shape[2],
            "transform": out_transform,
            "nodata": FILL_VALUE,
            "count": 1,
        })

        # Clip the mosaic to the target province boundary.
        with MemoryFile() as memfile:
            with memfile.open(**profile) as dataset:
                dataset.write(mosaic)
                clipped, _ = mask(
                    dataset,
                    geoms,
                    crop=True,
                    filled=False,
                    nodata=FILL_VALUE,
                )

    raw = np.ma.array(clipped[0], dtype="float32")

    # HLS-VI fill value.
    raw = np.ma.masked_equal(raw, FILL_VALUE)

    # Apply HLS-VI scale factor.
    ndvi = raw * SCALE_FACTOR

    # Remove impossible values and any remaining invalid pixels.
    ndvi = np.ma.masked_invalid(ndvi)
    ndvi = np.ma.masked_outside(ndvi, -1, 1)

    n_valid_pixels = int(ndvi.count())

    if n_valid_pixels == 0:
        mean_ndvi = np.nan
        sd_ndvi = np.nan
    else:
        mean_ndvi = float(ndvi.mean())
        sd_ndvi = float(ndvi.std())

    return {
        "date": date.date().isoformat(),
        "n_tiles": len(paths),
        "tiles": ",".join(sorted(group["tile"].unique())),
        "mean_ndvi": mean_ndvi,
        "sd_ndvi": sd_ndvi,
        "n_valid_pixels": n_valid_pixels,
        "files": "|".join([p.name for p in paths]),
    }


def compute_ndvi(
    hls_dir: Path,
    boundary_file: Path,
    province: str,
    out_dir: Path,
    year: int | None = None,
    name_col: str | None = None,
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    """Run the full workflow."""
    out_dir.mkdir(parents=True, exist_ok=True)

    target_boundary = select_target_boundary(boundary_file, province, name_col=name_col)
    manifest = build_manifest(hls_dir, year=year)

    raw_manifest_path = out_dir / f"{province}_raw_ndvi_manifest.csv"
    manifest.assign(path=manifest["path"].astype(str)).to_csv(raw_manifest_path, index=False)

    print(f"\nFound {len(manifest)} NDVI files after year filtering.")
    print(f"Distinct dates before spatial filtering: {manifest['date'].nunique()}")

    overlap = filter_to_intersecting_files(manifest, target_boundary)

    overlap_path = out_dir / f"{province}_intersecting_ndvi_manifest.csv"
    overlap.assign(path=overlap["path"].astype(str)).to_csv(overlap_path, index=False)

    print(f"Kept {len(overlap)} NDVI files intersecting {province}.")
    print(f"Distinct dates after spatial filtering: {overlap['date'].nunique()}")

    daily_records = []
    for date, group in overlap.groupby("date"):
        print(f"Processing {date.date()} with {len(group)} tile(s): {sorted(group['tile'].unique())}")
        daily_records.append(compute_daily_mean_for_date(date, group, target_boundary))

    daily = pd.DataFrame(daily_records).sort_values("date").reset_index(drop=True)
    daily = daily.dropna(subset=["mean_ndvi"]).copy()

    if daily.empty:
        raise ValueError("All daily means are missing after masking. Check files/boundary/cloud filters.")

    equal_day_mean = float(daily["mean_ndvi"].mean())
    pixel_weighted_mean = float(
        np.average(daily["mean_ndvi"], weights=daily["n_valid_pixels"])
    )

    summary = pd.DataFrame([{
        "province": province,
        "year": year if year is not None else "all",
        "n_valid_dates": int(len(daily)),
        "n_ndvi_files_used": int(len(overlap)),
        "mean_ndvi_equal_day": equal_day_mean,
        "mean_ndvi_pixel_weighted": pixel_weighted_mean,
        "total_valid_pixel_observations": int(daily["n_valid_pixels"].sum()),
        "min_daily_ndvi": float(daily["mean_ndvi"].min()),
        "max_daily_ndvi": float(daily["mean_ndvi"].max()),
    }])

    safe_province = re.sub(r"[^A-Za-z0-9_-]+", "_", province)
    year_part = str(year) if year is not None else "all_years"

    daily_path = out_dir / f"{safe_province}_daily_ndvi_{year_part}.csv"
    summary_path = out_dir / f"{safe_province}_annual_ndvi_{year_part}.csv"

    daily.to_csv(daily_path, index=False)
    summary.to_csv(summary_path, index=False)

    print("\nSaved outputs:")
    print(f"  Raw manifest:          {raw_manifest_path}")
    print(f"  Intersecting manifest: {overlap_path}")
    print(f"  Daily NDVI:            {daily_path}")
    print(f"  Annual summary:        {summary_path}")

    print("\nAnnual summary:")
    print(summary.to_string(index=False))

    return daily, summary, overlap


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--hls-dir", required=True, type=Path, help="Folder containing HLS-VI .tif files.")
    parser.add_argument("--boundary-file", required=True, type=Path, help="ADM1 GeoJSON/Shapefile boundary file.")
    parser.add_argument("--province", default="Shanghai", help="Province/municipality name to extract.")
    parser.add_argument("--year", default=2018, type=int, help="Year to keep, e.g. 2018.")
    parser.add_argument("--out-dir", default=Path("ndvi_outputs"), type=Path, help="Output folder.")
    parser.add_argument("--name-col", default=None, help="Optional province-name column in boundary file.")
    args = parser.parse_args()

    compute_ndvi(
        hls_dir=args.hls_dir,
        boundary_file=args.boundary_file,
        province=args.province,
        out_dir=args.out_dir,
        year=args.year,
        name_col=args.name_col,
    )


if __name__ == "__main__":
    main()
