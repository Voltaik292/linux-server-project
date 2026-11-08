#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="linux-server-project"
LOG_DIR="/var/log/${PROJECT_NAME}"
INSTALL_LOG="${LOG_DIR}/install.log"

REPO_NAME="private-local"
REPO_DIR="/var/www/repo"
REPO_FILE="/etc/yum.repos.d/${REPO_NAME}.repo"
PACKAGES=(httpd mod_ssl)

BUILD_TOOLS=(createrepo_c dnf-plugins-core)

log() {
    echo "[$(date)] $*";
}

die() {
    log "ERROR: $*" >&2;
    exit 1;
}

need_root() {
    [[ $EUID -eq 0 ]] || die "Run this script as root";
}
