#!/usr/bin/env bash
set -euo pipefail


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

# list reports
shopt -s nullglob
cd "${METRICS_MOUNT}"
reports=("${REPORT_PREFIX}"*.json)

if [[ ${#reports[@]} -eq 0 ]]; then
    log "No reports to archive"
    exit 0
fi

log "Found ${#reports[@]} reports"


# packing and testing
archive_name="${ARCHIVE_PREFIX}$(date +%Y-%m-%d_%H%M%S).tar.gz"
archive="${BACKUP_MOUNT}/${archive_name}"

tar -czf "${archive}" "${reports[@]}"

if ! tar -tzf "${archive}" > /dev/null; then
    rm -f "${archive}"
    die "Archive test failed, keeping the reports"
fi

log "Archive ${archive_name} is OK"


# checksum, then delete the packed reports
( cd "${BACKUP_MOUNT}" && sha256sum "${archive_name}" > "${archive_name}.sha256" )
rm "${reports[@]}"

log "Checksum written, ${#reports[@]} reports deleted"



# keep only the newest archives
cd "${BACKUP_MOUNT}"
ls "${ARCHIVE_PREFIX}"*.tar.gz | head -n -"${KEEP_ARCHIVES}" | while read -r name; do
    rm -f "${name}" "${name}.sha256"
done

log "Done. Keeping the newest ${KEEP_ARCHIVES} archives."
