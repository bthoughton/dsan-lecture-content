#!/usr/bin/env python3
"""Export pages from the OneDrive drawio sources into a lecture's images/ folder.

The drawio desktop binary renders through Chrome, so LaTeX in a shape comes out
as real vector text. A --scale 3 PNG stays sharp at any size a slide can show.

    ./drawio-export.py --list transformers
    ./drawio-export.py transformers learned-word-embeddings 07-sequence-models
    ./drawio-export.py --svg transformers attention-weight-matrix 08-transformers

Page indices passed to drawio are 1-based in 27.0.9, which is why PAGES below is
built from the document order of <diagram> and then offset.
"""

import argparse
import re
import subprocess
import sys
from pathlib import Path

DRAWIO = Path("/mnt/c/Program Files/draw.io/draw.io.exe")
ROOT = Path("/mnt/c/Users/benho/OneDrive/drawio")
LECTURES = Path(__file__).resolve().parent
TMP_WIN = r"C:\Users\benho\AppData\Local\Temp\drawio-export"
TMP = Path("/mnt/c/Users/benho/AppData/Local/Temp/drawio-export")

SOURCES = {
    "transformers": "deep-learning/transformers/drawings/transformers.drawio",
    "backprop": "deep-learning/backprop/ann-matrix-notation.drawio",
    "object-detection": "computer-vision/object-detection.drawio",
    "segmentation": "computer-vision/image-segmentation.drawio",
    "cnn": "computer-vision/cnn.drawio",
    "modern-cnn": "computer-vision/modern-cnn-architectures.drawio",
    "vit": "computer-vision/vision-transformers.drawio",
    "tracking": "computer-vision/object-tracking.drawio",
    "generative": "computer-vision/generative.drawio",
    "multimodal": "computer-vision/multimodal.drawio",
}


def pages(src: Path) -> list[str]:
    xml = src.read_text(encoding="utf-8", errors="replace")
    return re.findall(r'<diagram[^>]*name="([^"]+)"', xml)


def win(p: Path) -> str:
    """/mnt/c/a/b -> C:\\a\\b"""
    parts = p.parts
    return parts[2].upper() + ":\\" + "\\".join(parts[3:])


def export(src: Path, page: str, fmt: str, scale: int, out: Path) -> Path:
    names = pages(src)
    if page not in names:
        sys.exit(f"no page {page!r} in {src.name}; try --list")
    TMP.mkdir(parents=True, exist_ok=True)
    staged = TMP / f"{page}.{fmt}"
    cmd = [
        str(DRAWIO), "--export",
        "--page-index", str(names.index(page) + 1),
        "--format", fmt,
        "--output", f"{TMP_WIN}\\{page}.{fmt}",
    ]
    if fmt == "png":
        cmd += ["--scale", str(scale)]
    cmd += ["--no-sandbox", win(src)]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=300, check=False)
    if not staged.exists():
        noise = ("cache", "gpu", "Gpu", "sandbox")
        err = "\n".join(l for l in (r.stderr or "").splitlines()
                        if l.strip() and not any(n in l for n in noise))
        sys.exit(f"drawio produced nothing for {page}\n{err}")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(staged.read_bytes())
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("source", help=f"one of {', '.join(SOURCES)}")
    ap.add_argument("page", nargs="?", help="page name inside the drawio file")
    ap.add_argument("deck", nargs="?", help="lecture dir, e.g. 07-sequence-models")
    ap.add_argument("--name", help="output filename stem (default: page name)")
    ap.add_argument("--list", action="store_true", help="list pages and exit")
    ap.add_argument("--svg", action="store_true", help="export SVG instead of PNG")
    ap.add_argument("--scale", type=int, default=3)
    a = ap.parse_args()

    src = ROOT / SOURCES[a.source]
    if a.list:
        for i, n in enumerate(pages(src), 1):
            print(f"{i:3}  {n}")
        return
    if not (a.page and a.deck):
        sys.exit("need PAGE and DECK unless --list")

    fmt = "svg" if a.svg else "png"
    out = LECTURES / a.deck / "images" / f"{a.name or a.page}.{fmt}"
    export(src, a.page, fmt, a.scale, out)

    size = ""
    if fmt == "png":
        from PIL import Image
        w, h = Image.open(out).size
        size = f"  {w}x{h}, safe up to {round(w / 1.83)}px on a slide"
    print(f"{out.relative_to(LECTURES)}{size}")


if __name__ == "__main__":
    main()
