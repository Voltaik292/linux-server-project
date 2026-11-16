#!/usr/bin/env bash
set -euo pipefail


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

need_root
log "Step 5: reports, archives and cron"

# install tools
dnf install -y jq cronie logrotate

# copy the scripts, so webreport can run them
install -d -m 0755 "${INSTALL_DIR}"
install -m 0755 "${SCRIPT_DIR}/generate_report.sh" "${INSTALL_DIR}/"
install -m 0755 "${SCRIPT_DIR}/archive_reports.sh" "${INSTALL_DIR}/"
install -m 0644 "${SCRIPT_DIR}/config.sh" "${INSTALL_DIR}/"
restorecon -R "${INSTALL_DIR}"

# the log file the cron jobs write to
mkdir -p "${LOG_DIR}"
touch "${CRON_LOG}"
chown "${WEB_USER}:${WEB_USER}" "${CRON_LOG}"
chmod 0640 "${CRON_LOG}"

log "Tools installed, scripts copied to ${INSTALL_DIR}"


# --- Part 4: the cron file ---
cat > "${CRON_FILE}" <<CRON
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
HOME=/
MAILTO=""
${REPORT_SCHEDULE} ${WEB_USER} ${INSTALL_DIR}/generate_report.sh >> ${CRON_LOG} 2>&1
${ARCHIVE_SCHEDULE} ${WEB_USER} ${INSTALL_DIR}/archive_reports.sh >> ${CRON_LOG} 2>&1
CRON
chmod 0644 "${CRON_FILE}"

# log rotation
cat > "${LOGROTATE_FILE}" <<ROTATE
${CRON_LOG} {
    daily
    rotate ${LOG_KEEP_DAYS}
    compress
    missingok
    notifempty
    create 0640 ${WEB_USER} ${WEB_USER}
}
ROTATE
chmod 0644 "${LOGROTATE_FILE}"

# start cron and logrotate
systemctl enable --now crond
systemctl enable --now logrotate.timer


# run the jobs once, as webreport ---
runuser -u "${WEB_USER}" -- "${INSTALL_DIR}/generate_report.sh"
runuser -u "${WEB_USER}" -- "${INSTALL_DIR}/archive_reports.sh"
runuser -u "${WEB_USER}" -- "${INSTALL_DIR}/generate_report.sh"

log "Step 5 done. Cron runs the report every minute and the archive every 10 minutes."
