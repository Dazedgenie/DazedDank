"""Mockup of the grow room panel window, drawn in the game's UI style, to settle the layout before coding."""

import sys
from PIL import Image, ImageDraw, ImageFont

OUT = sys.argv[1]
F = "/usr/share/fonts/opentype/noto/NotoSansCJK-%s.ttc"


def font(w, s):
    return ImageFont.truetype(F % w, s, index=0)


SC = 2  # drawn at 2x for legibility
W, H = 560 * SC, 420 * SC
BG, PANEL, LINE, TEXT, DIM = (24, 24, 28), (40, 40, 46), (72, 72, 80), (235, 235, 235), (150, 150, 158)
PURPLE, GOOD, WARN, BAD = (160, 90, 240), (110, 200, 110), (240, 190, 70), (230, 90, 80)
TABS = ["Lights", "Hydro", "Plants", "Climate", "Log"]


def frame(title, active):
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, W, 30 * SC), fill=PANEL)
    d.text((10 * SC, 15 * SC), title, font=font("Bold", 13 * SC), fill=TEXT, anchor="lm")
    d.text((W - 12 * SC, 15 * SC), "X", font=font("Bold", 13 * SC), fill=DIM, anchor="rm")
    x = 10 * SC
    for t in TABS:
        w = 80 * SC
        on = t == active
        d.rectangle((x, 34 * SC, x + w, 56 * SC), fill=PANEL if on else BG, outline=LINE)
        if on:
            d.rectangle((x, 54 * SC, x + w, 56 * SC), fill=PURPLE)
        d.text((x + w // 2, 45 * SC), t, font=font("Medium", 11 * SC), fill=TEXT if on else DIM, anchor="mm")
        x += w + 4 * SC
    d.line((0, 56 * SC, W, 56 * SC), fill=LINE)
    return img, d


def button(d, x, y, label, w=None, on=True):
    w = w or (len(label) * 6 + 14) * SC
    d.rectangle((x, y, x + w, y + 18 * SC), fill=(60, 60, 68) if on else (44, 44, 50), outline=LINE)
    d.text((x + w // 2, y + 9 * SC), label, font=font("Medium", 10 * SC), fill=TEXT if on else DIM, anchor="mm")
    return x + w + 4 * SC


def bar(d, x, y, w, frac, col):
    d.rectangle((x, y, x + w, y + 8 * SC), fill=(20, 20, 24), outline=LINE)
    d.rectangle((x + 1, y + 1, x + 1 + int((w - 2) * frac), y + 8 * SC - 1), fill=col)


def hydro():
    img, d = frame("Grow Room Panel: Flower Room (power on)", "Hydro")
    y = 64 * SC
    d.text((10 * SC, y + 9 * SC), "4 systems · 9 sites · water line attached", font=font("Medium", 11 * SC), fill=DIM, anchor="lm")
    x = 10 * SC
    y += 22 * SC
    for b in ["Top Up All", "Change All", "Dose Veg All", "Dose Bloom All", "Bleach All"]:
        x = button(d, x, y, b)
    y += 26 * SC
    heads = ["System", "Water", "Food", "Roots", ""]
    cols = [10, 150, 250, 330, 400]
    for h, c in zip(heads, cols):
        d.text((c * SC, y), h, font=font("Bold", 10 * SC), fill=DIM)
    y += 16 * SC
    d.line((10 * SC, y, W - 10 * SC, y), fill=LINE)
    rows = [("RDWC control, 2 N", "4 sites", 0.72, "58 L / 80", 0.55, "Bloom 55%", "Healthy", GOOD),
            ("Flood reservoir, 5 NE", "3 sites", 0.30, "18 L / 60", 0.10, "Bloom 10%, hungry", "Healthy", GOOD),
            ("DWC bucket, 3 W", "1 site", 0.90, "13 L / 15", 0.40, "Veg 40%", "Browning", WARN),
            ("DWC bucket, 4 W", "1 site", 0.05, "1 L / 15, stale", 0.0, "None", "Rotting 62%", BAD)]
    for name, sites, wf, wt, ff, ft, roots, rc in rows:
        y += 6 * SC
        d.text((10 * SC, y), name, font=font("Medium", 11 * SC), fill=TEXT)
        d.text((10 * SC, y + 14 * SC), sites, font=font("Regular", 9 * SC), fill=DIM)
        bar(d, 150 * SC, y + 3 * SC, 80 * SC, wf, (90, 150, 230))
        d.text((150 * SC, y + 14 * SC), wt, font=font("Regular", 9 * SC), fill=DIM)
        bar(d, 250 * SC, y + 3 * SC, 60 * SC, ff, (120, 200, 120))
        d.text((250 * SC, y + 14 * SC), ft, font=font("Regular", 9 * SC), fill=DIM)
        d.text((330 * SC, y + 8 * SC), roots, font=font("Medium", 10 * SC), fill=rc, anchor="lm")
        bx = 400 * SC
        for b in ["Top Up", "Change", "Dose", "Bleach"]:
            bx = button(d, bx, y + 1 * SC, b, 36 * SC, on=(b != "Bleach" or rc == WARN))
        y += 30 * SC
        d.line((10 * SC, y, W - 10 * SC, y), fill=(52, 52, 58))
    y += 10 * SC
    d.text((10 * SC, y), "Flood schedule: every 6 h, next in 2 h 10 m", font=font("Medium", 11 * SC), fill=TEXT)
    button(d, 300 * SC, y - 2 * SC, "Flood Now")
    button(d, 372 * SC, y - 2 * SC, "Every 4 h")
    button(d, 436 * SC, y - 2 * SC, "Every 8 h")
    d.text((10 * SC, H - 14 * SC), "Top up and dose use water and bottles you carry.", font=font("Regular", 9 * SC), fill=DIM, anchor="lm")
    return img


def lights():
    img, d = frame("Grow Room Panel: Flower Room (power on)", "Lights")
    y = 66 * SC
    d.text((10 * SC, y), "Schedule", font=font("Bold", 12 * SC), fill=TEXT)
    x = 100 * SC
    for s, on in [("24/0", False), ("18/6 veg", False), ("12/12 flower", True)]:
        w = 90 * SC
        d.rectangle((x, y - 2 * SC, x + w, y + 18 * SC), fill=PURPLE if on else (60, 60, 68), outline=LINE)
        d.text((x + w // 2, y + 8 * SC), s, font=font("Medium", 10 * SC), fill=TEXT, anchor="mm")
        x += w + 6 * SC
    y += 30 * SC
    d.text((10 * SC, y), "Lights on 06:00 to 18:00 · lights ON now · dark in 3 h 40 m", font=font("Medium", 11 * SC), fill=DIM)
    y += 24 * SC
    bx0, bx1 = 10 * SC, W - 10 * SC
    d.rectangle((bx0, y, bx1, y + 14 * SC), fill=(20, 20, 24), outline=LINE)
    d.rectangle((bx0 + (bx1 - bx0) * 6 // 24, y + 1, bx0 + (bx1 - bx0) * 18 // 24, y + 14 * SC - 1), fill=PURPLE)
    nx = bx0 + (bx1 - bx0) * 14 // 24
    d.line((nx, y - 4 * SC, nx, y + 18 * SC), fill=TEXT, width=2)
    for hr in (0, 6, 12, 18, 24):
        d.text((bx0 + (bx1 - bx0) * hr // 24, y + 22 * SC), "%02d:00" % (hr % 24), font=font("Regular", 9 * SC), fill=DIM, anchor="mm")
    y += 44 * SC
    d.text((10 * SC, y), "Lamps in this room (6)", font=font("Bold", 12 * SC), fill=TEXT)
    y += 20 * SC
    for n, state, c in [("Large pro grow lamp, 3 N", "on, powered", GOOD), ("Large pro grow lamp, 3 S", "on, powered", GOOD),
                        ("Pro grow lamp, 5 E", "on, powered", GOOD), ("Pro grow lamp, 6 E", "on, powered", GOOD),
                        ("Pro flood grow light, 1 W", "on, powered", GOOD), ("Basic grow lamp, 8 NE", "no power", BAD)]:
        d.text((10 * SC, y), n, font=font("Medium", 11 * SC), fill=TEXT)
        d.text((250 * SC, y), state, font=font("Medium", 11 * SC), fill=c)
        y += 18 * SC
    y += 8 * SC
    d.text((10 * SC, y), "Leaks", font=font("Bold", 12 * SC), fill=TEXT)
    y += 20 * SC
    d.text((10 * SC, y), "Window, 2 E: no blackout. Sun reaches the room until 20:30 in the dark hours.", font=font("Medium", 11 * SC), fill=WARN)
    y += 18 * SC
    d.text((10 * SC, y), "Door, 4 S: blackout curtain hung.", font=font("Medium", 11 * SC), fill=GOOD)
    return img


def climate():
    img, d = frame("Grow Room Panel: Flower Room (power on)", "Climate")
    y = 66 * SC
    for label, val, lo, hi, frac, col, note in [("Temperature", "24 C", "20", "26", 0.6, GOOD, "in range"),
                                                 ("Humidity", "58%", "40", "50", 0.85, WARN, "high: mold risk in flower")]:
        d.text((10 * SC, y), label, font=font("Bold", 12 * SC), fill=TEXT)
        d.text((120 * SC, y), val, font=font("Black", 14 * SC), fill=col)
        bar(d, 190 * SC, y + 6 * SC, 200 * SC, frac, col)
        d.text((190 * SC, y + 18 * SC), "target " + lo + " to " + hi, font=font("Regular", 9 * SC), fill=DIM)
        d.text((400 * SC, y + 2 * SC), note, font=font("Medium", 11 * SC), fill=col)
        y += 40 * SC
    y += 6 * SC
    d.text((10 * SC, y), "Equipment", font=font("Bold", 12 * SC), fill=TEXT)
    y += 20 * SC
    for n, st, c, btn in [("Exhaust fan, 1 N (outside wall)", "running", GOOD, "Turn off"),
                          ("Intake fan, 1 S (outside wall)", "running", GOOD, "Turn off"),
                          ("Heater, 2 E", "off, not needed", DIM, "Turn on"),
                          ("Dehumidifier, 3 W", "no power", BAD, "Turn on"),
                          ("Humidifier", "none in room", DIM, None)]:
        d.text((10 * SC, y), n, font=font("Medium", 11 * SC), fill=TEXT)
        d.text((250 * SC, y), st, font=font("Medium", 11 * SC), fill=c)
        if btn:
            button(d, 400 * SC, y - 2 * SC, btn, 60 * SC)
        y += 20 * SC
    y += 8 * SC
    d.text((10 * SC, y), "Mode: Flower (auto from plants) · Drying rack found: targets conflict, move racks to their own room",
           font=font("Medium", 10 * SC), fill=WARN)
    return img


def plants():
    img, d = frame("Grow Room Panel: Flower Room (power on)", "Plants")
    y = 64 * SC
    d.text((10 * SC, y), "9 plants · 7 flowering · 2 ripe · nearest harvest: now", font=font("Medium", 11 * SC), fill=DIM)
    y += 20 * SC
    for h, c in zip(["Plant", "Stage", "Water", "Status (Agriculture 4)"], [10, 170, 260, 340]):
        d.text((c * SC, y), h, font=font("Bold", 10 * SC), fill=DIM)
    y += 16 * SC
    d.line((10 * SC, y, W - 10 * SC, y), fill=LINE)
    rows = [("Indica, RDWC site 2 N", "Ripe", 0.6, "Harvest window open", GOOD), ("Indica, RDWC site 3 N", "Ripe", 0.6, "Harvest window open", GOOD),
            ("Sativa, flood table 5 NE", "Flower, 2 d", 0.3, "Dry rockwool, hungry", WARN),
            ("Sativa, flood table 6 NE", "Flower, 2 d", 0.3, "Dry rockwool", WARN),
            ("Hybrid, DWC 3 W", "Flower, 5 d", 0.9, "Root rot: browning", WARN),
            ("Hybrid, DWC 4 W", "Flower, 5 d", 0.1, "Root rot, no water", BAD),
            ("Unknown, ground 7 S", "Flowering", 0.5, "Agriculture 7 to see more", DIM)]
    for n, st, wf, note, c in rows:
        y += 6 * SC
        d.text((10 * SC, y), n, font=font("Medium", 11 * SC), fill=TEXT)
        d.text((170 * SC, y), st, font=font("Medium", 11 * SC), fill=TEXT)
        bar(d, 260 * SC, y + 4 * SC, 60 * SC, wf, (90, 150, 230))
        d.text((340 * SC, y), note, font=font("Medium", 11 * SC), fill=c)
        y += 20 * SC
    d.text((10 * SC, H - 14 * SC), "Shows what Inspect would show at your Agriculture level.", font=font("Regular", 9 * SC), fill=DIM, anchor="lm")
    return img


for name, fn in [("hydro", hydro), ("lights", lights), ("climate", climate), ("plants", plants)]:
    fn().save(OUT + "/panel_" + name + ".png")
