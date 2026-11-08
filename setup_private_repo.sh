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


other_enabled="$(dnf repolist --enabled --quiet | awk 'NR>1 {print $1}' | grep -vx "${REPO_NAME}" || true)"

if [[ -z "${other_enabled}" && -f "${REPO_DIR}/repodata/repomd.xml" ]]; then
    log "Repo already built and it is the only enabled repo, skipping download"
else
    log "Downloading packages and their dependencies"
    mkdir -p "${REPO_DIR}/Packages"
    dnf download --resolve --alldeps --destdir "${REPO_DIR}/Packages" "${PACKAGES[@]}"

    log "Creating repo metadata"
    createrepo_c "${REPO_DIR}"
fi

[[ -f "${GPG_KEY}" ]] || die "Distribution GPG key not found in /etc/pki/rpm-gpg/"

log "Writing repo file ${REPO_FILE}"
cat > "${REPO_FILE}" <<EOF
[${REPO_NAME}]
name=Private local repo
baseurl=file://${REPO_DIR}
enabled=1
gpgcheck=1
gpgkey=file://${GPG_KEY}
EOF


log "Disabling every repo except ${REPO_NAME}"
for f in /etc/yum.repos.d/*.repo; do
    if [[ "$f" == "${REPO_FILE}" ]]; then
        continue
    fi
    sed -i 's/^enabled *= *1/enabled=0/' "$f"
done

dnf clean all > /dev/null
log "Enabled repos now:"
dnf repolist --enabled
