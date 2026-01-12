#!/usr/bin/env bash
set -euo pipefail

# Run from the bundle root (the directory that contains ansible.cfg, requirements-py.txt, vendor/, playbooks/)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VENV="${ROOT}/.venv"
WHEELS_DIR="${ROOT}/wheels"
PY_REQS="${ROOT}/requirements-py.txt"
PLAYBOOK="${ROOT}/ansible/playbook.yaml"

if [[ ! -d "${WHEELS_DIR}" ]]; then
  echo "ERROR: Missing wheels directory: ${WHEELS_DIR}"
  exit 1
fi

if [[ ! -f "${PY_REQS}" ]]; then
  echo "ERROR: Missing Python requirements file: ${PY_REQS}"
  exit 1
fi

if [[ ! -f "${PLAYBOOK}" ]]; then
  echo "ERROR: Missing playbook: ${PLAYBOOK}"
  exit 1
fi

# Ensure we use the bundle's ansible.cfg (roles_path should point to ./vendor/roles)
export ANSIBLE_CONFIG="${ROOT}/ansible/ansible.cfg"

# Create venv if needed
if [[ ! -d "${VENV}" ]]; then
  python3 -m venv "${VENV}"
fi

# Activate venv
# shellcheck disable=SC1091
source "${VENV}/bin/activate"

# Install Python deps from bundled wheels (offline)
python -m pip install --no-index --find-links "${WHEELS_DIR}" -r "${PY_REQS}"

# Run Ansible
exec ansible-playbook "${PLAYBOOK}" "$@"
