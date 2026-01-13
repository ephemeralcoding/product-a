#!/usr/bin/env python3
import sys
import shutil
import subprocess
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
ROLES_DIR = ROOT / "ansible" / "roles"
REPO_DIR = ROOT / "repo"

if not ROLES_DIR.exists():
    print("ERROR: vendor/roles not found. Run ansible-galaxy role install first.", file=sys.stderr)
    sys.exit(1)

# Start fresh
if REPO_DIR.exists():
    shutil.rmtree(REPO_DIR)
REPO_DIR.mkdir(parents=True, exist_ok=True)

packages = []

# Collect packages from all roles
for role_dir in sorted(ROLES_DIR.iterdir()):
    meta = role_dir / "meta" / "packages.yaml"
    if not meta.exists():
        continue

    data = yaml.safe_load(meta.read_text(encoding="utf-8")) or {}
    pkgs = data.get("packages", [])

    if not pkgs:
        continue

    if not isinstance(pkgs, list):
        print(f"ERROR: {meta} must contain 'packages:' as a list.", file=sys.stderr)
        sys.exit(1)

    for p in pkgs:
        if not isinstance(p, str) or not p.strip():
            print(f"ERROR: {meta} contains an invalid package name: {p!r}", file=sys.stderr)
            sys.exit(1)
        packages.append(p.strip())

# Deduplicate while preserving order
seen = set()
packages = [p for p in packages if not (p in seen or seen.add(p))]

if not packages:
    print("No packages found (no meta/packages.yml files or lists were empty).")
    sys.exit(0)

print("Packages to download:")
for p in packages:
    print("  -", p)

# Download RPMs + dependencies into vendor/repo/
cmd = [
    "dnf", "-y", "download",
    "--resolve",
    "--alldeps",
    f"--destdir={str(REPO_DIR)}",
    *packages
]
print("RUN ", " ".join(cmd))
subprocess.run(cmd, check=True)

# Create repo metadata
cmd = ["createrepo_c", str(REPO_DIR)]
print("RUN ", " ".join(cmd))
subprocess.run(cmd, check=True)

print("Done. Local repo created at:", REPO_DIR)
