"""Turns workshop/steam_description.bbcode into a self-contained HTML preview (images embedded) in a purple Steam-like page.
Run: python tools/workshop/preview.py images_dir out.html
"""

import base64
import html
import re
import sys
from pathlib import Path

SRC = Path(__file__).resolve().parent.parent.parent / "workshop" / "steam_description.bbcode"


def convert(text, images):
    def img(m):
        name = m.group(1)
        path = images / name
        if not path.exists():
            return f"[missing {name}]"
        data = base64.b64encode(path.read_bytes()).decode()
        return f'<img src="data:image/png;base64,{data}" alt="">'

    text = html.escape(text, quote=False)
    text = re.sub(r"\[img\]\{\{(.+?)\}\}\[/img\]", img, text)
    simple = {"h1": "h1", "h2": "h2", "h3": "h3", "b": "b", "i": "i", "u": "u", "list": "ul", "olist": "ol",
              "table": "table", "tr": "tr", "th": "th", "td": "td"}
    for tag, out in simple.items():
        text = text.replace(f"[{tag}]", f"<{out}>").replace(f"[/{tag}]", f"</{out}>")
    text = text.replace("[*]", "<li>")
    text = text.replace("[spoiler]", '<details open><summary>FAQ</summary>').replace("[/spoiler]", "</details>")
    parts = re.split(r"(<table>.*?</table>|<ul>.*?</ul>|<ol>.*?</ol>)", text, flags=re.S)
    out = []
    for part in parts:
        if part.startswith(("<table>", "<ul>", "<ol>")):
            out.append(part)
        else:
            out.append(part.replace("\n", "<br>\n"))
    return "".join(out)


def main(images, out):
    body = convert(SRC.read_text(), Path(images))
    page = f"""<!doctype html><meta charset="utf-8"><title>Dazed Dank - Workshop preview</title>
<style>
body{{margin:0;background:#150a26;color:#d9c9f2;font:14px/1.55 Arial,sans-serif}}
.wrap{{max-width:1010px;margin:0 auto;padding:24px 18px 60px;background:#1f1038}}
img{{max-width:100%;display:block;margin:14px auto}}
h1{{color:#ecd9ff;font-size:26px;border-bottom:1px solid #6a3fa8;padding-bottom:6px}}
h2{{color:#ecd9ff}}h3{{color:#e0b6ff;margin:18px 0 4px}}
b{{color:#fff}}table{{border-collapse:collapse;width:100%;margin:12px 0}}
th{{background:#3b1d63;color:#fff;text-align:left}}th,td{{border:1px solid #4a2a7a;padding:6px 9px;vertical-align:top}}
tr:nth-child(even) td{{background:#27134a}}li{{margin:4px 0}}details{{background:#27134a;padding:8px 12px;border-radius:6px}}
</style><div class="wrap">{body}</div>"""
    Path(out).write_text(page)
    print("wrote", out, len(page) // 1024, "KB")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
