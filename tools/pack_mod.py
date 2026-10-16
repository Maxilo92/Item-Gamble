#!/usr/bin/env python3
"""Packt die Mod fürs Mod-Portal: dist/item-gamble_<version>.zip mit Ordner item-gamble_<version>/.

Ohne Argumente gilt info.json (Factorio 2.1). Derselbe Code läuft auch auf 2.0, das Portal
verlangt dafür aber eine eigene Zip mit eigener Versionsnummer:

    python tools/pack_mod.py --factorio 2.0 --version 0.26.1
"""
import argparse
import json
import pathlib
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument("--factorio", help="factorio_version für diese Zip, z.B. 2.0")
parser.add_argument("--version", help="Versionsnummer für diese Zip (Pflicht mit --factorio)")
args = parser.parse_args()

root = pathlib.Path(__file__).resolve().parent.parent
info = json.loads((root / "info.json").read_text(encoding="utf-8"))
if args.factorio:
    if not args.version or args.version == info["version"]:
        parser.error("--factorio braucht eine eigene --version")
    info["version"] = args.version
    info["factorio_version"] = args.factorio
    info["dependencies"] = [
        f"{dep.split('>=')[0].strip()} >= {args.factorio}.0" if dep.split()[0] in ("base", "space-age") else dep
        for dep in info["dependencies"]
    ]
folder = f"{info['name']}_{info['version']}"
include = ["changelog.txt", "thumbnail.png", "LICENSE", "control.lua", "data.lua", "settings.lua"]
include_dirs = ["scripts", "locale", "graphics"]

files = [root / f for f in include]
for d in include_dirs:
    files += sorted(p for p in (root / d).rglob("*") if p.is_file())

out = root / "dist"
out.mkdir(exist_ok=True)
target = out / f"{folder}.zip"
with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr(f"{folder}/info.json", json.dumps(info, indent=2, ensure_ascii=False) + "\n")
    for f in files:
        z.write(f, f"{folder}/{f.relative_to(root).as_posix()}")
print(target, f"({len(files) + 1} Dateien, Factorio {info['factorio_version']})")
