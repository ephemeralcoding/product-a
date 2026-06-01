#!/usr/bin/env python3
"""
Orchestrator for hypervisor-fleet builds.

Reads the build manifest produced by the generator, downloads ISOs from
Artifactory, runs Packer per build. Observability over cleverness:
every step prints what it's about to do, before doing it.

Usage:
    python orchestrator/run.py build-one --build-id <id>
    python orchestrator/run.py build-all
    python orchestrator/run.py ensure-iso --build-id <id>
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
MANIFEST = REPO_ROOT / "output" / "build_manifest.yml"
INFRA = REPO_ROOT / "infra.yml"
ISO_CACHE = REPO_ROOT / "iso-cache"
PACKER_DIR = REPO_ROOT / "packer"

REQUIRED_ENV = ["ARTIFACTORY_TOKEN", "PACKER_WINRM_PASSWORD"]


# ---------------------------------------------------------------------------
# Output helpers — every action is announced
# ---------------------------------------------------------------------------

def step(msg: str) -> None:
    """Print a high-level step header. Visible in logs without grep."""
    print(f"\n=== {msg} ===", flush=True)


def info(msg: str) -> None:
    print(f"    {msg}", flush=True)


def cmd(args: list[str]) -> None:
    """Print a command before running it. Operators can copy-paste to re-run manually."""
    printable = " ".join(args)
    print(f"  $ {printable}", flush=True)


def fail(msg: str, code: int = 1) -> None:
    print(f"\nERROR: {msg}", file=sys.stderr, flush=True)
    sys.exit(code)


# ---------------------------------------------------------------------------
# Environment / .env
# ---------------------------------------------------------------------------

def load_dotenv_if_exists() -> None:
    """Populate os.environ from .env if present. CI: no-op (file absent)."""
    dotenv = REPO_ROOT / ".env"
    if not dotenv.exists():
        info(f".env not found at {dotenv} (CI mode: expecting env vars from pipeline)")
        return

    info(f"Loading .env from {dotenv}")
    for line in dotenv.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export "):]
        key, _, value = line.partition("=")
        value = value.strip().strip('"').strip("'")
        # Don't overwrite already-set env (CI wins over .env if both)
        os.environ.setdefault(key.strip(), value)


def require_env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        fail(
            f"{name} is not set.\n"
            f"  Local: ensure .env exists and defines {name}\n"
            f"  CI:    inject {name} as a pipeline secret variable"
        )
    return value


def validate_environment() -> None:
    step("Validating environment")
    for name in REQUIRED_ENV:
        require_env(name)
        info(f"  {name}: set ({len(os.environ[name])} chars)")


# ---------------------------------------------------------------------------
# File loaders
# ---------------------------------------------------------------------------

def load_yaml(path: Path) -> dict[str, Any]:
    if not path.exists():
        fail(f"Missing file: {path}")
    info(f"Reading {path.relative_to(REPO_ROOT)}")
    with open(path) as f:
        return yaml.safe_load(f)


def load_manifest() -> list[dict[str, Any]]:
    data = load_yaml(MANIFEST)
    builds = data.get("builds", [])
    if not builds:
        fail(f"{MANIFEST.name} has no builds. Did you run 'make generate'?")
    return builds


def find_build(build_id: str, manifest: list[dict[str, Any]]) -> dict[str, Any]:
    for b in manifest:
        if b["id"] == build_id:
            return b
    ids = [b["id"] for b in manifest]
    fail(f"Unknown build_id: {build_id!r}. Known: {', '.join(ids)}")


# ---------------------------------------------------------------------------
# ISO cache
# ---------------------------------------------------------------------------

def ensure_iso(base_os: str, infra: dict[str, Any]) -> None:
    step(f"Ensure ISO: {base_os}")
    ISO_CACHE.mkdir(exist_ok=True)
    iso_path = ISO_CACHE / f"{base_os}.iso"
    sha_path = ISO_CACHE / f"{base_os}.iso.sha256"

    if iso_path.exists() and sha_path.exists():
        info(f"Cached: {iso_path.relative_to(REPO_ROOT)}")
        return

    url_base = f"{infra['artifactory']['url']}{infra['artifactory']['iso_path']}"
    token = require_env("ARTIFACTORY_TOKEN")

    for url, dest in [
        (f"{url_base}{base_os}.iso", iso_path),
        (f"{url_base}{base_os}.iso.sha256", sha_path),
    ]:
        info(f"Downloading {url}")
        info(f"  -> {dest.relative_to(REPO_ROOT)}")
        args = [
            "curl", "-fsS",
            "-H", f"Authorization: Bearer {token}",
            "-o", str(dest),
            url,
        ]
        # Don't print the token in the command echo
        printable = [a if "Bearer " not in a else "Authorization: Bearer ***" for a in args]
        cmd(printable)
        result = subprocess.run(args, check=False)
        if result.returncode != 0:
            fail(f"Failed to download {url} (exit {result.returncode})")


# ---------------------------------------------------------------------------
# Packer
# ---------------------------------------------------------------------------

def run_packer(build: dict[str, Any]) -> None:
    step(f"Build: {build['id']}")
    info(f"location:      {build['location']}")
    info(f"host:          {build['host']}")
    info(f"base_os:       {build['base_os']}")
    info(f"build_version: {build['build_version']}")

    pkrvars = (
        REPO_ROOT / "output" / "builds" / build["id"] / f"{build['host']}.pkrvars.hcl"
    )
    if not pkrvars.exists():
        fail(f"Missing pkrvars file: {pkrvars}")

    env = os.environ.copy()
    env["ANSIBLE_CONFIG"] = str(REPO_ROOT / "output" / "ansible.cfg")
    env["ANSIBLE_GALAXY_SERVER_MYCOMPANY_ARTIFACTORY_TOKEN"] = env["ARTIFACTORY_TOKEN"]

    info("Running: packer init")
    cmd(["packer", "init", "."])
    result = subprocess.run(
        ["packer", "init", "."],
        cwd=PACKER_DIR,
        env=env,
        check=False,
    )
    if result.returncode != 0:
        fail(f"packer init failed (exit {result.returncode})")

    info("Running: packer build")
    packer_cmd = [
        "packer", "build",
        "-var-file", str(pkrvars.relative_to(PACKER_DIR.parent) if pkrvars.is_relative_to(PACKER_DIR.parent) else pkrvars),
        ".",
    ]
    cmd(packer_cmd)
    result = subprocess.run(
        packer_cmd,
        cwd=PACKER_DIR,
        env=env,
        check=False,
    )
    if result.returncode != 0:
        fail(f"packer build failed for {build['id']} (exit {result.returncode})")

    info(f"Build complete: {build['id']}")


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def cmd_ensure_iso(args) -> None:
    validate_environment()
    infra = load_yaml(INFRA)
    manifest = load_manifest()
    build = find_build(args.build_id, manifest)
    ensure_iso(build["base_os"], infra)


def cmd_build_one(args) -> None:
    validate_environment()
    infra = load_yaml(INFRA)
    manifest = load_manifest()
    build = find_build(args.build_id, manifest)
    ensure_iso(build["base_os"], infra)
    run_packer(build)


def cmd_build_all(args) -> None:
    validate_environment()
    infra = load_yaml(INFRA)
    manifest = load_manifest()
    step(f"Building all ({len(manifest)} builds, sequentially)")
    for b in manifest:
        info(f"  - {b['id']}")
    for b in manifest:
        ensure_iso(b["base_os"], infra)
        run_packer(b)
    step("All builds complete")


# ---------------------------------------------------------------------------
# Entry
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="hypervisor-fleet build orchestrator")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_iso = sub.add_parser("ensure-iso", help="Download ISO for a build (if not cached)")
    p_iso.add_argument("--build-id", required=True)
    p_iso.set_defaults(func=cmd_ensure_iso)

    p_one = sub.add_parser("build-one", help="Build one image")
    p_one.add_argument("--build-id", required=True)
    p_one.set_defaults(func=cmd_build_one)

    p_all = sub.add_parser("build-all", help="Build every image in the manifest, sequentially")
    p_all.set_defaults(func=cmd_build_all)

    args = parser.parse_args()

    load_dotenv_if_exists()
    args.func(args)


if __name__ == "__main__":
    main()
