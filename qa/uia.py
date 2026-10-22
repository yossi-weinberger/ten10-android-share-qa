#!/usr/bin/env python3
"""uiautomator helper: `uia.py tap REGEX` taps first node whose text/content-desc/resource-id matches; `has REGEX`; `dump`."""
import re, subprocess, sys, xml.etree.ElementTree as ET

def dump():
    subprocess.run(["adb", "shell", "uiautomator", "dump", "/sdcard/ui.xml"], capture_output=True)
    x = subprocess.run(["adb", "exec-out", "cat", "/sdcard/ui.xml"], capture_output=True, text=True).stdout
    try:
        return ET.fromstring(x[x.find("<"):])
    except Exception:
        return None

def find(rx):
    root = dump()
    if root is None:
        return None
    r = re.compile(rx, re.I)
    for n in root.iter("node"):
        for k in ("text", "content-desc", "resource-id"):
            if n.get(k) and r.search(n.get(k)):
                return n
    return None

cmd, rx = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else "")
if cmd == "dump":
    root = dump()
    for n in (root.iter("node") if root is not None else []):
        t = n.get("text") or n.get("content-desc")
        if t:
            print(repr(t), n.get("resource-id"), n.get("bounds"))
    sys.exit(0)
n = find(rx)
if n is None:
    print("not found:", rx); sys.exit(1)
if cmd == "tap":
    a = list(map(int, re.findall(r"\d+", n.get("bounds"))))
    subprocess.run(["adb", "shell", "input", "tap", str((a[0]+a[2])//2), str((a[1]+a[3])//2)])
    print("tapped:", n.get("text") or n.get("content-desc") or n.get("resource-id"))
else:
    print("found:", n.get("text") or n.get("content-desc"))
