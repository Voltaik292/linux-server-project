#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}"/config.sh

# only root can make the log folder and run the steps, so i check this first
need_root

# the log folder does not exist on a fresh server, and tee can't make it
mkdir -p "${LOG_DIR}"

# running all task steps :
main() {
    number=0
    for step in setup_private_repo.sh install_apache.sh configure_https.sh mount_disks.sh setup_crons.sh verify.sh; do
        number=$((number + 1))
        log "Running ${step} (step ${number})"
        # if a step fails i stop here and say which one (set -e alone would stop without a message)
        "${SCRIPT_DIR}/${step}" || die "Step ${number} (${step}) failed. See ${INSTALL_LOG}"
    done
}

# 2>&1 puts the errors in the same stream. tee shows everything on the screen AND adds it to install.log (-a = do not erase the old log)
main 2>&1 | tee -a "${INSTALL_LOG}"
