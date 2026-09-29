#!/bin/bash

# ============================================================
# Proxmox Vzdump Hook
# Backup VM 107 -> NAS Regional
# ============================================================

PHASE="$1"
MODE="$2"
VMID="$3"

LOG_FILE="/var/log/backup-to-nas.log"
BACKUP_SCRIPT="/usr/local/sbin/backup-to-nas.sh"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] HOOK: $1" | tee -a "$LOG_FILE"
}

# Hanya jalankan transfer setelah backup selesai
if [ "$PHASE" = "backup-end" ]; then

    # Hanya VM 107
    if [ "$VMID" != "107" ]; then
        exit 0
    fi

    # TARGET berisi file backup yang baru selesai dibuat
    TARGET="${TARGET:-}"

    if [ -z "$TARGET" ]; then
        log "ERROR: TARGET tidak tersedia."
        exit 1
    fi

    log "Backup VM ${VMID} selesai."
    log "TARGET: $TARGET"

    # Jalankan script transfer ke NAS
    "$BACKUP_SCRIPT" "$TARGET"

    RESULT=$?

    if [ "$RESULT" -ne 0 ]; then
        log "ERROR: Transfer backup ke NAS gagal."
        exit "$RESULT"
    fi

    log "Transfer backup VM ${VMID} ke NAS berhasil."

    # ========================================================
    # Trigger DR Restore di Proxmox B
    # Hanya dijalankan setelah backup ke NAS berhasil
    # ========================================================

    DR_HOST="192.168.71.205"
    DR_VM_NAME="ONEMDORAYA"
    DR_RESTORE_SCRIPT="/usr/local/sbin/dr-restore-reusable.sh"

    log "Memulai trigger DR restore di Proxmox B ${DR_HOST}..."
    log "DR Engine: ${DR_RESTORE_SCRIPT} ${DR_VM_NAME}"

    ssh -o BatchMode=yes \
        -o ConnectTimeout=30 \
        "root@${DR_HOST}" \
        "nohup ${DR_RESTORE_SCRIPT} ${DR_VM_NAME} >/dev/null 2>&1 </dev/null &"

    DR_RESULT=$?

    if [ "$DR_RESULT" -ne 0 ]; then
        log "ERROR: Gagal melakukan trigger DR restore di Proxmox B. Exit code: ${DR_RESULT}"
        exit "$DR_RESULT"
    fi

    log "DR restore berhasil ditrigger di Proxmox B."
    log "Proxmox A tidak menunggu proses DR restore selesai."
fi

exit 0
