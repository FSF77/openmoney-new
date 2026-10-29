#!/usr/bin/env python3
"""Converte MANUAL_BOAS_VINDAS.md em PDF usando Google Chrome headless (sem dependências)."""
import html, re, subprocess, sys, pathlib

root = pathlib.Path(__file__).resolve().parent.parent
src = root / "MANUAL_BOAS_VINDAS.md"
out_html = root / "tmp" / "manual.html"
out_pdf = root / "MANUAL_BOAS_VINDAS.pdf"
out_html.parent.mkdir(exist_ok=True)


def inline(t):
    t = html.escape(t, quote=False)
    t = re.sub(r"`([^`]+)`", r"<code>\1</code>", t)
    t = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", t)
    t = re.sub(r"(?<![\w*])\*(?!\s)(.+?)\*(?!\w)", r"<i>\1</i>", t)
    return t


lines = src.read_text(encoding="utf-8").splitlines()
body, i, ul, ol = [], 0, False, False


def close():
    global ul, ol
    if ul: body.append("</ul>"); ul = False
    if ol: body.append("</ol>"); ol = False


while i < len(lines):
    l = lines[i]
    if l.startswith("|"):
        close()
        rows = []
        while i < len(lines) and lines[i].startswith("|"):
            rows.append([c.strip() for c in lines[i].strip().strip("|").split("|")])
            i += 1
        body.append("<table><tr>" + "".join(f"<th>{inline(c)}</th>" for c in rows[0]) + "</tr>")
        for r in rows[2:]:
            body.append("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>")
        body.append("</table>")
        continue
    m = re.match(r"(#{1,3}) (.*)", l)
    if m:
        close(); n = len(m.group(1)); body.append(f"<h{n}>{inline(m.group(2))}</h{n}>")
    elif l.startswith("> "):
        close(); body.append(f"<blockquote>{inline(l[2:])}</blockquote>")
    elif l.startswith("---"):
        close(); body.append("<hr>")
    elif re.match(r"- ", l):
        if not ul: close(); body.append("<ul>"); ul = True
        body.append(f"<li>{inline(l[2:])}</li>")
    elif re.match(r"\d+\. ", l):
        if not ol: close(); body.append("<ol>"); ol = True
        body.append(f"<li>{inline(re.sub(r'^\d+\. ', '', l))}</li>")
    elif l.startswith("   - "):
        body.append(f"<li class='sub'>{inline(l[5:])}</li>")
    elif l.strip() == "":
        pass
    else:
        close(); body.append(f"<p>{inline(l)}</p>")
    i += 1
close()

css = """body{font-family:-apple-system,Helvetica,Arial,sans-serif;font-size:12pt;line-height:1.5;color:#222;max-width:760px;margin:auto}
h1{color:#0a7d4f}h2{color:#0a7d4f;border-bottom:2px solid #d8efe5;padding-bottom:4px;margin-top:28px;page-break-after:avoid}
h3{page-break-after:avoid}table{border-collapse:collapse;width:100%;margin:10px 0}th,td{border:1px solid #ccc;padding:6px 8px;text-align:left}
th{background:#e8f6ef}blockquote{background:#fff8e1;border-left:4px solid #f5b800;margin:10px 0;padding:8px 12px}
code{background:#eee;padding:1px 4px;border-radius:3px}li.sub{margin-left:20px}tr,li{page-break-inside:avoid}"""
out_html.write_text(f"<html><head><meta charset='utf-8'><style>{css}</style></head><body>{''.join(body)}</body></html>", encoding="utf-8")

chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
sys.exit(subprocess.call([chrome, "--headless", "--disable-gpu", "--no-pdf-header-footer",
                          f"--print-to-pdf={out_pdf}", out_html.as_uri()]))
