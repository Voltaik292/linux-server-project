#!/usr/bin/env bash
set -euo pipefail


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

# setup_disk prepares ONE disk, and we call it once per disk (metrics, backup).
# It takes 3 values: $1 = image file, $2 = size, $3 = mount point folder.
setup_disk() {
    local img="$1"
    local size="$2"
    local mount_point="$3"

    log "Setting up ${mount_point}"

    # Create the image file only if it does not exist yet (safe to run again).
    # truncate makes a sparse file: big on paper, almost no real space used.
    # chmod 0600: only root can read or write the raw disk.
    if [[ -f "${img}" ]]; then
        log "Image ${img} already exists, keeping it"
    else
        log "Creating ${size} image ${img}"
        truncate -s "${size}" "${img}"
        chmod 0600 "${img}"
    fi

    # Ask blkid what is inside the image.
    # fs_type = the text blkid prints (for example xfs), empty if nothing found.
    # rc = blkid's exit code, saved only when blkid failed:
    # 0 = has a filesystem, 2 = empty, anything else = real error.
    local fs_type=""
    local rc=0
    fs_type="$(blkid -p -s TYPE -o value "${img}")" || rc=$?

    # Format ONLY when blkid said "empty" (exit code 2).
    # On any other error we stop, so we never format a disk by mistake.
    if [[ "${rc}" -eq 0 ]]; then
        log "${img} already has a ${fs_type} filesystem, not formatting"
    elif [[ "${rc}" -eq 2 ]]; then
        log "${img} has no filesystem, formatting as ${DISK_FS}"
        "mkfs.${DISK_FS}" "${img}"
    else
        die "Could not check ${img} (blkid exit code ${rc})"
    fi


    # Add the disk to /etc/fstab so it is mounted again after every reboot.
    # findmnt looks the mount point up in fstab: exit 0 = line exists, 1 = missing.
    if findmnt --fstab --mountpoint "${mount_point}" > /dev/null; then
        log "${mount_point} is already in /etc/fstab"
    else
        log "Adding ${mount_point} to /etc/fstab"
        echo "${img} ${mount_point} ${DISK_FS} ${DISK_OPTIONS} 0 0" >> /etc/fstab
        systemctl daemon-reload
    fi


    # Mount the disk using its fstab line. If the line is wrong, this fails now,
    # mountpoint -q: exit 0 if something is mounted on that folder, 1 if not.
    if mountpoint -q "${mount_point}"; then
        log "${mount_point} is already mounted"
    else
        log "Mounting ${mount_point}"
        mount "${mount_point}"
    fi

    # now an extra check just to make sure the disk mounted there is really OUR image (same filesystem UUID).
    local mounted_uuid=""
    local image_uuid=""
    mounted_uuid="$(findmnt -n -o UUID --mountpoint "${mount_point}")"
    image_uuid="$(blkid -p -s UUID -o value "${img}")"
    [[ "${mounted_uuid}" == "${image_uuid}" ]] || die "Something else is mounted on ${mount_point}"


    # Give the disk to the web user and make it private (only the owner can enter).
    # This must come AFTER mounting: mounting hides the folder underneath, and the
    # new setting is stored inside the image, so it survives reboots.
    chown "${WEB_USER}:${WEB_USER}" "${mount_point}"
    chmod "${DISK_MODE}" "${mount_point}"

}


need_root
log "Step 4: Disks"


log "Installing xfsprogs"
dnf install -y xfsprogs

log "Creating folders"
mkdir -p "${IMG_DIR}" "${METRICS_MOUNT}" "${BACKUP_MOUNT}"
chmod 0700 "${IMG_DIR}"


# run the setup disk function for both new disks.
setup_disk "${METRICS_IMG}" "${METRICS_SIZE}" "${METRICS_MOUNT}"
setup_disk "${BACKUP_IMG}" "${BACKUP_SIZE}" "${BACKUP_MOUNT}"


# final fstab check, just incase something weird happened.
# findmnt --verify exits with an error on a real problem. Warnings are fine.
log "Checking /etc/fstab"
findmnt --verify
log "Step 4 done: ${METRICS_MOUNT} and ${BACKUP_MOUNT} are mounted"




