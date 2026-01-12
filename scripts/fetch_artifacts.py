#!/usr/bin/env python3
from pathlib import Path
import urllib.request
import yaml

ROOT = Path(__file__).resolve().parent.parent
ROLES = ROOT / "ansible" / "roles"
OUT = ROOT / "ansible" / "artifacts"

for role in sorted(ROLES.iterdir()):
    if not role.is_dir():
        continue

    meta = role / "meta" / "artifacts.yaml"
    if not meta.exists():
        continue

    data = yaml.safe_load(meta.read_text(encoding="utf-8")) or {}
    for a in data.get("artifacts", []):
        url = a["url"]
        name = url.rstrip("/").split("/")[-1]
        dest = OUT / name

        dest.parent.mkdir(parents=True, exist_ok=True)

        if dest.exists() and dest.stat().st_size > 0:
            print("SKIP", dest)
            continue

        print("GET ", url)
        urllib.request.urlretrieve(url, dest)

print("Done.")
