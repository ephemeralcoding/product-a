#!/usr/bin/env bash
set -euo pipefail

# Azure DevOps container job environment variables:
#   BUILD_SOURCESDIRECTORY           -> repo checkout path
#   PIPELINE_WORKSPACE              -> workspace root for scratch
#   BUILD_ARTIFACTSTAGINGDIRECTORY   -> artifact staging dir

SRC="${SRC:-${BUILD_SOURCESDIRECTORY:-}}"
WORKROOT="${WORKROOT:-${PIPELINE_WORKSPACE:-}}"
STAGING="${STAGING:-${BUILD_ARTIFACTSTAGINGDIRECTORY:-}}"

if [[ -z "${SRC}" || -z "${WORKROOT}" || -z "${STAGING}" ]]; then
  echo "ERROR: Required env vars not set."
  echo "Expected BUILD_SOURCESDIRECTORY, PIPELINE_WORKSPACE, BUILD_ARTIFACTSTAGINGDIRECTORY."
  echo "Got: SRC='${SRC}', WORKROOT='${WORKROOT}', STAGING='${STAGING}'"
  exit 1
fi

# Contract
WORK="${WORK:-${WORKROOT}/work}"
ROLES_DIR="${ROLES_DIR:-${WORK}/roles}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-${WORK}/artifacts}"
WHEELS_DIR="${WHEELS_DIR:-${WORK}/wheels}"
RPM_REPO_DIR="${RPM_REPO_DIR:-${WORK}/repo}"
BUNDLE_DIR="${BUNDLE_DIR:-${WORK}/bundle}"
DIST_DIR="${DIST_DIR:-${STAGING}/dist}"

STAMP="${STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"
BUNDLE_NAME="${BUNDLE_NAME:-my-product-${STAMP}}"

# Paths to fetch scripts INSIDE the container image
FETCH_ARTIFACTS="${FETCH_ARTIFACTS:-/opt/builder/fetch_artifacts.py}"
FETCH_RPMS="${FETCH_RPMS:-/opt/builder/fetch_rpms.py}"

echo "==> Inputs"
echo "SRC=${SRC}"
echo "==> Outputs"
echo "WORK=${WORK}"
echo "DIST_DIR=${DIST_DIR}"

# Clean workspace
rm -rf "${WORK}"
mkdir -p "${ROLES_DIR}" "${ARTIFACTS_DIR}" "${WHEELS_DIR}" "${RPM_REPO_DIR}" "${BUNDLE_DIR}" "${DIST_DIR}"

# 1) Vendor Python wheels (optional)
if [[ -f "${SRC}/requirements-py.txt" ]]; then
  echo "==> Downloading Python wheels"
  python3 -m pip download \
    --dest "${WHEELS_DIR}" \
    --requirement "${SRC}/requirements-py.txt"
else
  echo "==> requirements-py.txt not found; skipping wheels"
fi

# 2) Install roles (support both common locations)
REQ_ROLES=""
if [[ -f "${SRC}/ansible/requirements.yaml" ]]; then
  REQ_ROLES="${SRC}/ansible/requirements.yaml"
elif [[ -f "${SRC}/ansible/requirements.yml" ]]; then
  REQ_ROLES="${SRC}/ansible/requirements.yml"
elif [[ -f "${SRC}/requirements.yml" ]]; then
  REQ_ROLES="${SRC}/requirements.yml"
elif [[ -f "${SRC}/requirements.yaml" ]]; then
  REQ_ROLES="${SRC}/requirements.yaml"
fi

if [[ -n "${REQ_ROLES}" ]]; then
  echo "==> Installing roles from ${REQ_ROLES}"
  ANSIBLE_FORCE_COLOR=0 ansible-galaxy role install \
    -r "${REQ_ROLES}" \
    -p "${ROLES_DIR}" \
    --force
else
  echo "==> No role requirements file found; skipping role install"
fi

# 3) Fetch third-party artifacts declared by roles
if [[ -f "${FETCH_ARTIFACTS}" ]]; then
  echo "==> Fetching role artifacts"
  python3 "${FETCH_ARTIFACTS}" \
    --roles-dir "${ROLES_DIR}" \
    --out-dir "${ARTIFACTS_DIR}"
else
  echo "==> WARN: fetch_artifacts.py not found at ${FETCH_ARTIFACTS}; skipping"
fi

# 4) Fetch RPMs declared by roles + create local repo
if [[ -f "${FETCH_RPMS}" ]]; then
  echo "==> Fetching RPMs and creating local repo"
  python3 "${FETCH_RPMS}" \
    --roles-dir "${ROLES_DIR}" \
    --repo-dir "${RPM_REPO_DIR}" \
    --clean \
    --no-weak-deps
else
  echo "==> WARN: fetch_rpms.py not found at ${FETCH_RPMS}; skipping"
fi

# 5) Assemble bundle
echo "==> Assembling bundle filesystem"
mkdir -p \
  "${BUNDLE_DIR}/ansible" \
  "${BUNDLE_DIR}/vendor/roles" \
  "${BUNDLE_DIR}/vendor/wheels" \
  "${BUNDLE_DIR}/ansible/artifacts" \
  "${BUNDLE_DIR}/repo"

# Copy product ansible content (if present)
if [[ -d "${SRC}/ansible" ]]; then
  rsync -a "${SRC}/ansible/" "${BUNDLE_DIR}/ansible/"
fi

# Inject generated content
rsync -a "${ROLES_DIR}/" "${BUNDLE_DIR}/vendor/roles/" || true
rsync -a "${WHEELS_DIR}/" "${BUNDLE_DIR}/vendor/wheels/" || true
rsync -a "${ARTIFACTS_DIR}/" "${BUNDLE_DIR}/ansible/artifacts/" || true
rsync -a "${RPM_REPO_DIR}/" "${BUNDLE_DIR}/repo/" || true

# Minimal manifest (extend as needed)
cat > "${BUNDLE_DIR}/manifest.json" <<EOF
{
  "bundle_name": "${BUNDLE_NAME}",
  "stamp_utc": "${STAMP}"
}
EOF

# 6) Create tarball
echo "==> Creating tarball"
tar -C "${BUNDLE_DIR}" -czf "${DIST_DIR}/${BUNDLE_NAME}.tar.gz" .

# Also publish manifest separately (handy in CI)
cp -f "${BUNDLE_DIR}/manifest.json" "${DIST_DIR}/${BUNDLE_NAME}.manifest.json"

echo "==> Done"
echo "Artifact: ${DIST_DIR}/${BUNDLE_NAME}.tar.gz"