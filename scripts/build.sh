#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="${ROOT}/dist"
VENDOR="${ROOT}/ansible"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BUNDLE_NAME="bundle"
WORKDIR="${DIST}/${BUNDLE_NAME}"

WHEELS="${ROOT}/wheels"
VENV="${ROOT}/.venv"


#Output shall be converted to a pipeline later on
rm -rf "${DIST}"
mkdir -p "${DIST}" "${VENDOR}/roles" "${VENDOR}/artifacts"

echo "==> Downloading Python wheels into vendor/wheels"
python3 -m pip download \
  --dest "${ROOT}/wheels" \
  --requirement "${ROOT}/requirements-py.txt"

python3 -m venv "${VENV}"
source "${VENV}/bin/activate"
python -m pip install --no-index --find-links "${WHEELS}" -r "${ROOT}/requirements-py.txt"

echo "==> Installing pinned roles into vendor/roles"
ANSIBLE_FORCE_COLOR=0 \
ansible-galaxy role install \
  -r "${VENDOR}/requirements.yaml" \
  -p "${VENDOR}/roles" \
  --force

echo "==> Fetching third-party artifacts declared by roles"
"${ROOT}/scripts/fetch_artifacts.py"

#fix
echo "==> Preparing bundle workdir"
mkdir -p "${WORKDIR}"
rsync -a --delete \
  --exclude '.git/' \
  --exclude 'dist/' \
  --exclude 'stuff/' \
  "${ROOT}/" "${WORKDIR}/"

echo "==> Copying vendor/ (roles + artifacts) into bundle"
mkdir -p "${WORKDIR}/stuff"
rsync -a "${VENDOR}/" "${WORKDIR}/stuff/"

echo "==> Creating tarball"
tar -C "${DIST}" -czf "${DIST}/${BUNDLE_NAME}.tar.gz" "${BUNDLE_NAME}"

echo "==> Done:"
echo "    ${DIST}/${BUNDLE_NAME}.tar.gz"
