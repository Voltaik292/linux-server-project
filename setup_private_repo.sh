#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

need_root
log "Step 1: Setting private repo"

missing=()
for pkg in "${BUILD_TOOLS[@]}"; do
    rpm -q "$pkg" > /dev/null || missing+=("$pkg")
done

log "Checking for required build tools"
log "Required build tools are: ${BUILD_TOOLS[*]}"

if [[ ${#missing[@]} -gt 0 ]]; then
    log "missing build tools ${missing[*]}"
    log "installing the missing build tools..."
    dnf install -y "${missing[@]}"
else
    log "All build tools are already installed"
fi


log "Downloading packages and their dependancies"
mkdir -p "${REPO_DIR}/Packages"
dnf download --resolve --alldeps --destdir "${REPO_DIR}/Packages" "${PACKAGES[@]}"

log "Creating repo metadata"
createrepo_c "${REPO_DIR}"

[[ -f "${GPG_KEY}" ]] || die "Distribution GPT key not found in /etc/pki/rpm-gpg/"

log "Writing repo file ${REPO_FILE}"
cat > "${REPO_FILE}" <<EOF
[${REPO_NAME}]
name=Private local repo
baseurl=file://${REPO_DIR}
enabled=1
gpgcheck=1
gpgkey=file://${GPG_KEY}
EOF
