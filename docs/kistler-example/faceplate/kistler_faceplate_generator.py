#!/usr/bin/env python3
"""
Kistler maXYmos NC WinCC Unified faceplate generator.
Produces SVG + SVGHMI XML for a Kistler press control/monitoring interface.

Outputs hierarchical SVG with bindable parameters for:
- Status indicators (Ready, OK/NOK, alarms)
- Control buttons (Start, Home, Ref, Jog Fwd/Back, Stop, Reset)
- Process values (Force, Distance, Gradient curves, pass/fail)
- MP/sequence selection
- Live force-displacement curve plot
"""

import xml.etree.ElementTree as ET
from xml.dom import minidom
from dataclasses import dataclass
from typing import List, Tuple

# ============================================================================
# CONSTANTS & DESIGN
# ============================================================================

CANVAS_W, CANVAS_H = 1200, 800
MARGIN = 20

# Colors
COLOR_OK = "#00CC00"       # Green
COLOR_NOK = "#CC0000"      # Red
COLOR_WARN = "#FFCC00"     # Yellow
COLOR_READY = "#0066FF"    # Blue
COLOR_BG = "#E8E8E8"       # Light gray
COLOR_TEXT = "#000000"
COLOR_PANEL_BG = "#F5F5F5"

# Sections
SECTION_STATUS = {"x": MARGIN, "y": MARGIN, "w": 300, "h": 150}
SECTION_CONTROLS = {"x": MARGIN, "y": MARGIN + 170, "w": 300, "h": 280}
SECTION_CURVE = {"x": MARGIN + 320, "y": MARGIN, "w": 520, "h": 450}
SECTION_PV = {"x": MARGIN + 320, "y": MARGIN + 470, "w": 520, "h": 160}
SECTION_MP = {"x": MARGIN + 860, "y": MARGIN, "w": 300, "h": 300}
SECTION_ALARMS = {"x": MARGIN + 860, "y": MARGIN + 320, "w": 300, "h": 310}

# ============================================================================
# DATA CLASSES
# ============================================================================

@dataclass
class ButtonDef:
    """Control button definition."""
    label: str
    x: float
    y: float
    w: float = 80
    h: float = 40
    param: str = ""  # Parameter name if bound

@dataclass
class IndicatorDef:
    """Status indicator definition."""
    label: str
    x: float
    y: float
    w: float = 60
    h: float = 30
    param: str = ""
    color_ok: str = COLOR_OK
    color_nok: str = COLOR_NOK

# ============================================================================
# SVG BUILDER
# ============================================================================

class SVGBuilder:
    """Build SVG elements with parameter binding hints."""

    def __init__(self, w: int, h: int):
        self.w = w
        self.h = h
        self.root = ET.Element("svg")
        self.root.set("xmlns", "http://www.w3.org/2000/svg")
        self.root.set("viewBox", f"0 0 {w} {h}")
        self.root.set("width", str(w))
        self.root.set("height", str(h))
        self.root.set("class", "svghmi")

        # Background
        bg = ET.SubElement(self.root, "rect")
        bg.set("width", str(w))
        bg.set("height", str(h))
        bg.set("fill", COLOR_BG)

        self.next_id = 1

    def _id(self, prefix="obj"):
        """Generate unique ID."""
        uid = f"{prefix}_{self.next_id}"
        self.next_id += 1
        return uid

    def group(self, label=""):
        """Create and return a <g> element."""
        g = ET.Element("g")
        if label:
            g.set("class", label)
        return g

    def rect(self, x, y, w, h, fill=COLOR_PANEL_BG, stroke="#999", stroke_w=1, rx=4):
        """Add rounded rectangle."""
        r = ET.Element("rect")
        r.set("x", str(x))
        r.set("y", str(y))
        r.set("width", str(w))
        r.set("height", str(h))
        r.set("fill", fill)
        r.set("stroke", stroke)
        r.set("stroke-width", str(stroke_w))
        r.set("rx", str(rx))
        return r

    def text(self, label, x, y, font_size=14, fill=COLOR_TEXT, anchor="start"):
        """Add text element."""
        t = ET.Element("text")
        t.set("x", str(x))
        t.set("y", str(y))
        t.set("font-family", "Arial, sans-serif")
        t.set("font-size", str(font_size))
        t.set("fill", fill)
        t.set("text-anchor", anchor)
        t.text = label
        return t

    def circle(self, cx, cy, r, fill=COLOR_OK, stroke="#333", stroke_w=1):
        """Add circle."""
        c = ET.Element("circle")
        c.set("cx", str(cx))
        c.set("cy", str(cy))
        c.set("r", str(r))
        c.set("fill", fill)
        c.set("stroke", stroke)
        c.set("stroke-width", str(stroke_w))
        return c

    def polyline(self, points: List[Tuple[float, float]], fill="none", stroke="#000", stroke_w=2):
        """Add polyline for curve."""
        pl = ET.Element("polyline")
        pts = " ".join(f"{x},{y}" for x, y in points)
        pl.set("points", pts)
        pl.set("fill", fill)
        pl.set("stroke", stroke)
        pl.set("stroke-width", str(stroke_w))
        pl.set("stroke-linecap", "round")
        pl.set("stroke-linejoin", "round")
        return pl

    def button(self, label, x, y, w=80, h=40, param=""):
        """Create a clickable button group with parameter hint."""
        g = self.group(f"button {param}")
        g.set("data-param", param)
        g.set("class", f"button {param}")

        # Background
        bg = self.rect(x, y, w, h, fill="#CCCCCC", stroke="#666", stroke_w=2)
        g.append(bg)

        # Label
        txt = self.text(label, x + w/2, y + h/2 + 5, font_size=12, anchor="middle")
        g.append(txt)

        return g

    def indicator(self, label, x, y, w=60, h=30, param="", color_on=COLOR_OK):
        """Create a status indicator (LED-style) with parameter binding."""
        g = self.group(f"indicator {param}")
        g.set("data-param", param)
        g.set("class", f"indicator {param}")

        # Background
        bg = self.rect(x, y, w, h, fill="#DCDCDC", stroke="#666", stroke_w=1)
        g.append(bg)

        # Circle (LED)
        led = self.circle(x + w/2, y + h/2, 12, fill="#CCCCCC", stroke="#666")
        led.set("class", f"led {param}")
        led.set("data-param", param)
        g.append(led)

        # Label below
        txt = self.text(label, x + w/2, y + h + 15, font_size=11, anchor="middle")
        g.append(txt)

        return g

    def add(self, elem):
        """Add element to root."""
        self.root.append(elem)

    def add_to_group(self, group, elem):
        """Add element to a group."""
        group.append(elem)

    def to_xml_string(self, pretty=True):
        """Export to XML string."""
        xml_str = ET.tostring(self.root, encoding='unicode')
        if pretty:
            dom = minidom.parseString(xml_str)
            return dom.toprettyxml(indent="  ")
        return xml_str

# ============================================================================
# FACEPLATE DESIGN
# ============================================================================

def build_kistler_faceplate() -> SVGBuilder:
    """Build the complete Kistler faceplate SVG."""
    svg = SVGBuilder(CANVAS_W, CANVAS_H)

    # ---- TITLE ----
    title = svg.text("Kistler maXYmos NC Press Controller", CANVAS_W/2, 25, font_size=18, anchor="middle")
    title.set("font-weight", "bold")
    svg.add(title)

    # ---- SECTION 1: STATUS INDICATORS ----
    sec = SECTION_STATUS
    panel = svg.rect(sec["x"], sec["y"], sec["w"], sec["h"], fill=COLOR_PANEL_BG)
    svg.add(panel)

    label = svg.text("STATUS", sec["x"] + 10, sec["y"] + 20, font_size=12, fill="#666")
    label.set("font-weight", "bold")
    svg.add(label)

    # Indicators in a grid
    ind_y = sec["y"] + 35
    indicators = [
        ("Ready", sec["x"] + 10, ind_y, "ready"),
        ("OK", sec["x"] + 100, ind_y, "okTotal"),
        ("NOK", sec["x"] + 190, ind_y, "nokTotal"),
        ("Drive", sec["x"] + 10, ind_y + 50, "driveEnabled"),
        ("Home", sec["x"] + 100, ind_y + 50, "homePos"),
        ("Ref", sec["x"] + 190, ind_y + 50, "referencePos"),
    ]

    for lbl, x, y, param in indicators:
        color = COLOR_OK if "OK" not in lbl else COLOR_OK
        color = COLOR_NOK if "NOK" in lbl else color
        ind_g = svg.indicator(lbl, x, y, 60, 30, param=param, color_on=color)
        svg.add(ind_g)

    # ---- SECTION 2: CONTROL BUTTONS ----
    sec = SECTION_CONTROLS
    panel = svg.rect(sec["x"], sec["y"], sec["w"], sec["h"], fill=COLOR_PANEL_BG)
    svg.add(panel)

    label = svg.text("CONTROLS", sec["x"] + 10, sec["y"] + 20, font_size=12, fill="#666")
    label.set("font-weight", "bold")
    svg.add(label)

    # Button grid (6 buttons in 2 cols × 3 rows)
    button_y = sec["y"] + 35
    buttons = [
        ("Start", sec["x"] + 10, button_y, "autoRunSequence"),
        ("Stop", sec["x"] + 160, button_y, "extStopRequest"),
        ("Home", sec["x"] + 10, button_y + 50, "autoHomePosition"),
        ("Ref", sec["x"] + 160, button_y + 50, "autoDriveToReferencePosition"),
        ("Jog+", sec["x"] + 10, button_y + 100, "JogFwd"),
        ("Jog-", sec["x"] + 160, button_y + 100, "JogNeq"),
        ("Reset", sec["x"] + 10, button_y + 150, "SequenceEndReset"),
        ("Enable", sec["x"] + 160, button_y + 150, "enableBlock"),
    ]

    for lbl, x, y, param in buttons:
        btn_g = svg.button(lbl, x, y, w=75, h=35, param=param)
        svg.add(btn_g)

    # ---- SECTION 3: FORCE-DISPLACEMENT CURVE ----
    sec = SECTION_CURVE
    panel = svg.rect(sec["x"], sec["y"], sec["w"], sec["h"], fill="white", stroke="#999")
    svg.add(panel)

    label = svg.text("Force vs. Displacement", sec["x"] + 10, sec["y"] + 20, font_size=12, fill="#666")
    label.set("font-weight", "bold")
    svg.add(label)

    # Axes
    curve_x = sec["x"] + 40
    curve_y = sec["y"] + 50
    curve_w = sec["w"] - 60
    curve_h = sec["h"] - 80

    # X axis (Displacement)
    x_axis = ET.Element("line")
    x_axis.set("x1", str(curve_x))
    x_axis.set("y1", str(curve_y + curve_h))
    x_axis.set("x2", str(curve_x + curve_w))
    x_axis.set("y2", str(curve_y + curve_h))
    x_axis.set("stroke", "#000")
    x_axis.set("stroke-width", "2")
    svg.add(x_axis)

    # Y axis (Force)
    y_axis = ET.Element("line")
    y_axis.set("x1", str(curve_x))
    y_axis.set("y1", str(curve_y))
    y_axis.set("x2", str(curve_x))
    y_axis.set("y2", str(curve_y + curve_h))
    y_axis.set("stroke", "#000")
    y_axis.set("stroke-width", "2")
    svg.add(y_axis)

    # Axis labels
    svg.add(svg.text("Distance (mm)", curve_x + curve_w/2, curve_y + curve_h + 30, font_size=11, anchor="middle"))
    svg.add(svg.text("Force (N)", curve_x - 35, curve_y - 5, font_size=11, anchor="end"))

    # Sample curve (parabolic motion)
    curve_points = []
    for i in range(0, 101):
        t = i / 100.0
        x = curve_x + (t * curve_w)
        # Simple curve shape: rise, plateau, fall
        if t < 0.4:
            y_val = 0.8 * t / 0.4
        elif t < 0.7:
            y_val = 0.8
        else:
            y_val = 0.8 * (1 - (t - 0.7) / 0.3)
        y = curve_y + curve_h - (y_val * curve_h * 0.8)
        curve_points.append((x, y))

    curve = svg.polyline(curve_points, fill="none", stroke="#0066FF", stroke_w=2)
    curve.set("class", "curve pvCurve")
    curve.set("data-param", "pvCurve")
    svg.add(curve)

    # ---- SECTION 4: PROCESS VALUES ----
    sec = SECTION_PV
    panel = svg.rect(sec["x"], sec["y"], sec["w"], sec["h"], fill=COLOR_PANEL_BG)
    svg.add(panel)

    label = svg.text("PROCESS VALUES", sec["x"] + 10, sec["y"] + 20, font_size=12, fill="#666")
    label.set("font-weight", "bold")
    svg.add(label)

    pv_y = sec["y"] + 40
    pv_items = [
        ("Force:", "0.0 N", sec["x"] + 10, pv_y, "pvCurrentValueY"),
        ("Distance:", "0.0 mm", sec["x"] + 270, pv_y, "pvCurrentValueX"),
        ("Gradient:", "0.0", sec["x"] + 10, pv_y + 40, "pvGradient"),
        ("Status:", "IDLE", sec["x"] + 270, pv_y + 40, "sequenceStatus"),
    ]

    for lbl, val, x, y, param in pv_items:
        svg.add(svg.text(lbl, x, y, font_size=11, fill="#333"))
        val_elem = svg.text(val, x + 80, y, font_size=11, fill="#0066FF")
        val_elem.set("class", f"value {param}")
        val_elem.set("data-param", param)
        svg.add(val_elem)

    # ---- SECTION 5: MP / SEQUENCE SELECTION ----
    sec = SECTION_MP
    panel = svg.rect(sec["x"], sec["y"], sec["w"], sec["h"], fill=COLOR_PANEL_BG)
    svg.add(panel)

    label = svg.text("MP SELECTION", sec["x"] + 10, sec["y"] + 20, font_size=12, fill="#666")
    label.set("font-weight", "bold")
    svg.add(label)

    sel_y = sec["y"] + 50
    svg.add(svg.text("MP #:", sec["x"] + 10, sel_y, font_size=11))
    mp_val = svg.text("0", sec["x"] + 200, sel_y, font_size=11, fill="#0066FF", anchor="end")
    mp_val.set("class", "value mpNumber")
    mp_val.set("data-param", "MeasurementProgramEcho")
    svg.add(mp_val)

    svg.add(svg.text("Sequence:", sec["x"] + 10, sel_y + 35, font_size=11))
    seq_val = svg.text("Main", sec["x"] + 200, sel_y + 35, font_size=11, fill="#0066FF", anchor="end")
    seq_val.set("class", "value sequenceLabel")
    seq_val.set("data-param", "currentLabel")
    svg.add(seq_val)

    svg.add(svg.text("Status:", sec["x"] + 10, sel_y + 70, font_size=11))
    stat_val = svg.text("Ready", sec["x"] + 200, sel_y + 70, font_size=11, fill="#00AA00", anchor="end")
    stat_val.set("class", "value readyStatus")
    stat_val.set("data-param", "ready")
    svg.add(stat_val)

    # ---- SECTION 6: ALARMS ----
    sec = SECTION_ALARMS
    panel = svg.rect(sec["x"], sec["y"], sec["w"], sec["h"], fill=COLOR_PANEL_BG)
    svg.add(panel)

    label = svg.text("ALARMS & FAULTS", sec["x"] + 10, sec["y"] + 20, font_size=12, fill="#666")
    label.set("font-weight", "bold")
    svg.add(label)

    # Alarm list
    alarm_y = sec["y"] + 45
    alarms = [
        ("Hardware NOK", "hardwareNOK"),
        ("Drive NOK", "driveenabledNOK"),
        ("Safety NOK", "safetyNOK"),
        ("Serial Mismatch", "serialnumbermismatch"),
        ("Transmission", "transmissionFault"),
        ("User Mode Active", "remoteControlNotActive"),
    ]

    for i, (lbl, param) in enumerate(alarms):
        y = alarm_y + (i * 30)
        led = svg.circle(sec["x"] + 15, y + 5, 6, fill="#CCCCCC", stroke="#666")
        led.set("class", f"alarm-led {param}")
        led.set("data-param", param)
        svg.add(led)

        txt = svg.text(lbl, sec["x"] + 30, y + 10, font_size=10)
        svg.add(txt)

    # ---- FOOTER ----
    footer = svg.text("Generated for WinCC Unified SVGHMI | Kistler maXYmos NC", CANVAS_W/2, CANVAS_H - 10, font_size=9, anchor="middle", fill="#999")
    svg.add(footer)

    return svg

# ============================================================================
# MAIN
# ============================================================================

if __name__ == "__main__":
    svg = build_kistler_faceplate()
    xml_str = svg.to_xml_string(pretty=True)

    # Save SVG file
    output_file = "C:/Users/MudasserWahab/Claude Code/_kistler_faceplate_v1.svg"
    with open(output_file, "w", encoding="utf-8") as f:
        f.write(xml_str)

    print(f"[OK] Faceplate generated: {output_file}")
    print(f"[OK] SVG size: {len(xml_str)} bytes")
    print("\nParameters bound (for WinCC binding):")
    # Extract all data-param attributes
    import re
    params = set(re.findall(r'data-param="([^"]+)"', xml_str))
    for p in sorted(params):
        if p:
            print(f"  - {p}")
