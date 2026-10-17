"""Helpers for the Steam Workshop upload workflow (.github/workflows/workshop-upload.yml).

  python3 steam_upload.py vdf <repo dir> <out.vdf> <change note file> [--no-description] [--no-preview] [--set-visibility] [--create]
      Writes the workshop_build_item VDF from workshop.txt. Visibility is left out (the item
      keeps what it has on Steam) unless --set-visibility applies workshop.txt's visibility=.
      --create makes a new Workshop item when workshop.txt has no id (title, description and
      visibility are sent with it).
  python3 steam_upload.py code
      Prints a Steam Guard code from the STEAM_SHARED_SECRET environment variable."""

import base64
import fnmatch
import hashlib
import hmac
import os
import shutil
import struct
import sys
import time

APP_ID = "108600"  # Project Zomboid
# Never uploaded: developer files that sit inside Contents/ in some repos (tools, tests, scripts, docs,
# caches) and the staff-only *Test mods. LICENSE and NOTICE files ship; README and the like do not.
SKIP_DIRS = {"tools", "tests", "test", "__pycache__", ".git", ".github", "docs"}
SKIP_FILES = ["*.py", "*.pyc", "*.whl", "*.sh", "*.bat", "*.md", "*.blend", "*.blend1", "*.psd", "*.xcf",
              "*.zip", "*.7z", ".DS_Store", "Thumbs.db", "*.log"]
KEEP_FILES = ["NOTICE*", "LICENSE*", "LICENCE*"]
# workshop.txt visibility= values to Steam's numbers.
VISIBILITY = {"public": "0", "friends": "1", "friendsonly": "1", "private": "2", "hidden": "2", "unlisted": "3"}


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


def skipped(rel_dir, name, is_dir):
    """Is this entry (relative dir inside Contents/, entry name) left out of the upload?"""
    if is_dir:
        if name in SKIP_DIRS:
            return True
        # Contents/mods/<Something>Test is a staff or debug test mod: never on Steam.
        return rel_dir == "mods" and name.endswith("Test")
    if any(fnmatch.fnmatch(name, k) for k in KEEP_FILES):
        return False
    return any(fnmatch.fnmatch(name, k) for k in SKIP_FILES)


def stage_contents(repo, staging):
    """Copy Contents/ to the staging folder without the developer files, and report what was left out."""
    src = os.path.join(repo, "Contents")
    if os.path.isdir(staging):
        shutil.rmtree(staging)
    left_out = []
    for cur, dirs, files in os.walk(src):
        rel = os.path.relpath(cur, src)
        rel = "" if rel == "." else rel
        keep_dirs = []
        for d in sorted(dirs):
            if skipped(rel, d, True):
                left_out.append(os.path.join(rel, d) + "/")
            else:
                keep_dirs.append(d)
        dirs[:] = keep_dirs
        os.makedirs(os.path.join(staging, rel), exist_ok=True)
        for f in sorted(files):
            if skipped(rel, f, False):
                left_out.append(os.path.join(rel, f))
            else:
                shutil.copy2(os.path.join(cur, f), os.path.join(staging, rel, f))
    if left_out:
        print("Left out of the upload (%d):" % len(left_out))
        for item in left_out[:60]:
            print("  " + item)
        if len(left_out) > 60:
            print("  ... and %d more" % (len(left_out) - 60))
    return staging


def write_vdf(repo, out, note_file, with_description):
    info = read_workshop_txt(os.path.join(repo, "workshop.txt"))
    item_id = (info.get("id") or info.get("workshopid") or "").strip()
    if not item_id.isdigit() or item_id == "0":
        if "--create" not in sys.argv:
            sys.exit("workshop.txt has no id; publish the item once first (or upload with --create).")
        # Steam makes a new item; title, description and visibility must come with it.
        item_id = "0"
        with_description = True
        if "--set-visibility" not in sys.argv:
            sys.argv.append("--set-visibility")
    source = os.path.join(repo, "Contents")
    preview = os.path.join(repo, "preview.png")
    mods = os.path.join(source, "mods")
    if not any(os.path.isfile(os.path.join(mods, m, "42", "mod.info")) for m in os.listdir(mods)):
        sys.exit("No Contents/mods/<mod>/42/mod.info found; refusing to upload an empty item.")
    content = stage_contents(repo, os.path.join(os.path.dirname(os.path.abspath(out)), "upload-contents"))
    staged_mods = os.path.join(content, "mods")
    if not os.path.isdir(staged_mods) or not any(
            os.path.isfile(os.path.join(staged_mods, m, "42", "mod.info")) for m in os.listdir(staged_mods)):
        sys.exit("The staged upload holds no mod; check SKIP_DIRS in steam_upload.py.")
    with open(note_file, encoding="utf-8") as f:
        note = f.read().strip() or "Update"
    fields = [
        ("appid", APP_ID),
        ("publishedfileid", item_id),
    ]
    # --page-only leaves the uploaded mod files as they are and changes just the page.
    if "--page-only" not in sys.argv:
        fields += [("contentfolder", content), ("changenote", note)]
    if os.path.isfile(preview) and "--no-preview" not in sys.argv:
        fields.append(("previewfile", preview))
    if "--set-visibility" in sys.argv:
        vis = info.get("visibility", "").strip().lower()
        if vis not in VISIBILITY:
            sys.exit("workshop.txt visibility=%r is not one of %s" % (vis, ", ".join(VISIBILITY)))
        fields.append(("visibility", VISIBILITY[vis]))
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
