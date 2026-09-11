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

fi

exit 0
