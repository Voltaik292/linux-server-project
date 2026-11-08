#!/usr/bin/env bash
set -euo pipefail

PROJECT_NAME="linux-server-project"
LOG_DIR="/var/log/${PROJECT_NAME}"
INSTALL_LOG="${LOG_DIR}/install.log"

REPO_NAME="private-local"
REPO_DIR="/var/www/repo"
REPO_FILE="/etc/yum.repos.d/${REPO_NAME}.repo"
PACKAGES=(httpd mod_ssl openssl firewalld)

BUILD_TOOLS=(createrepo_c dnf-plugins-core)

GPG_KEY="$(ls /etc/pki/rpm-gpg/RPM-GPG-KEY-*"$(rpm -E %rhel)"* 2>/dev/null | head -n 1 || true)"

WEB_USER="webreport"                                    # Name of the appache user
WEB_ROOT="/var/www/html"                                # The folder the apache server serves
HTTPD_CONF="/etc/httpd/conf/httpd.conf"                 # Apache config, where user/group lines are.
TMPFILES_CONF="/etc/tmpfiles.d/httpd.conf"    # Here i will write the rule that keeps web root owned by the appache user, even after reboot.


CERT_FILE="/etc/pki/tls/certs/${PROJECT_NAME}.crt"
KEY_FILE="/etc/pki/tls/private/${PROJECT_NAME}.key"
CERT_DAYS=365
CERT_RENEW_SECONDS=2592000
TRUST_DIR="/etc/pki/ca-trust/source/anchors"
SITE_CONF="/etc/httpd/conf.d/${PROJECT_NAME}.conf"
SITE_ACCESS_LOG="/var/log/httpd/${PROJECT_NAME}-access.log"
SITE_ERROR_LOG="/var/log/httpd/${PROJECT_NAME}-error.log"


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
