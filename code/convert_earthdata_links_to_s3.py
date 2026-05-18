"""
Convert NASA Earthdata HTTPS download links to AWS S3 URIs.

This is designed for Earthdata Search download scripts like:
    6973200432-download.sh

It extracts links of this form:
    https://data.lpdaac.earthdatacloud.nasa.gov/lp-prod-protected/...

and converts them to:
    s3://lp-prod-protected/...

By default, it writes:
    shanghai_all_s3.txt      = all converted S3 links
    shanghai_ndvi_s3.txt     = only links ending in .NDVI.tif
    shanghai_fmask_s3.txt    = only links ending in .Fmask.tif

Usage:
    python convert_earthdata_links_to_s3.py 6973200432-download.sh

Optional:
    python convert_earthdata_links_to_s3.py 6973200432-download.sh --out-prefix shanghai
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path


URL_PATTERN = re.compile(
    r"https://data\.lpdaac\.earthdatacloud\.nasa\.gov/[^\s'\"<>]+",
    flags=re.IGNORECASE,
)


def extract_urls(text: str) -> list[str]:
    """Extract unique Earthdata HTTPS URLs while preserving original order."""
    seen = set()
    urls = []
    for match in URL_PATTERN.finditer(text):
        url = match.group(0).strip()
        if url not in seen:
            urls.append(url)
            seen.add(url)
    return urls


def https_to_s3(url: str) -> str:
    """Convert a NASA Earthdata HTTPS URL to an S3 URI."""
    prefix = "https://data.lpdaac.earthdatacloud.nasa.gov/"
    if not url.startswith(prefix):
        raise ValueError(f"Unexpected URL format: {url}")
    return "s3://" + url[len(prefix):]


def write_lines(path: Path, lines: list[str]) -> None:
    """Write one URI per line."""
    path.write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("download_script", type=Path, help="Earthdata Search download .sh file")
    parser.add_argument("--out-prefix", default="shanghai", help="Output filename prefix")
    parser.add_argument("--out-dir", type=Path, default=Path("."), help="Output directory")
    args = parser.parse_args()

    text = args.download_script.read_text(encoding="utf-8", errors="ignore")

    urls = extract_urls(text)
    s3_links = [https_to_s3(url) for url in urls]
    s3_links = list(dict.fromkeys(s3_links))

    ndvi_links = [x for x in s3_links if x.endswith(".NDVI.tif")]
    fmask_links = [x for x in s3_links if x.endswith(".Fmask.tif")]

    args.out_dir.mkdir(parents=True, exist_ok=True)

    all_path = args.out_dir / f"{args.out_prefix}_all_s3.txt"
    ndvi_path = args.out_dir / f"{args.out_prefix}_ndvi_s3.txt"
    fmask_path = args.out_dir / f"{args.out_prefix}_fmask_s3.txt"

    write_lines(all_path, s3_links)
    write_lines(ndvi_path, ndvi_links)
    write_lines(fmask_path, fmask_links)

    print(f"Input file: {args.download_script}")
    print(f"All S3 links:   {len(s3_links):>4} -> {all_path}")
    print(f"NDVI S3 links:  {len(ndvi_links):>4} -> {ndvi_path}")
    print(f"Fmask S3 links: {len(fmask_links):>4} -> {fmask_path}")


if __name__ == "__main__":
    main()
