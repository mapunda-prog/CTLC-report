#!/usr/bin/env python3
"""Build templates/reference.docx -- the Word style carrier for Quarto.

BUILD-TIME ONLY. The report pipeline is pure R + Quarto; this script exists
because Word headers and footers cannot be expressed in Markdown and officer
can only replace text in headers that already exist, not create them.

Run it only when the letterhead, fonts or footer need to change:

    python3 tools/make_reference_docx.py

then commit the regenerated templates/reference.docx.

Quarto's docx writer copies the styles, headers and footers out of this file
and applies them to every rendered report, so the MoH letterhead and the
"Page X of Y" footer appear on all pages without the template knowing.
"""

import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    yaml = None

from docx import Document
from docx.enum.text import WD_PARAGRAPH_ALIGNMENT
from docx.enum.style import WD_STYLE_TYPE
from docx.shared import Pt, Inches
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

ROOT = Path(__file__).resolve().parent.parent
EMBLEM = ROOT / "templates" / "emblem.jpg"
OUT = ROOT / "templates" / "reference.docx"

FALLBACK = {
    "ministry": "MINISTRY OF HEALTH",
    "title": "HIV DRUG RESISTANCE REPORT FORM",
    "effective_date": "25/07/2022",
    "revision_no": "0",
}


def load_form_config():
    """Read the form block from config.yml, falling back to defaults."""
    cfg_path = ROOT / "config.yml"
    if yaml is None or not cfg_path.exists():
        return FALLBACK
    with cfg_path.open(encoding="utf-8") as fh:
        cfg = yaml.safe_load(fh) or {}
    form = cfg.get("form") or {}
    return {k: form.get(k, v) for k, v in FALLBACK.items()}


def style_run(run, size=12, bold=False):
    run.font.name = "Times New Roman"
    run.font.size = Pt(size)
    run.bold = bold
    # python-docx sets the Latin font only; set the East Asian slot too so
    # Word does not silently substitute a different face.
    run._element.rPr.rFonts.set(qn("w:eastAsia"), "Times New Roman")


def add_field(paragraph, instruction):
    """Append a Word field code (PAGE, NUMPAGES) that Word evaluates on open."""
    fld = OxmlElement("w:fldSimple")
    fld.set(qn("w:instr"), instruction)
    run = OxmlElement("w:r")
    rpr = OxmlElement("w:rPr")
    fonts = OxmlElement("w:rFonts")
    fonts.set(qn("w:ascii"), "Times New Roman")
    fonts.set(qn("w:hAnsi"), "Times New Roman")
    rpr.append(fonts)
    size = OxmlElement("w:sz")
    size.set(qn("w:val"), "20")  # half-points: 20 = 10pt
    rpr.append(size)
    run.append(rpr)
    fld.append(run)
    paragraph._p.append(fld)


def set_base_styles(doc, form):
    """Times New Roman 12pt at 1.15 spacing, and headings in the same face."""
    normal = doc.styles["Normal"]
    normal.font.name = "Times New Roman"
    normal.font.size = Pt(12)
    normal.element.rPr.rFonts.set(qn("w:eastAsia"), "Times New Roman")
    normal.paragraph_format.line_spacing = 1.15
    normal.paragraph_format.space_after = Pt(6)

    # Quarto maps markdown headings onto these built-in styles.
    for name, size in (("Heading 1", 14), ("Heading 2", 12), ("Heading 3", 12)):
        try:
            st = doc.styles[name]
        except KeyError:
            continue
        st.font.name = "Times New Roman"
        st.font.size = Pt(size)
        st.font.bold = True
        st.font.color.rgb = None
        st.element.rPr.rFonts.set(qn("w:eastAsia"), "Times New Roman")

    # Named style the template reaches for via a custom-style div. Pandoc
    # only applies it if a style of this exact name exists here.
    centered = doc.styles.add_style("Centered", WD_STYLE_TYPE.PARAGRAPH)
    centered.base_style = doc.styles["Normal"]
    centered.font.name = "Times New Roman"
    centered.font.size = Pt(12)
    centered.paragraph_format.alignment = WD_PARAGRAPH_ALIGNMENT.CENTER
    centered.paragraph_format.space_before = Pt(12)


def _border(tag, size=4, color="000000"):
    el = OxmlElement(f"w:{tag}")
    el.set(qn("w:val"), "single")
    el.set(qn("w:sz"), str(size))      # eighths of a point
    el.set(qn("w:space"), "0")
    el.set(qn("w:color"), color)
    return el


def build_table_style(doc):
    """Add the 'Table' style pandoc applies to every rendered table.

    Without this the tables land on 'Normal Table', which has no borders at
    all, so the drug results read as loose columns of text on the page.
    Ruled cells and a shaded header row keep each drug tied to its score and
    interpretation when the form is printed in black and white.
    """
    style = doc.styles.add_style("Table", WD_STYLE_TYPE.TABLE)
    style.font.name = "Times New Roman"
    style.font.size = Pt(11)

    el = style.element
    tbl_pr = OxmlElement("w:tblPr")

    borders = OxmlElement("w:tblBorders")
    for edge in ("top", "left", "bottom", "right", "insideH", "insideV"):
        borders.append(_border(edge))
    tbl_pr.append(borders)

    # A little padding so text does not touch the rules.
    margins = OxmlElement("w:tblCellMar")
    for side, width in (("top", 40), ("left", 80), ("bottom", 40), ("right", 80)):
        m = OxmlElement(f"w:{side}")
        m.set(qn("w:w"), str(width))
        m.set(qn("w:type"), "dxa")
        margins.append(m)
    tbl_pr.append(margins)
    el.append(tbl_pr)

    # Header row: bold on a light grey fill, repeated if a table splits
    # across pages.
    first_row = OxmlElement("w:tblStylePr")
    first_row.set(qn("w:type"), "firstRow")

    r_pr = OxmlElement("w:rPr")
    bold = OxmlElement("w:b")
    bold.set(qn("w:val"), "1")
    r_pr.append(bold)
    first_row.append(r_pr)

    tc_pr = OxmlElement("w:tcPr")
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"), "D9D9D9")
    tc_pr.append(shd)
    first_row.append(tc_pr)

    el.append(first_row)
    return style


def build_header(doc, form):
    header = doc.sections[0].header
    p = header.paragraphs[0]
    p.alignment = WD_PARAGRAPH_ALIGNMENT.CENTER
    style_run(p.add_run(form["ministry"]), size=12, bold=True)

    if EMBLEM.exists():
        img_p = header.add_paragraph()
        img_p.alignment = WD_PARAGRAPH_ALIGNMENT.CENTER
        img_p.add_run().add_picture(str(EMBLEM), width=Inches(0.6))
    else:
        print(f"warning: {EMBLEM} not found -- header will have no emblem",
              file=sys.stderr)

    title_p = header.add_paragraph()
    title_p.alignment = WD_PARAGRAPH_ALIGNMENT.CENTER
    style_run(title_p.add_run(form["title"]), size=12, bold=True)


def build_footer(doc, form):
    footer = doc.sections[0].footer
    p = footer.paragraphs[0]
    p.alignment = WD_PARAGRAPH_ALIGNMENT.CENTER
    style_run(
        p.add_run(
            f"Effective date: {form['effective_date']}    "
            f"Revision No. {form['revision_no']}    Page "
        ),
        size=10,
    )
    add_field(p, "PAGE")
    style_run(p.add_run(" of "), size=10)
    add_field(p, "NUMPAGES")


def main():
    form = load_form_config()
    doc = Document()
    set_base_styles(doc, form)
    build_table_style(doc)
    build_header(doc, form)
    build_footer(doc, form)

    # Pandoc reads styles from this file but discards its body content.
    # One empty paragraph keeps the document valid.
    doc.add_paragraph()

    OUT.parent.mkdir(parents=True, exist_ok=True)
    doc.save(OUT)
    print(f"wrote {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
