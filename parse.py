#!/usr/bin/env python3
"""Read SoT files, emit per-build configs and a build manifest."""

import sys
import yaml
from pathlib import Path
from jinja2 import Environment, FileSystemLoader

REPO_ROOT = Path(__file__).resolve().parent.parent
SOT_DIR = REPO_ROOT / "sot"
OUT_DIR = REPO_ROOT / "generated"
TEMPLATES_DIR = Path(__file__).resolve().parent / "templates"


def load_sot_files():
    """Load every YAML file under sot/ as one location each."""
    locations = []
    for path in sorted(SOT_DIR.glob("*.yml")):
        with open(path) as f:
            loc = yaml.safe_load(f)
        validate_location(loc, path)
        locations.append(loc)
    return locations


def validate_location(loc, path):
    """Cheap structural checks — fail loud on malformed SoT."""
    if "location" not in loc:
        raise ValueError(f"{path}: missing 'location'")
    if "hosts" not in loc or not loc["hosts"]:
        raise ValueError(f"{path}: missing or empty 'hosts'")

    for host_name, host in loc["hosts"].items():
        if "-" in host_name:
            raise ValueError(
                f"{path}: host name '{host_name}' contains hyphen "
                f"(use underscore)"
            )
        for required in ("image", "instance"):
            if required not in host:
                raise ValueError(
                    f"{path}: host '{host_name}' missing '{required}' section"
                )


def build_id(location, host_name):
    return f"{location}__{host_name}"


def render(env, template_name, ctx, out_path):
    template = env.get_template(template_name)
    rendered = template.render(**ctx)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(rendered)
    print(f"  wrote {out_path.relative_to(REPO_ROOT)}")


def main():
    OUT_DIR.mkdir(exist_ok=True)
    env = Environment(
        loader=FileSystemLoader(TEMPLATES_DIR),
        trim_blocks=True,
        lstrip_blocks=True,
        keep_trailing_newline=True,
    )

    locations = load_sot_files()
    all_builds = []

    for loc in locations:
        location_name = loc["location"]
        print(f"Location: {location_name}")
        for host_name, host in loc["hosts"].items():
            bid = build_id(location_name, host_name)
            build_dir = OUT_DIR / "builds" / bid

            ctx = {
                "build_id": bid,
                "location": location_name,
                "host_name": host_name,
                "image": host["image"],
                "instance": host["instance"],
            }

            render(env, "requirements.yml.j2", ctx,
                   build_dir / "requirements.yml")
            render(env, "build-vars.yml.j2", ctx,
                   build_dir / "build-vars.yml")

            all_builds.append({
                "id": bid,
                "location": location_name,
                "host": host_name,
                "base_os": host["image"]["base_os"],
                "disk_size_gb": host["image"]["disk_size_gb"],
            })

    render(env, "build_manifest.yml.j2", {"builds": all_builds},
           OUT_DIR / "build_manifest.yml")
    print(f"\nGenerated {len(all_builds)} build(s).")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError) as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)
