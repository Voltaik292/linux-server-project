#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}"/config.sh

need_root
log "Step 3:HTTPS"

log "Installing mod_ssl and openssl"
dnf install -y mod_ssl openssl

SERVER_NAME="$(hostname)"
SERVER_IP="$(hostname -I | cut -d' ' -f1)"

[[ -n "${SERVER_IP}" ]] || die "Could not find the server IP address"
log "Server name: ${SERVER_NAME}, server IP: ${SERVER_IP}"


need_cert="no"

if [[ ! -f "${CERT_FILE}" || ! -f "${KEY_FILE}" ]]; then
    need_cert="yes"
elif ! openssl x509 -in "${CERT_FILE}" -noout -checkend "${CERT_RENEW_SECONDS}" > /dev/null; then
    need_cert="yes"
elif ! openssl x509 -in "${CERT_FILE}" -noout -ext subjectAltName | grep -qwF "${SERVER_IP}"; then
    need_cert="yes"
fi

# Make a new certificate only if the checks above said we need one
if [[ "${need_cert}" == "yes" ]]; then
    log "Creating a new self-signed certificate"

    # -x509: self-signed | -newkey rsa:2048: new 2048-bit key
    # -nodes: no passphrase, so Apache can start at boot by itself
    # -days: validity | -keyout/-out: where the key and certificate go
    # -subj: subject given here, so openssl asks no questions
    # -addext: SAN with the hostname (DNS) and the IP the certificate is valid for
    openssl req -x509 -newkey rsa:2048 -nodes -days "${CERT_DAYS}" \
        -keyout "${KEY_FILE}" -out "${CERT_FILE}" \
        -subj "/CN=${SERVER_NAME}" \
        -addext "subjectAltName=DNS:${SERVER_NAME},IP:${SERVER_IP}"

    # Key: only root can read it. Certificate: public, everyone can read it
    chmod 600 "${KEY_FILE}"
    chmod 644 "${CERT_FILE}"

    # Put the correct SELinux labels on both files
    restorecon "${KEY_FILE}" "${CERT_FILE}"
else
    # Certificate exists, is not expiring soon, and contains the current IP
    log "Certificate is still valid, keeping it"
fi


# Add our certificate to the system trust store
log "Making the server trust its own certificate"
cp "${CERT_FILE}" "${TRUST_DIR}/${PROJECT_NAME}.crt"
update-ca-trust
