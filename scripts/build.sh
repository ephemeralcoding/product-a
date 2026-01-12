#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="${ROOT}/dist"
VENDOR="${ROOT}/ansible"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BUNDLE_NAME="my-product-${STAMP}"
WORKDIR="${DIST}/${BUNDLE_NAME}"

#rm -rf "${DIST}" "${VENDOR}"
mkdir -p "${DIST}" "${VENDOR}/roles" "${VENDOR}/artifacts"

echo "==> Downloading Python wheels into vendor/wheels"
python3 -m pip download \
  --dest "${ROOT}/wheels" \
  --requirement "${ROOT}/requirements-py.txt"

echo "==> Installing pinned roles into vendor/roles"
ANSIBLE_FORCE_COLOR=0 \
ansible-galaxy role install \
  -r "${ROOT}/requirements.yml" \
  -p "${VENDOR}/roles" \
  --force

echo "==> Fetching third-party artifacts declared by roles"
"${ROOT}/scripts/fetch_artifacts.py"

echo "==> Preparing bundle workdir"
mkdir -p "${WORKDIR}"
rsync -a --delete \
  --exclude '.git/' \
  --exclude 'dist/' \
  --exclude 'vendor/' \
  "${ROOT}/" "${WORKDIR}/"

echo "==> Copying vendor/ (roles + artifacts) into bundle"
mkdir -p "${WORKDIR}/vendor"
rsync -a "${VENDOR}/" "${WORKDIR}/vendor/"

cat > "${WORKDIR}/BUNDLE_MANIFEST.txt" <<EOF
Bundle: ${BUNDLE_NAME}
Build timestamp (UTC): ${STAMP}

Roles requirements:
$(sed 's/^/  /' "${ROOT}/requirements.yml")

Vendored roles:
$(ls -1 "${VENDOR}/roles" | sed 's/^/  /' || true)

Vendored artifacts per role:
$(find "${VENDOR}/artifacts" -mindepth 2 -maxdepth 2 -type f 2>/dev/null | sed 's|^|  |' || true)
EOF

echo "==> Creating tarball"
tar -C "${DIST}" -czf "${DIST}/${BUNDLE_NAME}.tar.gz" "${BUNDLE_NAME}"

echo "==> Done:"
echo "    ${DIST}/${BUNDLE_NAME}.tar.gz"
