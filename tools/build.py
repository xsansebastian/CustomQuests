"""Builds the single installable package (Retail and Forever share it).

    python tools/build.py        # dist/CustomQuests-<version>.zip

Contains only what CustomQuests.toc loads, plus the TOC and README.
"""
import re
import shutil
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ADDON = "CustomQuests"
TOC = ROOT / f"{ADDON}.toc"


def main():
    text = TOC.read_text(encoding="utf-8")
    files = [l.strip().replace("\\", "/") for l in text.splitlines() if l.strip() and not l.startswith("#")]
    missing = [f for f in files if not (ROOT / f).is_file()]
    if missing:
        sys.exit(f"files listed in the TOC do not exist: {missing}")
    version = (re.search(r"^## Version:\s*(\S+)", text, re.M) or [None, "0"])[1]
    shutil.rmtree(ROOT / "dist", ignore_errors=True)
    (ROOT / "dist").mkdir()
    path = ROOT / "dist" / f"{ADDON}-{version}.zip"
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for f in [f"{ADDON}.toc", *files, "README.md"]:
            if (ROOT / f).is_file():
                z.write(ROOT / f, f"{ADDON}/{f}")
    print(f"{path.relative_to(ROOT)} ({len(files)} files)")


if __name__ == "__main__":
    main()
