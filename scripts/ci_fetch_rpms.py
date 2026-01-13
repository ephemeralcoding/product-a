#!/usr/bin/env python3
import argparse
import shutil
import subprocess
from pathlib import Path
import yaml


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--roles-dir", required=True, type=Path)
    parser.add_argument("--repo-dir", required=True, type=Path)
    parser.add_argument("--clean", action="store_true")
    parser.add_argument("--dnf", default="dnf")
    parser.add_argument("--enablerepo", action="append", default=["crb", "appstream", "baseos"])
    parser.add_argument("--no-weak-deps", action="store_true")
    args = parser.parse_args()

    roles_dir = args.roles_dir
    repo_dir = args.repo_dir

    if not roles_dir.exists():
        raise SystemExit(f"ERROR: roles-dir not found: {roles_dir}")

    packages = []
    seen = set()

    for role_dir in sorted(roles_dir.iterdir()):
        if not role_dir.is_dir():
            continue

        meta = role_dir / "meta" / "packages.yaml"
        if not meta.exists():
            continue

        data = yaml.safe_load(meta.read_text(encoding="utf-8")) or {}
        pkgs = data.get("packages", [])

        if not isinstance(pkgs, list):
            raise SystemExit(f"ERROR: {meta} 'packages' must be a list")

        for p in pkgs:
            if not isinstance(p, str) or not p.strip():
                raise SystemExit(f"ERROR: {meta} contains invalid package: {p!r}")

            p = p.strip()
            if p not in seen:
                seen.add(p)
                packages.append(p)

    if not packages:
        print("No packages found. Nothing to do.")
        repo_dir.mkdir(parents=True, exist_ok=True)
        return

    if args.clean and repo_dir.exists():
        shutil.rmtree(repo_dir)
    repo_dir.mkdir(parents=True, exist_ok=True)

    cmd = [
        args.dnf,
        "-y",
        "download",
        "--resolve",
        "--alldeps",
        f"--destdir={str(repo_dir)}",
    ]

    if args.no_weak_deps:
        cmd.append("--setopt=install_weak_deps=False")

    for r in args.enablerepo:
        cmd.append(f"--enablerepo={r}")

    cmd.extend(packages)

    print("RUN ", " ".join(cmd))
    subprocess.run(cmd, check=True)

    print("RUN createrepo_c", repo_dir)
    subprocess.run(["createrepo_c", str(repo_dir)], check=True)

    print("Done. Local repo created at:", repo_dir)


if __name__ == "__main__":
    main()
