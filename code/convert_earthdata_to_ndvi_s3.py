"""
Batch-convert NASA Earthdata download .sh files to NDVI-only S3 manifest files.

Scans a folder for Earthdata Search download scripts (*.sh), extracts NASA
Earthdata HTTPS links, converts them to AWS S3 URIs, filters to .NDVI.tif only,
and writes one NDVI-only S3 manifest per .sh file.

Default input folder:
    C:\\Users\\26540\\Desktop\\学习\\Uchicago\\final-project-greenness-infrastructure-happiness\\satellite_data

Basic usage:
    python batch_convert_earthdata_sh_to_ndvi_s3.py

Optional output folder:
    python batch_convert_earthdata_sh_to_ndvi_s3.py --out-dir ndvi_manifests

Recursive search:
    python batch_convert_earthdata_sh_to_ndvi_s3.py --recursive

Also write one combined NDVI manifest:
    python batch_convert_earthdata_sh_to_ndvi_s3.py --write-combined
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path


DEFAULT_INPUT_DIR = Path(
    r"C:\Users\26540\Desktop\学习\Uchicago\final-project-greenness-infrastructure-happiness\satellite_data"
)

URL_PATTERN = re.compile(
    r"https://data\.lpdaac\.earthdatacloud\.nasa\.gov/[^\s'\"<>]+",
    flags=re.IGNORECASE,
)


def extract_urls(text: str) -> list[str]:
    """Extract unique Earthdata HTTPS URLs while preserving original order."""
    seen = set()
    urls = []

    for match in URL_PATTERN.finditer(text):
        url = match.group(0).strip().rstrip(");,")
        if url not in seen:
            urls.append(url)
            seen.add(url)

    return urls


def https_to_s3(url: str) -> str:
    """Convert NASA Earthdata HTTPS URL to S3 URI."""
    prefix = "https://data.lpdaac.earthdatacloud.nasa.gov/"
    if not url.startswith(prefix):
        raise ValueError(f"Unexpected URL format: {url}")
    return "s3://" + url[len(prefix):]


def write_lines(path: Path, lines: list[str]) -> None:
    """Write one URI per line using Unix line endings."""
    path.write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8", newline="\n")


def safe_stem(path: Path) -> str:
    """Create a safe output stem from the shell-script filename."""
    return re.sub(r"[^A-Za-z0-9._-]+", "_", path.stem)


def convert_one(download_script: Path, out_dir: Path) -> tuple[Path, int]:
    """Convert one Earthdata .sh file to one NDVI-only S3 manifest."""
    text = download_script.read_text(encoding="utf-8", errors="ignore")

    urls = extract_urls(text)
    s3_links = [https_to_s3(url) for url in urls]
    s3_links = list(dict.fromkeys(s3_links))

    ndvi_links = [link for link in s3_links if link.endswith(".NDVI.tif")]

    out_path = out_dir / f"{safe_stem(download_script)}_ndvi_s3.txt"
    write_lines(out_path, ndvi_links)

    return out_path, len(ndvi_links)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--input-dir",
        type=Path,
        default=DEFAULT_INPUT_DIR,
        help="Folder containing Earthdata .sh files.",
    )
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=None,
        help="Folder for *_ndvi_s3.txt outputs. Default: same as --input-dir.",
    )
    parser.add_argument(
        "--recursive",
        action="store_true",
        help="Search recursively for .sh files.",
    )
    parser.add_argument(
        "--write-combined",
        action="store_true",
        help="Also write combined_ndvi_s3.txt with unique NDVI links from all .sh files.",
    )
    parser.add_argument(
        "--combined-name",
        default="combined_ndvi_s3.txt",
        help="Name of combined manifest if --write-combined is used.",
    )
    args = parser.parse_args()

    input_dir = args.input_dir
    out_dir = args.out_dir if args.out_dir is not None else input_dir

    if not input_dir.exists():
        raise FileNotFoundError(f"Input directory does not exist: {input_dir}")
    if not input_dir.is_dir():
        raise NotADirectoryError(f"Input path is not a directory: {input_dir}")

    out_dir.mkdir(parents=True, exist_ok=True)

    pattern = "**/*.sh" if args.recursive else "*.sh"
    sh_files = sorted(input_dir.glob(pattern))

    if not sh_files:
        raise FileNotFoundError(
            f"No .sh files found in {input_dir}. Use --recursive if they are in subfolders."
        )

    print(f"Input directory:  {input_dir}")
    print(f"Output directory: {out_dir}")
    print(f"Recursive search: {args.recursive}")
    print(f"Found .sh files:  {len(sh_files)}")
    print()

    combined = []
    total = 0

    for sh_file in sh_files:
        out_path, n = convert_one(sh_file, out_dir)
        total += n
        if n > 0:
            combined.extend(out_path.read_text(encoding="utf-8").splitlines())

        print(f"{sh_file.name}")
        print(f"  NDVI links: {n}")
        print(f"  Output:     {out_path}")
        print()

    if args.write_combined:
        combined = list(dict.fromkeys(combined))
        combined_path = out_dir / args.combined_name
        write_lines(combined_path, combined)
        print("Combined NDVI manifest:")
        print(f"  Unique NDVI links: {len(combined)}")
        print(f"  Output:            {combined_path}")
        print()

    print("Done.")
    print(f"Total NDVI links across per-file outputs: {total}")


if __name__ == "__main__":
    main()
