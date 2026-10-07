#!/usr/bin/env python3
"""Packt die Mod fürs Mod-Portal: dist/item-gamble_<version>.zip mit Ordner item-gamble_<version>/."""
import json
import pathlib
import zipfile

root = pathlib.Path(__file__).resolve().parent.parent
info = json.loads((root / "info.json").read_text(encoding="utf-8"))
folder = f"{info['name']}_{info['version']}"
include = ["info.json", "changelog.txt", "thumbnail.png", "LICENSE", "control.lua", "data.lua", "settings.lua"]
include_dirs = ["scripts", "locale", "graphics"]

files = [root / f for f in include]
for d in include_dirs:
    files += sorted(p for p in (root / d).rglob("*") if p.is_file())

out = root / "dist"
out.mkdir(exist_ok=True)
target = out / f"{folder}.zip"
with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as z:
    for f in files:
        z.write(f, f"{folder}/{f.relative_to(root).as_posix()}")
print(target, f"({len(files)} Dateien)")
