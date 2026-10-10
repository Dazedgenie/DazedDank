"""Helpers for the Steam Workshop upload workflow (.github/workflows/workshop-upload.yml).

  python3 steam_upload.py vdf <repo dir> <out.vdf> <change note file> [--no-description] [--no-preview]
      Writes the workshop_build_item VDF from workshop.txt. Visibility is left out, so the
      item keeps whatever visibility it already has on Steam.
  python3 steam_upload.py code
      Prints a Steam Guard code from the STEAM_SHARED_SECRET environment variable."""

import base64
import hashlib
import hmac
import os
import struct
import sys
import time

APP_ID = "108600"  # Project Zomboid


def read_workshop_txt(path):
    """Parse workshop.txt into a dict; description lines are joined with newlines."""
    info, desc = {}, []
    with open(path, encoding="utf-8") as f:
        for line in f.read().splitlines():
            key, sep, value = line.partition("=")
            if not sep:
                continue
            if key == "description":
                desc.append(value)
            else:
                info[key] = value
    info["description"] = "\n".join(desc)
    return info


def vdf_str(s):
    """Quote a string for a VDF file. SteamCMD's parser ignores backslash escapes, so straight
    double quotes inside the text become curly ones instead of ending the string."""
    parts = s.split('"')
    out = parts[0]
    for i, part in enumerate(parts[1:]):
        out += ("\u201c" if i % 2 == 0 else "\u201d") + part
    return '"' + out + '"'


def write_vdf(repo, out, note_file, with_description):
    info = read_workshop_txt(os.path.join(repo, "workshop.txt"))
    item_id = (info.get("id") or info.get("workshopid") or "").strip()
    if not item_id.isdigit() or item_id == "0":
        sys.exit("workshop.txt has no workshopid; publish the item from the game once first.")
    content = os.path.join(repo, "Contents")
    preview = os.path.join(repo, "preview.png")
    mods = os.path.join(content, "mods")
    if not any(os.path.isfile(os.path.join(mods, m, "42", "mod.info")) for m in os.listdir(mods)):
        sys.exit("No Contents/mods/<mod>/42/mod.info found; refusing to upload an empty item.")
    with open(note_file, encoding="utf-8") as f:
        note = f.read().strip() or "Update"
    fields = [
        ("appid", APP_ID),
        ("publishedfileid", item_id),
        ("contentfolder", content),
        ("changenote", note),
    ]
    if os.path.isfile(preview) and "--no-preview" not in sys.argv:
        fields.append(("previewfile", preview))
    if with_description:
        fields.append(("title", info.get("title", "")))
        fields.append(("description", info["description"]))
    lines = ['"workshopitem"', "{"]
    lines += ["\t%s\t\t%s" % (vdf_str(k), vdf_str(v)) for k, v in fields]
    lines.append("}")
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print("Item %s, content %s, description %s, note: %s"
          % (item_id, content, "updated" if with_description else "unchanged", note.splitlines()[0]))


def guard_code(secret, t=None):
    """Steam Guard mobile authenticator code (same algorithm as the Steam app)."""
    counter = int((t or time.time()) // 30)
    digest = hmac.new(base64.b64decode(secret), struct.pack(">Q", counter), hashlib.sha1).digest()
    start = digest[-1] & 0x0F
    value = struct.unpack(">I", digest[start:start + 4])[0] & 0x7FFFFFFF
    chars = "23456789BCDFGHJKMNPQRTVWXY"
    code = ""
    for _ in range(5):
        code += chars[value % len(chars)]
        value //= len(chars)
    return code


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "vdf":
        write_vdf(sys.argv[2], sys.argv[3], sys.argv[4], "--no-description" not in sys.argv)
    elif cmd == "code":
        print(guard_code(os.environ["STEAM_SHARED_SECRET"]))
    else:
        sys.exit(__doc__)
