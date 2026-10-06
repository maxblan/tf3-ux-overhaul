#!/usr/bin/env python3
"""Composes the mod.io gallery: one 1920 x 1080 card per feature story, from the in-game screenshots
that `spec/ingame/run.sh --save <save> --gallery --language en [--vanilla]` takes.

Each card has the same frame: an eyebrow (the screen), a headline that names the player's gain, one
line of explanation, and the screenshots. The look is the mod's thumbnail (assets/preview.svg): the
dark blue glow, screenshots in a silver bevelled rim like its window, round silver markers like its
close button, and white with a soft glow for what to look at. The formats: before/after (same scene
without and with the mod), spotlight (the scene for context, the changed element enlarged in an
inset), storyboard (a workflow in numbered steps) and annotated overview.

Usage: tools/gallery/compose.py <screenshots dir> <out dir>
  <screenshots dir> holds gallery-mod/ and gallery-vanilla/ (spec/ingame/results)
Writes <out dir>/NN-name.svg and <out dir>/crops.txt (the regions the cards use, which build.sh cuts
into <screenshots dir>/gallery-crops/ before it renders the cards to PNG).
Regions are in screenshot pixels (3440 x 1440: the captures' screen), measured on the shots of
World#1; another savegame needs them measured again.
"""
import os
import sys
from xml.sax.saxutils import escape

W, H = 1920, 1080
MARGIN = 72
SHOT_W, SHOT_H = 3440, 1440
FONT = "Lato"
# assets/preview.svg: background glow, window bevel, window face
GLOW = ("#2a4c68", "#173047", "#0a1622")
BEVEL = ("#b9bec3", "#dfe2e5", "#aeb3b8")
FACE = ("#d9dcdf", "#f1f2f3", "#cfd2d5")
HIGHLIGHT = "#FFFFFF"
INK = "#173047"  # text on silver
EYEBROW = "#A9BDCF"
TEXT = "#FFFFFF"
MUTED = "#B4C2D0"
FAINT = "#7F93A6"
BEZEL = 9  # the silver rim around a screenshot

CROP_DIR = "gallery-crops/"
CROPS = {}  # crop file name -> (screenshot, region)


def crop_name(src, crop):
    base = src.replace("/", "-").replace(".png", "")
    return f"{base}-{crop[0]}-{crop[1]}-{crop[2]}-{crop[3]}.png"


class Card:
    def __init__(self, number, total, eyebrow, headline, subline):
        self.parts = []
        self.defs = []
        self.ids = 0
        self.number, self.total = number, total
        self.eyebrow, self.headline, self.subline = eyebrow, headline, subline

    def uid(self, prefix):
        self.ids += 1
        return f"{prefix}{self.ids}"

    def add(self, svg):
        self.parts.append(svg)

    def text(self, x, y, s, size, color=TEXT, weight=400, anchor="start", spacing=0):
        self.add(f'<text x="{x}" y="{y}" font-family="{FONT}" font-size="{size}" font-weight="{weight}" '
                 f'fill="{color}" text-anchor="{anchor}" letter-spacing="{spacing}">{escape(s)}</text>')

    def shot(self, src, crop, box, radius=10):
        """Draws the region `crop` (cx, cy, cw, ch in screenshot pixels) of screenshot `src` into
        `box` (x, y, w, h on the card), in a silver rim. Returns a function mapping screenshot to card
        coordinates."""
        cx, cy, cw, ch = crop
        x, y, w, h = box
        b = BEZEL
        self.add(f'<rect x="{x - b}" y="{y - b}" width="{w + 2 * b}" height="{h + 2 * b}" rx="{radius + b}" '
                 f'fill="url(#bevel)" filter="url(#shadow)"/>'
                 f'<rect x="{x - b + 1.5}" y="{y - b + 1.5}" width="{w + 2 * b - 3}" height="{h + 2 * b - 3}" '
                 f'rx="{radius + b - 1.5}" fill="none" stroke="#ffffff" stroke-opacity="0.8" stroke-width="1.5"/>')
        clip = self.uid("clip")
        self.defs.append(f'<clipPath id="{clip}"><rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{radius}"/>'
                         f'</clipPath>')
        # a pre-cropped file (build.sh): resvg draws an image scaled past about 4096 pixels black
        name = crop_name(src, crop)
        CROPS[name] = (src, crop)
        self.add(f'<g clip-path="url(#{clip})"><image href="{CROP_DIR}{name}" x="{x}" y="{y}" width="{w}" '
                 f'height="{h}" preserveAspectRatio="none"/></g>'
                 f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{radius}" fill="none" stroke="#6f767d" '
                 f'stroke-width="1.5"/>')
        return lambda px, py: (x + (px - cx) * w / cw, y + (py - cy) * h / ch)

    def zoom(self, src, crop, at, scale):
        """A shot of `crop` at `scale` with its top left corner at `at`; returns (mapper, box)."""
        cx, cy, cw, ch = crop
        box = (at[0], at[1], round(cw * scale), round(ch * scale))
        return self.shot(src, crop, box), box

    def outline(self, rect, radius=8):
        """A white frame with a soft glow just outside `rect` (card coordinates)."""
        x, y, w, h = rect
        pad = 4
        self.add(f'<rect x="{x - pad:.1f}" y="{y - pad:.1f}" width="{w + 2 * pad:.1f}" height="{h + 2 * pad:.1f}" '
                 f'rx="{radius}" fill="none" stroke="{HIGHLIGHT}" stroke-width="3" filter="url(#glow)"/>')

    def mapped(self, mapper, rect):
        x0, y0 = mapper(rect[0], rect[1])
        x1, y1 = mapper(rect[0] + rect[2], rect[1] + rect[3])
        return (x0, y0, x1 - x0, y1 - y0)

    def connector(self, a, b):
        self.add(f'<line x1="{a[0]:.1f}" y1="{a[1]:.1f}" x2="{b[0]:.1f}" y2="{b[1]:.1f}" stroke="{HIGHLIGHT}" '
                 f'stroke-width="3" stroke-dasharray="2 9" stroke-linecap="round" filter="url(#glow)"/>')

    def arrow(self, x, y, size=16):
        """A chevron pointing right, centred on (x, y)."""
        self.add(f'<path d="M {x - size / 2:.1f} {y - size:.1f} l {size} {size} l {-size} {size}" fill="none" '
                 f'stroke="{HIGHLIGHT}" stroke-width="5" stroke-linecap="round" stroke-linejoin="round" '
                 f'filter="url(#glow)"/>')

    def marker(self, x, y, n, r=24):
        """A numbered marker like the thumbnail's round close button: silver face, white rim."""
        self.add(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r}" fill="url(#face)" filter="url(#lift)"/>'
                 f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r - 1}" fill="none" stroke="#ffffff" stroke-width="2"/>')
        self.text(round(x), round(y + r * 0.38), str(n), round(r * 1.05), INK, 800, "middle")

    def pin(self, point, offset, n, r=22):
        """A marker at `point` + `offset` with a leader line to `point`, so it covers nothing there."""
        mx, my = point[0] + offset[0], point[1] + offset[1]
        self.add(f'<line x1="{point[0]:.1f}" y1="{point[1]:.1f}" x2="{mx:.1f}" y2="{my:.1f}" stroke="{HIGHLIGHT}" '
                 f'stroke-width="3" filter="url(#glow)"/>'
                 f'<circle cx="{point[0]:.1f}" cy="{point[1]:.1f}" r="7" fill="{HIGHLIGHT}" stroke="{INK}" '
                 f'stroke-width="2"/>')
        self.marker(mx, my, n, r)

    def chip(self, x, y, label, silver):
        width = round(len(label) * 13.2 + 40)
        if silver:
            self.add(f'<rect x="{x}" y="{y}" width="{width}" height="44" rx="22" fill="url(#face)" '
                     f'filter="url(#lift)"/>')
            self.text(x + width / 2, y + 30, label, 22, INK, 700, "middle")
        else:
            self.add(f'<rect x="{x}" y="{y}" width="{width}" height="44" rx="22" fill="{GLOW[0]}" '
                     f'stroke="#ffffff" stroke-opacity="0.25"/>')
            self.text(x + width / 2, y + 30, label, 22, "#D5DEE7", 700, "middle")
        return width

    def plate(self, x, y, label, n=None):
        """A caption on a silver pill (readable over the game), with an optional step marker."""
        width = round(len(label) * 12.6 + (84 if n else 40))
        self.add(f'<rect x="{x}" y="{y}" width="{width}" height="50" rx="25" fill="url(#face)" '
                 f'filter="url(#lift)"/>')
        if n:
            self.add(f'<circle cx="{x + 25}" cy="{y + 25}" r="18" fill="{INK}"/>')
            self.text(x + 25, y + 32, str(n), 20, TEXT, 800, "middle")
        self.text(x + (56 if n else 20), y + 33, label, 24, INK, 700)
        return width

    def svg(self):
        head = [
            f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">',
            '<defs>',
            # as assets/preview.svg (background-glow-fill, window-bevel-fill, window-face-fill)
            f'<radialGradient id="bg" cx="960" cy="330" r="1150" gradientUnits="userSpaceOnUse">'
            f'<stop offset="0" stop-color="{GLOW[0]}"/><stop offset="0.55" stop-color="{GLOW[1]}"/>'
            f'<stop offset="1" stop-color="{GLOW[2]}"/></radialGradient>',
            f'<linearGradient id="bevel" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="{BEVEL[0]}"/>'
            f'<stop offset="0.5" stop-color="{BEVEL[1]}"/><stop offset="1" stop-color="{BEVEL[2]}"/></linearGradient>',
            f'<linearGradient id="face" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="{FACE[0]}"/>'
            f'<stop offset="0.5" stop-color="{FACE[1]}"/><stop offset="1" stop-color="{FACE[2]}"/></linearGradient>',
            '<filter id="shadow" x="-10%" y="-10%" width="120%" height="130%">'
            '<feDropShadow dx="0" dy="14" stdDeviation="18" flood-color="#000" flood-opacity="0.6"/></filter>',
            '<filter id="lift" x="-30%" y="-30%" width="160%" height="180%">'
            '<feDropShadow dx="0" dy="3" stdDeviation="4" flood-color="#000" flood-opacity="0.45"/></filter>',
            '<filter id="glow" x="-20%" y="-20%" width="140%" height="140%">'
            '<feDropShadow dx="0" dy="0" stdDeviation="4" flood-color="#ffffff" flood-opacity="0.85"/></filter>',
            *self.defs,
            '</defs>',
            f'<rect width="{W}" height="{H}" fill="url(#bg)"/>',
        ]
        frame = Card(0, 0, "", "", "")
        frame.text(MARGIN, 104, self.eyebrow.upper(), 22, EYEBROW, 700, spacing=3)
        frame.text(MARGIN, 168, self.headline, 58, TEXT, 700)
        frame.text(MARGIN, 214, self.subline, 26, MUTED, 400)
        frame.text(W - MARGIN, H - 34, "UI Overhaul  ·  Transport Fever 3", 20, FAINT, 400, "end")
        frame.text(MARGIN, H - 34, f"{self.number:02d} / {self.total:02d}", 20, FAINT, 700)
        return "\n".join(head + frame.parts + self.parts + ["</svg>"])


MOD = "gallery-mod/"
VANILLA = "gallery-vanilla/"
TOP = 256  # first line below the subline
BOTTOM = 1000  # last line above the footer
TOTAL = 10


def before_after():
    c = Card(1, TOTAL, "Line Manager", "See which lines lose money at a glance",
             "Vehicle count and 12-month balance for every line, load and age for every vehicle.")
    crop = (100, 96, 690, 760)  # the Line Manager's title row, lines and vehicles
    y = TOP + 44 + 30
    h = BOTTOM - y
    w = round(690 * h / 760)
    gap = 130
    left = (W - 2 * w - gap) // 2
    c.chip(left, TOP + 4, "Vanilla", False)
    c.shot(VANILLA + "gallery_line_manager.png", crop, (left, y, w, h))
    right = left + w + gap
    c.chip(right, TOP + 4, "With UI Overhaul", True)
    m = c.shot(MOD + "gallery_line_manager.png", crop, (right, y, w, h))
    c.outline(c.mapped(m, (486, 282, 182, 262)))   # vehicle count and balance
    c.outline(c.mapped(m, (110, 604, 672, 52)))    # the model row
    c.outline(c.mapped(m, (543, 664, 212, 172)))   # load, condition and age
    c.arrow(left + w + gap / 2, y + h / 2)
    return "01-line-manager-before-after", c


def terminals():
    c = Card(4, TOTAL, "Stations", "Set a stop's terminals in one click",
             "A terminal button for every line in the station window: Preferred, Alternative or Don't use.")
    src = MOD + "gallery_terminals.png"
    box = (MARGIN, TOP + 8, W - 2 * MARGIN, BOTTOM - TOP - 8)
    context = (560, 0, 2880, round(2880 * box[3] / box[2]))
    m = c.shot(src, context, box)
    rows = (2822, 225, 558, 272)  # the station's line rows with their buttons
    pop = (856, 214, 942, 170)    # the popover
    c.outline(c.mapped(m, rows))
    c.outline(c.mapped(m, pop))
    _mp, bp = c.zoom(src, pop, (MARGIN + 56, BOTTOM - 56 - 170), 1.0)
    _mr, br = c.zoom(src, rows, (W - MARGIN - 56 - 558, BOTTOM - 56 - 272), 1.0)
    sp, sr = c.mapped(m, pop), c.mapped(m, rows)
    c.connector((sp[0] + sp[2] / 2, sp[1] + sp[3] + 4), (bp[0] + bp[2] / 2, bp[1] - BEZEL))
    c.connector((sr[0] + sr[2] / 2, sr[1] + sr[3] + 4), (br[0] + br[2] / 2, br[1] - 66))
    c.plate(br[0], br[1] - 74, "The button next to each line", 1)
    c.plate(bp[0] + bp[2] - 420, bp[1] - 74, "Its terminals, set right there", 2)
    return "04-terminals", c


def industry():
    c = Card(5, TOTAL, "Industries", "Know why an industry isn't growing",
             "Level, transported share, what blocks it, and the lines that serve it.")
    src = MOD + "gallery_industry.png"
    box_w = W - 2 * MARGIN
    box_h = round(box_w * 1440 / 3440)
    m = c.shot(src, (0, 0, 3440, 1440), (MARGIN, TOP + 8, box_w, box_h))
    card = (2818, 350, 564, 425)  # Development and Served by
    c.outline(c.mapped(m, card))
    _mi, bi = c.zoom(src, card, (MARGIN + 56, TOP + 44), 1.12)
    sc = c.mapped(m, card)
    c.connector((sc[0] - 4, sc[1] + sc[3] / 2), (bi[0] + bi[2] + BEZEL, bi[1] + bi[3] / 2))
    c.plate(bi[0], bi[1] + bi[3] + 26, "Why it does not expand, and who serves it")
    return "05-industry", c


def statistics():
    c = Card(6, TOTAL, "Statistics", "Find the lines that lose money in one click",
             "Quick filters for losing lines, problems and empty lines, with totals for what is shown.")
    src = MOD + "gallery_statistics_losing.png"
    box_w = W - 2 * MARGIN
    box_h = round(box_w * 1440 / 3440)
    m = c.shot(src, (0, 0, 3440, 1440), (MARGIN, TOP + 8, box_w, box_h))
    filters = (90, 1014, 510, 56)
    totals = (2838, 1016, 520, 56)
    c.outline(c.mapped(m, filters))
    c.outline(c.mapped(m, totals))
    scale = 1.55
    _mf, bf = c.zoom(src, filters, (MARGIN + 70, TOP + 90), scale)
    _mt, bt = c.zoom(src, totals, (W - MARGIN - 70 - round(520 * scale), TOP + 90), scale)
    sf, st = c.mapped(m, filters), c.mapped(m, totals)
    c.connector((sf[0] + sf[2] / 2, sf[1] - 4), (bf[0] + bf[2] / 2, bf[1] + bf[3] + BEZEL))
    c.connector((st[0] + st[2] / 2, st[1] - 4), (bt[0] + bt[2] / 2, bt[1] + bt[3] + BEZEL))
    c.marker(bf[0] - 4, bf[1] - 4, 1)
    c.marker(bt[0] - 4, bt[1] - 4, 2)
    return "06-statistics", c


def workflow():
    c = Card(7, TOTAL, "Workflow", "Replace a vehicle model across your whole network",
             "Pick the model, pull its vehicles from every line, replace them all at once.")
    crop = (100, 322, 690, 740)
    steps = [
        (MOD + "gallery_models_select.png", "Click the model", (110, 604, 672, 52)),
        (MOD + "gallery_models_all_lines.png", "“In all lines” adds every one", (110, 610, 666, 266)),
        (MOD + "gallery_models_replace.png", "Replace them all in one go", (166, 893, 560, 112)),
    ]
    gap = 52
    w = (W - 2 * MARGIN - 2 * gap) // 3
    h = round(w * 740 / 690)
    y = TOP + 76
    for i, (src, caption, mark) in enumerate(steps):
        x = MARGIN + i * (w + gap)
        m = c.shot(src, crop, (x, y, w, h))
        c.outline(c.mapped(m, mark))
        c.marker(x + 22, y - 42, i + 1, 22)
        c.text(x + 58, y - 33, caption, 26, TEXT, 700)
        if i < 2:
            c.arrow(x + w + gap / 2, y + h / 2, 13)
    c.text(W / 2, y + h + 62, "The Line Manager asks first, so nothing is replaced by accident.", 24, MUTED, 400,
           "middle")
    return "07-workflow-replace-model", c


def overview():
    c = Card(14, TOTAL, "At a glance", "More to read, fewer clicks, in the windows you know",
             "Every change sits in a vanilla screen: no new windows, no new notifications.")
    src = MOD + "gallery_overview.png"
    box_w = 1560
    box_h = round(box_w * 1440 / 3440)
    x = (W - box_w) // 2
    m = c.shot(src, (0, 0, 3440, 1440), (x, TOP + 8, box_w, box_h))
    points = [  # screenshot point, marker offset on the card, label
        ((674, 330), (96, 0), "Balance per line"),
        ((784, 560), (64, 0), "Every vehicle of a model"),
        ((2834, 1010), (-58, 0), "Performance on slopes"),
        ((1240, 40), (60, 40), "Notifications grouped"),
        ((3243, 41), (-60, 60), "Minimize any window"),
    ]
    for i, (p, offset, _label) in enumerate(points):
        c.pin(m(*p), offset, i + 1)
    y = TOP + 8 + box_h + 62
    col = (W - 2 * MARGIN) / len(points)
    for i, (_p, _o, label) in enumerate(points):
        lx = MARGIN + i * col
        c.marker(lx + 20, y - 8, i + 1, 18)
        c.text(lx + 48, y, label, 23, TEXT, 700)
    return "14-overview", c


def pair(c, crop, src_before, src_after, labels=("Vanilla", "With UI Overhaul")):
    """Two shots of `crop` side by side under their chips, as large as the card allows; returns the
    after shot's mapper and box and the before shot's mapper."""
    cw, ch = crop[2], crop[3]
    gap = 130
    y = TOP + 44 + 30
    h = BOTTOM - y
    w = round(cw * h / ch)
    if 2 * w + gap > W - 2 * MARGIN:
        w = (W - 2 * MARGIN - gap) // 2
        h = round(ch * w / cw)
    left = (W - 2 * w - gap) // 2
    c.chip(left, TOP + 4, labels[0], False)
    before = c.shot(src_before, crop, (left, y, w, h))
    right = left + w + gap
    c.chip(right, TOP + 4, labels[1], True)
    after = c.shot(src_after, crop, (right, y, w, h))
    c.arrow(left + w + gap / 2, y + h / 2)
    return after, (right, y, w, h), before


def line_window():
    c = Card(2, TOTAL, "Line window", "Add or remove a vehicle without the Line Manager",
             "Load and condition per vehicle, Add Vehicle and Remove Vehicle, and a Stops card with who waits where.")
    m, _box, _b = pair(c, (2800, 400, 610, 820), VANILLA + "gallery_line_window.png", MOD + "gallery_line_window.png")
    c.outline(c.mapped(m, (3080, 488, 146, 134)))   # load and condition
    c.outline(c.mapped(m, (2836, 660, 424, 52)))    # Add Vehicle, Remove Vehicle
    c.outline(c.mapped(m, (2822, 720, 556, 262)))   # the Stops card
    return "02-line-window-before-after", c


def vehicle_hover():
    c = Card(3, TOTAL, "Vehicles on the map", "Hover a vehicle, see how it is doing",
             "Line, next stop, speed, load, condition and delivery quality, right where the vehicle is.")
    m, _box, _b = pair(c, (1560, 600, 760, 480), VANILLA + "gallery_vehicle_hover.png", MOD + "gallery_vehicle_hover.png")
    c.outline(c.mapped(m, (1736, 816, 450, 198)))
    return "03-vehicle-hover-before-after", c


def warehouses():
    c = Card(7, TOTAL, "Statistics", "See what lies in every warehouse",
             "Each cargo with its amount, Full and Empty filters, a cargo picker, and totals for what is shown.")
    src = MOD + "gallery_warehouses.png"
    crop = (60, 930, 1900, 400)
    w = W - 2 * MARGIN
    h = round(400 * w / 1900)
    m = c.shot(src, crop, (MARGIN, TOP + 8, w, h))
    c.outline(c.mapped(m, (86, 1012, 524, 64)))    # filters and the cargo picker
    c.outline(c.mapped(m, (1206, 1100, 668, 226)))  # stocks per cargo
    totals = (2680, 1012, 690, 64)
    _mt, bt = c.zoom(src, totals, (W - MARGIN - round(690 * 1.5), TOP + 8 + h + 70), 1.5)
    c.marker(bt[0] - 4, bt[1] - 4, 2)
    c.plate(MARGIN, TOP + 8 + h + 82, "Filter by cargo, see stock per warehouse", 1)
    c.plate(bt[0], bt[1] + bt[3] + 26, "Totals for what the filter shows", 2)
    return "07-warehouses", c


def notifications():
    c = Card(9, TOTAL, "Notifications", "Fewer icons, clearer colours, offers that say when they end",
             "Notifications of one kind share an icon with a count; every colour has 7:1 contrast to its symbol.")
    vanilla_ridge = (1140, 8, 450, 70)
    mod_ridge = (1140, 8, 322, 70)
    scale = 1.25
    y = TOP + 60
    c.chip(MARGIN, y, "Vanilla", False)
    c.zoom(VANILLA + "gallery_vehicle_hover.png", vanilla_ridge, (MARGIN, y + 70), scale)
    y2 = y + 70 + round(70 * scale) + 70
    c.chip(MARGIN, y2, "With UI Overhaul", True)
    c.zoom(MOD + "gallery_vehicle_hover.png", mod_ridge, (MARGIN, y2 + 70), scale)
    card = (1296, 88, 512, 318)
    s2 = 1.6
    _mc, bc = c.zoom(MOD + "gallery_subsidy_hover_3.png", card, (W - MARGIN - round(card[2] * s2), TOP + 40), s2)
    c.plate(bc[0], bc[1] + bc[3] + 26, "A subsidy offer, with the time it has left")
    c.text(MARGIN, y2 + 70 + round(70 * scale) + 74, "Seven icons become five groups, in high-contrast colours.", 24,
           MUTED, 400)
    return "09-notifications", c


def catchment():
    c = Card(8, TOTAL, "Map", "Keep every station's catchment area on the map",
             "Two buttons switch the passenger and the cargo areas of all stations on and off, separately.")
    src = MOD + "gallery_catchment.png"
    h = BOTTOM - TOP - 8
    w = round(3440 * h / 1440)
    x = (W - w) // 2
    m = c.shot(src, (0, 0, 3440, 1440), (x, TOP + 8, w, h))
    buttons = (94, 16, 112, 54)
    c.outline(c.mapped(m, buttons))
    _mb, bb = c.zoom(src, buttons, (x + 70, TOP + 130), 2.6)
    sb = c.mapped(m, buttons)
    c.connector((sb[0] + sb[2] / 2, sb[1] + sb[3] + 4), (bb[0] + bb[2] / 2, bb[1] - BEZEL))
    c.plate(bb[0] + bb[2] + 30, bb[1] + bb[3] / 2 - 25, "Passengers and cargo, each on its own")
    return "08-catchment", c


def minimize():
    c = Card(10, TOTAL, "Windows", "Minimize any window to its title bar",
             "A button next to close folds the window; it keeps its place, its tabs and what you scrolled to.")
    crop = (2280, 0, 1160, 1220)
    after, _box, before = pair(c, crop, MOD + "gallery_minimize_open.png", MOD + "gallery_minimize_folded.png",
                               ("Open", "Minimized"))
    c.outline(c.mapped(before, (3222, 20, 42, 42)), radius=21)
    c.outline(c.mapped(after, (2796, 8, 612, 84)))
    return "10-minimize", c


CARDS = [before_after, line_window, vehicle_hover, terminals, industry, statistics, workflow, catchment, notifications, minimize]
# not in the gallery (mod.io takes at most 10 images per upload): warehouses, overview


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)
    shots, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    for make in CARDS:
        name, card = make()
        with open(os.path.join(out, name + ".svg"), "w", encoding="utf-8") as f:
            f.write(card.svg())
        print(name)
    for src, _crop in CROPS.values():
        if not os.path.isfile(os.path.join(shots, src)):
            sys.exit(f"missing screenshot: {src}")
    with open(os.path.join(out, "crops.txt"), "w", encoding="utf-8") as f:
        for name, (src, (cx, cy, cw, ch)) in sorted(CROPS.items()):
            f.write(f"{src} {CROP_DIR}{name} {cx} {cy} {cw} {ch}\n")


if __name__ == "__main__":
    main()
