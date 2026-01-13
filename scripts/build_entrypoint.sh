#!/usr/bin/env bash
set -euo pipefail

SRC="${SRC:-/src}"      # product repo mounted read-only
OUT="${OUT:-/out}"      # output mounted writeable
WORK="${WORK:-/work}"   # workspace inside container (writeable)

STAMP="${STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"
BUNDLE_NAME="${BUNDLE_NAME:-my-product-${STAMP}}"

# Workspace layout
W_ROLES="${WORK}/ansible/roles"
W_ARTIFACTS="${WORK}/ansible/artifacts"
W_WHEELS="${WORK}/wheels"
W_RPM_REPO="${WORK}/repo"
W_BUNDLE_DIR="${WORK}/bundle"
W_DIST="${WORK}/dist"

rm -rf "${WORK}"
mkdir -p "${W_ROLES}" "${W_ARTIFACTS}" "${W_WHEELS}" "${W_RPM_REPO}" "${W_BUNDLE_DIR}" "${W_DIST}" "${OUT}/dist"

echo "==> Vendor Python wheels"
if [[ -f "${SRC}/requirements-py.txt" ]]; then
  python3 -m pip download -r "${SRC}/requirements-py.txt" -d "${W_WHEELS}"
fi

echo "==> Install Ansible roles into workspace"
if [[ -f "${SRC}/ansible/requirements.yaml" ]]; then
  ANSIBLE_FORCE_COLOR=0 ansible-galaxy role install \
    -r "${SRC}/ansible/requirements.yaml" \
    -p "${W_ROLES}" \
    --force
elif [[ -f "${SRC}/requirements.yml" ]]; then
  ANSIBLE_FORCE_COLOR=0 ansible-galaxy role install \
    -r "${SRC}/requirements.yml" \
    -p "${W_ROLES}" \
    --force
else
  echo "WARN: No role requirements file found. Skipping role install."
fi

echo "==> Fetch third-party artifacts declared by roles"
python3 "${SRC}/scripts/fetch_artifacts.py" \
  --roles-dir "${W_ROLES}" \
  --out-dir "${W_ARTIFACTS}"

echo "==> Fetch RPMs declared by roles"
python3 "${SRC}/scripts/fetch_rpms.py" \
  --roles-dir "${W_ROLES}" \
  --repo-dir "${W_RPM_REPO}" \
  --clean \
  --no-weak-deps

echo "==> Assemble bundle"
mkdir -p "${W_BUNDLE_DIR}/ansible" "${W_BUNDLE_DIR}/vendor" "${W_BUNDLE_DIR}/repo"

# copy product ansible content
rsync -a "${SRC}/ansible/" "${W_BUNDLE_DIR}/ansible/"

# inject generated vendor assets
rsync -a "${WORK}/ansible/" "${W_BUNDLE_DIR}/ansible/"
rsync -a "${W_WHEELS}/" "${W_BUNDLE_DIR}/vendor/wheels/" || true
rsync -a "${W_RPM_REPO}/" "${W_BUNDLE_DIR}/repo/" || true

cat > "${W_BUNDLE_DIR}/manifest.json" <<EOF
{
  "bundle_name": "${BUNDLE_NAME}",
  "stamp_utc": "${STAMP}"
}
EOF

echo "==> Create tarball"
tar -C "${W_BUNDLE_DIR}" -czf "${W_DIST}/${BUNDLE_NAME}.tar.gz" .

echo "==> Export to /out"
cp -f "${W_DIST}/${BUNDLE_NAME}.tar.gz" "${OUT}/dist/"
cp -f "${W_BUNDLE_DIR}/manifest.json" "${OUT}/dist/${BUNDLE_NAME}.manifest.json"

echo "Done: ${OUT}/dist/${BUNDLE_NAME}.tar.gz"
