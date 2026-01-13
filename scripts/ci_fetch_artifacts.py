#!/usr/bin/env python3
import argparse
from pathlib import Path
import urllib.request
import yaml


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--roles-dir", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    args = parser.parse_args()

    roles_dir = args.roles_dir
    out_dir = args.out_dir

    if not roles_dir.exists():
        raise SystemExit(f"ERROR: roles-dir not found: {roles_dir}")

    out_dir.mkdir(parents=True, exist_ok=True)

    for role_dir in sorted(roles_dir.iterdir()):
        if not role_dir.is_dir():
            continue

        meta = role_dir / "meta" / "artifacts.yaml"
        if not meta.exists():
            continue

        data = yaml.safe_load(meta.read_text(encoding="utf-8")) or {}
        artifacts = data.get("artifacts", [])

        if not isinstance(artifacts, list):
            raise SystemExit(f"ERROR: {meta} 'artifacts' must be a list")

        for item in artifacts:
            if not isinstance(item, dict):
                raise SystemExit(f"ERROR: {meta} artifact entry must be a dict")
            if "url" not in item:
                raise SystemExit(f"ERROR: {meta} artifact missing 'url'")

            url = str(item["url"])
            name = item.get("name") or url.rstrip("/").split("/")[-1]
            dest = out_dir / name

            dest.parent.mkdir(parents=True, exist_ok=True)

            if dest.exists() and dest.stat().st_size > 0:
                print("SKIP", dest)
                continue

            print("GET ", url)
            urllib.request.urlretrieve(url, dest)

    print("Done.")


if __name__ == "__main__":
    main()
