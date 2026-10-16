#!/usr/bin/env python3
"""Author a drawio diagram from Python, then render it with the drawio CLI.

drawio files are plain mxGraphModel XML, so a diagram is just a list of boxes
and edges. Setting math="1" on the model turns on MathJax, which is what lets a
label carry real LaTeX and still export as sharp vector text.

Math delimiters in a label, all three tested:

    \\( ... \\)   inline, stays on the line with the surrounding words
    $$ ... $$   display, renders as its own centred block and breaks the line
    $ ... $     not recognised, prints literally

So use \\(...\\) unless you actually want the formula on its own line.

Use it as a library:

    from drawio_build import Diagram
    d = Diagram("bptt", width=1180, height=330)
    a = d.box(40, 40, 90, 46, "$h_1$", fill=BLUE)
    b = d.box(190, 40, 90, 46, "$h_2$", fill=BLUE)
    d.edge(a, b, "$W_h$")
    d.render("/path/to/images/bptt.png", scale=3)

Colours match lectures/*/make-figures.py so generated diagrams and generated
plots sit on a slide together without clashing.
"""

import html
import os
import subprocess
import tempfile
from pathlib import Path

INK = "#2c3e50"
GREEN = "#1c7a3e"
RED = "#a8281f"
BLUE = "#2980b9"
ORANGE = "#e08a1e"
PURPLE = "#7b4397"
GRAY = "#7f8c8d"

DRAWIO = Path("/mnt/c/Program Files/draw.io/draw.io.exe")


def _wsl_distro():
    """Name of the running distro, for building \\\\wsl.localhost paths."""
    return os.environ.get("WSL_DISTRO_NAME", "Ubuntu")


def _tint(hex_colour, amount=0.88):
    """Lighten a colour towards white, for fills under dark text."""
    r, g, b = (int(hex_colour[i:i + 2], 16) for i in (1, 3, 5))
    f = lambda c: round(c + (255 - c) * amount)
    return f"#{f(r):02x}{f(g):02x}{f(b):02x}"


def _win(p):
    """WSL path -> a path the Windows drawio binary can open.

    /mnt/c/a/b          -> C:\\a\\b
    /home/ben/a/b       -> \\\\wsl.localhost\\<distro>\\home\\ben\\a\\b
    """
    parts = Path(p).resolve().parts
    if len(parts) > 2 and parts[1] == "mnt" and len(parts[2]) == 1:
        return parts[2].upper() + ":\\" + "\\".join(parts[3:])
    return f"\\\\wsl.localhost\\{_wsl_distro()}\\" + "\\".join(parts[1:])


class Diagram:
    def __init__(self, name, width=1000, height=400, font=15):
        self.name = name
        self.width = width
        self.height = height
        self.font = font
        self.cells = []
        self._n = 0

    def _id(self):
        self._n += 1
        return f"c{self._n}"

    def box(self, x, y, w, h, label="", fill=BLUE, stroke=None, font=None,
            rounded=1, dashed=False, opacity=100, bold=False,
            align="center", mono=False):
        """A rectangle. fill is a palette colour; it gets tinted automatically.

        Labels are always XML-escaped. Because every shape carries html=1,
        drawio un-escapes the attribute and then renders the result as HTML, so
        `<b>x</b>` in the label works and arrives as bold. To show a literal
        angle bracket, write the entity yourself: `&lt;pad&gt;` survives the
        round trip and renders as <pad>.
        """
        i = self._id()
        style = (
            f"rounded={rounded};whiteSpace=wrap;html=1;align={align};"
            f"fillColor={_tint(fill)};strokeColor={stroke or fill};strokeWidth=2;"
            f"fontColor={INK};fontSize={font or self.font};"
            f"fontStyle={1 if bold else 0};verticalAlign=middle;"
            f"opacity={opacity};"
            + ("fontFamily=Courier New;" if mono else "")
            + ("dashed=1;dashPattern=6 4;" if dashed else "")
        )
        self.cells.append(
            f'<mxCell id="{i}" value="{html.escape(label)}" '
            f'style="{style}" vertex="1" parent="1">'
            f'<mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry"/>'
            f"</mxCell>")
        return i

    def text(self, x, y, w, h, label, colour=None, size=None, align="center",
             bold=False):
        i = self._id()
        style = (f"text;html=1;strokeColor=none;fillColor=none;align={align};"
                 f"verticalAlign=middle;fontColor={colour or INK};"
                 f"fontSize={size or self.font};fontStyle={1 if bold else 0};")
        self.cells.append(
            f'<mxCell id="{i}" value="{html.escape(label)}" style="{style}" '
            f'vertex="1" parent="1">'
            f'<mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry"/>'
            f"</mxCell>")
        return i

    def edge(self, src, dst, label="", colour=None, width=2, dashed=False,
             curve=0.0, exit_=None, entry=None, size=None, label_pos=None):
        """Arrow from src to dst. curve bends it; negative arcs above."""
        i = self._id()
        style = (
            f"edgeStyle={'none' if not curve else 'none'};html=1;rounded=1;"
            f"strokeColor={colour or INK};strokeWidth={width};"
            f"fontColor={colour or INK};fontSize={size or self.font};"
            f"labelBackgroundColor=#ffffff;endArrow=blockThin;endFill=1;"
            + ("dashed=1;dashPattern=6 4;" if dashed else "")
            + (f"exitX={exit_[0]};exitY={exit_[1]};exitDx=0;exitDy=0;" if exit_ else "")
            + (f"entryX={entry[0]};entryY={entry[1]};entryDx=0;entryDy=0;" if entry else "")
            + (f"curved=1;" if curve else "")
        )
        geo = '<mxGeometry relative="1" as="geometry">'
        if curve:
            geo += (f'<Array as="points"><mxPoint x="0" y="{int(curve)}"/></Array>')
        if label_pos is not None:
            geo += f'<mxPoint as="offset" x="0" y="{label_pos}"/>'
        geo += "</mxGeometry>"
        self.cells.append(
            f'<mxCell id="{i}" value="{html.escape(label)}" style="{style}" '
            f'edge="1" parent="1" source="{src}" target="{dst}">{geo}</mxCell>')
        return i

    def waypoint_edge(self, src, dst, points, label="", colour=None, width=2,
                      dashed=False, size=None, exit_=None, entry=None):
        """Arrow routed through explicit (x, y) waypoints, drawn curved."""
        i = self._id()
        style = (
            f"edgeStyle=none;curved=1;html=1;rounded=0;"
            f"strokeColor={colour or INK};strokeWidth={width};"
            f"fontColor={colour or INK};fontSize={size or self.font};"
            f"labelBackgroundColor=#ffffff;endArrow=blockThin;endFill=1;"
            + ("dashed=1;dashPattern=6 4;" if dashed else "")
            + (f"exitX={exit_[0]};exitY={exit_[1]};exitDx=0;exitDy=0;" if exit_ else "")
            + (f"entryX={entry[0]};entryY={entry[1]};entryDx=0;entryDy=0;" if entry else "")
        )
        pts = "".join(f'<mxPoint x="{x}" y="{y}"/>' for x, y in points)
        self.cells.append(
            f'<mxCell id="{i}" value="{html.escape(label)}" style="{style}" '
            f'edge="1" parent="1" source="{src}" target="{dst}">'
            f'<mxGeometry relative="1" as="geometry">'
            f'<Array as="points">{pts}</Array></mxGeometry></mxCell>')
        return i

    def xml(self):
        return (
            '<mxfile host="python">'
            f'<diagram id="d1" name="{self.name}">'
            f'<mxGraphModel dx="{self.width}" dy="{self.height}" grid="0" '
            f'gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" '
            f'fold="1" page="1" pageScale="1" pageWidth="{self.width}" '
            f'pageHeight="{self.height}" math="1" shadow="0">'
            "<root><mxCell id=\"0\"/><mxCell id=\"1\" parent=\"0\"/>"
            + "".join(self.cells) +
            "</root></mxGraphModel></diagram></mxfile>")

    def render(self, out, scale=3, fmt=None, border=12, source_dir=None):
        """Export with the CLI, straight to `out`.

        drawio is a Windows binary but reads and writes WSL paths through the
        \\\\wsl.localhost share, so no staging through the Windows temp
        directory is needed. The editable .drawio goes to source_dir, never
        next to the image, so an images/ folder stays images only.
        """
        out = Path(out)
        fmt = fmt or out.suffix.lstrip(".")
        out.parent.mkdir(parents=True, exist_ok=True)
        if out.exists():
            out.unlink()

        if source_dir:
            source_dir = Path(source_dir)
            source_dir.mkdir(parents=True, exist_ok=True)
            src = source_dir / f"{self.name}.drawio"
        else:
            src = Path(tempfile.gettempdir()) / f"{self.name}.drawio"
        src.write_text(self.xml(), encoding="utf-8")

        cmd = [str(DRAWIO), "--export", "--format", fmt,
               "--output", _win(out), "--border", str(border), "--crop"]
        if fmt == "png":
            cmd += ["--scale", str(scale)]
        cmd += ["--no-sandbox", _win(src)]
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        if not out.exists():
            noise = ("cache", "Gpu", "gpu", "sandbox")
            err = "\n".join(l for l in (r.stderr or "").splitlines()
                             if l.strip() and not any(n in l for n in noise))
            raise RuntimeError(f"drawio export failed for {self.name}\n{err}")

        if fmt == "png":
            from PIL import Image
            w, h = Image.open(out).size
            print(f"  {out.name:34} {w}x{h}  safe to {round(w / 1.83)}px")
        else:
            print(f"  {out.name:34} {out.stat().st_size:,} bytes")
        return out
