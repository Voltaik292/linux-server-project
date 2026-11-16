#!/usr/bin/env bash
set -euo pipefail


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}"/config.sh

need_root

host="$(hostname)"
server_ip="$(hostname -I | cut -d' ' -f1)"
failed=0

# check "text" command...  runs the command and prints PASS or FAIL
check() {
    local text="$1"
    shift
    if "$@" > /dev/null 2>&1; then
        echo "PASS  ${text}"
    else
        echo "FAIL  ${text}"
        failed=$((failed + 1))
    fi
}

# ---- the checks go here ----
check "private-local is the only enabled repo" [ "$(dnf repolist --enabled --quiet 2> /dev/null | awk 'NR>1 {print $1}')" = "${REPO_NAME}" ]
check "httpd was installed from private-local" [ "$(dnf info --installed httpd 2> /dev/null | awk '/^From repo/ {print $NF}')" = "${REPO_NAME}" ]



for svc in httpd firewalld crond; do
    check "${svc} is enabled" systemctl is-enabled --quiet "${svc}"
    check "${svc} is running" systemctl is-active --quiet "${svc}"
done


# ---- result ----
if [[ "${failed}" -eq 0 ]]; then
    echo "Site ready: https://${server_ip}/"
else
    echo "${failed} check/checks failed"
    exit 1
fi
