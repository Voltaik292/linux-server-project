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

# asks the server for a page and prints only the code (200, 301...), or 000 if it can't connect
http_code() {
    curl -s -o /dev/null -w '%{http_code}' --max-time "${CURL_TIMEOUT}" "$1"
}

# the .sha256 file has only the file name, so i check inside the backup folder (the ( ) keeps the cd inside this function)
archive_ok() (
    cd "${BACKUP_MOUNT}" && sha256sum -c "$(ls "${ARCHIVE_PREFIX}"*.tar.gz | tail -n 1).sha256"
)

# the checks are all below

# i want our own repo to be the only enabled one, nothing from the internet
check "private-local is the only enabled repo" [ "$(dnf repolist --enabled --quiet | awk 'NR>1 {print $1}')" = "${REPO_NAME}" ]

# httpd must come from our own repo
check "httpd was installed from private-local" [ "$(dnf info --installed httpd | awk '/^From repo/ {print $NF}')" = "${REPO_NAME}" ]

# same 2 checks for each service
for svc in httpd firewalld crond; do
    # enabled = it starts by itself after a reboot
    check "${svc} is enabled" systemctl is-enabled --quiet "${svc}"
    # running = it works right now
    check "${svc} is running" systemctl is-active --quiet "${svc}"
done

# the workers must run as webreport (the parent is root, that's normal, so i look for a worker)
check "Apache workers run as ${WEB_USER}" pgrep -u "${WEB_USER}" -x httpd

# https must answer 200, and no -k, so the certificate has to be trusted for real
check "https://${host}/ returns 200" [ "$(http_code "https://${host}/")" = "200" ]

# http must only redirect to https (301)
check "http://${host}/ returns 301" [ "$(http_code "http://${host}/")" = "301" ]

# the repo has to be reachable over https too
check "https://${host}/repo/repodata/repomd.xml returns 200" [ "$(http_code "https://${host}/repo/repodata/repomd.xml")" = "200" ]

# same 2 checks for each disk
for dir in "${METRICS_MOUNT}" "${BACKUP_MOUNT}"; do
    # something is mounted on this folder right now
    check "${dir} is mounted" mountpoint -q "${dir}"
    # there is a line in /etc/fstab, so the disk comes back after a reboot
    check "${dir} is in /etc/fstab" findmnt --fstab --mountpoint "${dir}"
done

# the whole fstab file has no errors (warnings are ok)
check "/etc/fstab passes the check" findmnt --verify

# cron must have rewritten the status page in the last 3 minutes
check "index.html was updated in the last ${PAGE_MAX_AGE} minutes" test -n "$(find "${WEB_INDEX}" -mmin -"${PAGE_MAX_AGE}")"

# there is a backup archive and its checksum is still right
check "an archive exists and its checksum matches" archive_ok

# SELinux must be on: not Permissive and not Disabled
check "SELinux is Enforcing" [ "$(getenforce)" = "Enforcing" ]

# final results
if [[ "${failed}" -eq 0 ]]; then
    echo "Site ready: https://${server_ip}/"
else
    echo "${failed} check/checks failed"
    exit 1
fi
