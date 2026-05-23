"""
Memory-optimized province/municipality-average NDVI from HLS-VI .NDVI.tif files.

Drop-in replacement for:
    compute_hls_ndvi_by_province.py

Compatible with the current SQS worker command:
    python3 compute_hls_ndvi_by_province.py \
        --hls-dir RAW_DIR \
        --boundary-file geoBoundaries-CHN-ADM1.geojson \
        --province "Xinjiang" \
        --year 2018 \
        --out-dir OUT_DIR

Why this version is better for large provinces:
1. Handles same-date tiles that span multiple CRS/UTM zones.
2. Avoids building one giant full-province mosaic in memory.
3. Processes each province-date in smaller spatial chunks.
4. Keeps the old output filenames, so the current SQS pipeline does not need to change.
5. Keeps the Guangdong boundary alias needed for the current boundary file
   where Guangdong is labeled as "Guangzhou Province".

Optional:
    --block-size 1024   # lower memory, slower
    --block-size 2048   # default
    --block-size 4096   # faster, more memory
"""

from __future__ import annotations

import argparse
import math
import re
from contextlib import ExitStack
from pathlib import Path

import geopandas as gpd
import numpy as np
import pandas as pd
import rasterio
from rasterio.features import geometry_mask
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

    # Boundary-name aliases for nonstandard labels in this ADM1 file.
    boundary_aliases = {
        "Guangdong": "Guangzhou",
    }

    search_name = province
    target = adm1[adm1[col].astype(str).str.contains(search_name, case=False, na=False)].copy()

    if target.empty and province in boundary_aliases:
        search_name = boundary_aliases[province]
        target = adm1[adm1[col].astype(str).str.contains(search_name, case=False, na=False)].copy()

    if target.empty:
        names = sorted(adm1[col].dropna().astype(str).unique().tolist())
        preview = names[:80]
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


def intersect_bounds(a: tuple[float, float, float, float], b: tuple[float, float, float, float]):
    """Return intersection bounds or None."""
    left = max(a[0], b[0])
    bottom = max(a[1], b[1])
    right = min(a[2], b[2])
    top = min(a[3], b[3])

    if left >= right or bottom >= top:
        return None

    return left, bottom, right, top


def src_bounds_union(srcs) -> tuple[float, float, float, float]:
    """Union bounds for open rasterio sources."""
    left = min(src.bounds.left for src in srcs)
    bottom = min(src.bounds.bottom for src in srcs)
    right = max(src.bounds.right for src in srcs)
    top = max(src.bounds.top for src in srcs)
    return left, bottom, right, top


def valid_ndvi_stats_from_chunk(
    arr: np.ndarray,
    transform,
    target_geom,
) -> tuple[float, float, int, int]:
    """Compute sum, sumsq, valid count, and inside-province pixel count for one chunk."""
    raw = arr[0].astype("float32", copy=False)

    inside_mask = geometry_mask(
        [target_geom],
        out_shape=raw.shape,
        transform=transform,
        invert=True,
        all_touched=False,
    )

    inside_count = int(inside_mask.sum())

    ndvi = raw * SCALE_FACTOR

    valid_mask = (
        inside_mask
        & np.isfinite(raw)
        & (raw != FILL_VALUE)
        & np.isfinite(ndvi)
        & (ndvi >= -1)
        & (ndvi <= 1)
    )

    n_valid = int(valid_mask.sum())

    if n_valid == 0:
        return 0.0, 0.0, 0, inside_count

    vals = ndvi[valid_mask].astype("float64", copy=False)
    s = float(vals.sum())
    ss = float((vals ** 2).sum())

    return s, ss, n_valid, inside_count


def iter_chunk_bounds(
    bounds: tuple[float, float, float, float],
    resx: float,
    resy: float,
    block_size: int,
):
    """Yield spatial chunk bounds over a bounding box."""
    left, bottom, right, top = bounds

    width = int(math.ceil((right - left) / resx))
    height = int(math.ceil((top - bottom) / resy))

    for row0 in range(0, height, block_size):
        y_top = top - row0 * resy
        y_bottom = max(bottom, top - min(row0 + block_size, height) * resy)

        for col0 in range(0, width, block_size):
            x_left = left + col0 * resx
            x_right = min(right, left + min(col0 + block_size, width) * resx)

            if x_left < x_right and y_bottom < y_top:
                yield (x_left, y_bottom, x_right, y_top)


def compute_daily_mean_for_date(
    date: pd.Timestamp,
    group: pd.DataFrame,
    target_boundary: gpd.GeoDataFrame,
    block_size: int = 2048,
) -> dict:
    """
    Compute daily province mean NDVI in memory-bounded chunks.

    Within each chunk and CRS, rasterio.merge(..., method='first') keeps
    mosaic-style behavior while avoiding a full province-date mosaic.
    """
    paths = list(group["path"])

    crs_to_paths: dict[str, list[Path]] = {}

    for path in paths:
        with rasterio.open(path) as src:
            crs_key = str(src.crs)
        crs_to_paths.setdefault(crs_key, []).append(path)

    total_sum = 0.0
    total_sumsq = 0.0
    total_valid_count = 0
    total_inside_count = 0

    n_chunks_processed = 0
    n_chunks_with_valid_pixels = 0
    per_crs_debug = []

    for crs_key, crs_paths in sorted(crs_to_paths.items()):
        with ExitStack() as stack:
            srcs = [stack.enter_context(rasterio.open(path)) for path in crs_paths]

            crs = srcs[0].crs
            target_proj = target_boundary.to_crs(crs)
            target_geom = get_union_geometry(target_proj)

            target_bounds = target_geom.bounds
            source_bounds = src_bounds_union(srcs)
            work_bounds = intersect_bounds(target_bounds, source_bounds)

            if work_bounds is None:
                per_crs_debug.append(f"{crs_key}:{len(crs_paths)}files:0valid:no_bounds_overlap")
                continue

            resx = abs(float(srcs[0].res[0]))
            resy = abs(float(srcs[0].res[1]))

            src_boxes = [(src, box(*src.bounds)) for src in srcs]

            crs_sum = 0.0
            crs_sumsq = 0.0
            crs_valid_count = 0
            crs_inside_count = 0
            crs_chunks = 0

            for chunk_bounds in iter_chunk_bounds(work_bounds, resx, resy, block_size):
                chunk_geom = box(*chunk_bounds)

                if not chunk_geom.intersects(target_geom):
                    continue

                chunk_srcs = [src for src, src_box in src_boxes if src_box.intersects(chunk_geom)]

                if not chunk_srcs:
                    continue

                try:
                    mosaic, out_transform = merge(
                        chunk_srcs,
                        bounds=chunk_bounds,
                        res=(resx, resy),
                        nodata=FILL_VALUE,
                        method="first",
                    )
                except Exception as e:
                    print(
                        f"WARNING: date {date.date()} CRS {crs_key} chunk {chunk_bounds} failed: {e}",
                        flush=True,
                    )
                    continue

                s, ss, n_valid, n_inside = valid_ndvi_stats_from_chunk(
                    mosaic,
                    out_transform,
                    target_geom,
                )

                crs_sum += s
                crs_sumsq += ss
                crs_valid_count += n_valid
                crs_inside_count += n_inside

                n_chunks_processed += 1
                crs_chunks += 1

                if n_valid > 0:
                    n_chunks_with_valid_pixels += 1

                del mosaic

            total_sum += crs_sum
            total_sumsq += crs_sumsq
            total_valid_count += crs_valid_count
            total_inside_count += crs_inside_count

            per_crs_debug.append(
                f"{crs_key}:{len(crs_paths)}files:{crs_valid_count}valid:{crs_chunks}chunks"
            )

    if total_valid_count == 0:
        mean_ndvi = np.nan
        sd_ndvi = np.nan
        valid_pixel_coverage = np.nan
    else:
        mean_ndvi = total_sum / total_valid_count
        variance = max(total_sumsq / total_valid_count - mean_ndvi ** 2, 0.0)
        sd_ndvi = float(np.sqrt(variance))

        if total_inside_count > 0:
            valid_pixel_coverage = float(total_valid_count / total_inside_count)
        else:
            valid_pixel_coverage = np.nan

    return {
        "date": date.date().isoformat(),
        "n_tiles": len(paths),
        "tiles": ",".join(sorted(group["tile"].unique())),
        "n_crs_groups": len(crs_to_paths),
        "crs_groups": ",".join(sorted(crs_to_paths.keys())),
        "n_chunks_processed": int(n_chunks_processed),
        "n_chunks_with_valid_pixels": int(n_chunks_with_valid_pixels),
        "mean_ndvi": float(mean_ndvi) if pd.notna(mean_ndvi) else np.nan,
        "sd_ndvi": sd_ndvi,
        "n_valid_pixels": int(total_valid_count),
        "n_inside_pixels": int(total_inside_count),
        "valid_pixel_coverage": valid_pixel_coverage,
        "per_crs_debug": "|".join(per_crs_debug),
        "files": "|".join([Path(p).name for p in paths]),
    }


def compute_ndvi(
    hls_dir: Path,
    boundary_file: Path,
    province: str,
    out_dir: Path,
    year: int | None = None,
    name_col: str | None = None,
    block_size: int = 2048,
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    """Run the full workflow."""
    if block_size < 128:
        raise ValueError("--block-size is too small. Use at least 128.")

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
    print(f"Memory-optimized block size: {block_size} pixels")

    daily_records = []
    for date, group in overlap.groupby("date"):
        print(f"Processing {date.date()} with {len(group)} tile(s): {sorted(group['tile'].unique())}", flush=True)
        daily_records.append(
            compute_daily_mean_for_date(
                date=date,
                group=group,
                target_boundary=target_boundary,
                block_size=block_size,
            )
        )

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
        "total_inside_pixel_observations": int(daily["n_inside_pixels"].sum()) if "n_inside_pixels" in daily.columns else np.nan,
        "mean_valid_pixel_coverage": float(daily["valid_pixel_coverage"].mean()) if "valid_pixel_coverage" in daily.columns else np.nan,
        "min_valid_pixel_coverage": float(daily["valid_pixel_coverage"].min()) if "valid_pixel_coverage" in daily.columns else np.nan,
        "max_valid_pixel_coverage": float(daily["valid_pixel_coverage"].max()) if "valid_pixel_coverage" in daily.columns else np.nan,
        "max_daily_crs_groups": int(daily["n_crs_groups"].max()) if "n_crs_groups" in daily.columns else 1,
        "total_chunks_processed": int(daily["n_chunks_processed"].sum()) if "n_chunks_processed" in daily.columns else np.nan,
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
    parser.add_argument(
        "--block-size",
        default=2048,
        type=int,
        help=(
            "Chunk size in pixels for memory-optimized mosaicking. "
            "Lower values use less memory but may be slower. Default: 2048."
        ),
    )
    args = parser.parse_args()

    compute_ndvi(
        hls_dir=args.hls_dir,
        boundary_file=args.boundary_file,
        province=args.province,
        out_dir=args.out_dir,
        year=args.year,
        name_col=args.name_col,
        block_size=args.block_size,
    )


if __name__ == "__main__":
    main()
