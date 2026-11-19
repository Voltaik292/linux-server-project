#!/usr/bin/env bash
set -euo pipefail


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"


# prints every free real disk, one per line (like /dev/nvme0n2)
# free = nothing is written on it (no filesystem, no partitions, nothing)
# i don't look for names like sdb or vdb, because every virtualization tool names disks differently
find_free_disks() {
    local disk

    # lsblk prints: name, type, read-only, removable, size
    # awk keeps real disks only (no loop, no cdrom, no usb, no empty 0 size ones)
    for disk in $(lsblk -dnbpo NAME,TYPE,RO,RM,SIZE | awk '$2 == "disk" && $3 == 0 && $4 == 0 && $5 > 0 {print $1}'); do
        # if blkid prints nothing, the disk is empty
        if [[ -z "$(blkid -p "${disk}" 2>&1)" ]]; then
            echo "${disk}"
        fi
    done
}


# formats a disk or an image, but only if it is empty
format_if_empty() {
    local device="$1"

    # fs_type = the text blkid prints (for example xfs), empty if nothing found
    # rc = blkid's exit code: 0 = has a filesystem, 2 = empty, anything else = real error
    local fs_type=""
    local rc=0
    fs_type="$(blkid -p -s TYPE -o value "${device}")" || rc=$?

    # i format only when blkid said "empty" (exit code 2)
    # on any other error i stop, so i never format something by mistake
    if [[ "${rc}" -eq 0 ]]; then
        log "${device} already has a ${fs_type} filesystem, not formatting"
    elif [[ "${rc}" -eq 2 ]]; then
        log "${device} has no filesystem, formatting as ${DISK_FS}"
        "mkfs.${DISK_FS}" "${device}"
    else
        die "Could not check ${device} (blkid exit code ${rc})"
    fi
}


# prepares ONE disk, i call it once per disk (metrics, backup)
# $1 = image file, $2 = size, $3 = mount point folder, $4 = a free real disk (empty if there is none)
setup_disk() {
    local img="$1"
    local size="$2"
    local mount_point="$3"
    local free_disk="$4"

    log "Setting up ${mount_point}"

    # if the mount point is already in fstab, an earlier run did all the work, so i skip it
    # (findmnt --fstab looks in /etc/fstab: exit 0 = line exists, 1 = missing)
    if findmnt --fstab --mountpoint "${mount_point}" > /dev/null; then
        log "${mount_point} is already in /etc/fstab, not touching the disk"
    elif [[ -n "${free_disk}" ]]; then
        # i have a free real disk, so i use it
        log "Using the free disk ${free_disk} for ${mount_point}"
        format_if_empty "${free_disk}"

        # in fstab i write the UUID, because the /dev name can change after a reboot
        echo "UUID=$(blkid -p -s UUID -o value "${free_disk}") ${mount_point} ${DISK_FS} ${DISK_OPTIONS_REAL} 0 0" >> /etc/fstab
        systemctl daemon-reload
    else
        # no free disk, so i make an image file and use it as a disk
        # truncate makes a sparse file: big on paper, almost no real space used
        # chmod 0600: only root can read or write the raw disk
        log "No free disk for ${mount_point}, using an image file"
        if [[ ! -f "${img}" ]]; then
            log "Creating ${size} image ${img}"
            truncate -s "${size}" "${img}"
            chmod 0600 "${img}"
        fi
        format_if_empty "${img}"

        echo "${img} ${mount_point} ${DISK_FS} ${DISK_OPTIONS} 0 0" >> /etc/fstab
        systemctl daemon-reload
    fi


    # mount the disk using its fstab line. if the line is wrong, this fails now
    # mountpoint -q: exit 0 if something is mounted on that folder, 1 if not
    if mountpoint -q "${mount_point}"; then
        log "${mount_point} is already mounted"
    else
        log "Mounting ${mount_point}"
        mount "${mount_point}"
    fi

    # because of nofail, mount says "ok" even if the disk is missing, so i check that it is really mounted
    mountpoint -q "${mount_point}" || die "${mount_point} is not mounted, the disk in /etc/fstab is missing?"


    # give the disk to the web user and make it private (only the owner can enter)
    # this must come AFTER mounting: mounting hides the folder underneath, and the
    # new setting is stored inside the disk, so it survives reboots
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



# look for free disks. mapfile puts each line into the list free_disks
mapfile -t free_disks < <(find_free_disks)
log "Free disks found: ${#free_disks[@]}"

# run the setup disk function for both new disks
# the first free disk is for metrics, the second one is for backup
# ${free_disks[0]:-} = the first free disk, or empty if there is none
setup_disk "${METRICS_IMG}" "${METRICS_SIZE}" "${METRICS_MOUNT}" "${free_disks[0]:-}"
setup_disk "${BACKUP_IMG}" "${BACKUP_SIZE}" "${BACKUP_MOUNT}" "${free_disks[1]:-}"


# final fstab check, just incase something weird happened.
# findmnt --verify exits with an error on a real problem. Warnings are fine.
log "Checking /etc/fstab"
findmnt --verify
log "Step 4 done: ${METRICS_MOUNT} and ${BACKUP_MOUNT} are mounted"




