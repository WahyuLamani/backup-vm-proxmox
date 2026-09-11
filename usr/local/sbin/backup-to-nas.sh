#!/bin/bash

set -euo pipefail

# ============================================================
# Proxmox Backup -> NAS OMV
# ============================================================

# Konfigurasi
VMID="107"
NAS_MOUNT="/mnt/nas-backup"
NAS_BACKUP_DIR="${NAS_MOUNT}/Regional"
LOG_FILE="/var/log/backup-to-nas.log"

# ============================================================
# Fungsi logging
# ============================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# ============================================================
# Validasi argument
# ============================================================

if [ "$#" -ne 1 ]; then
    log "ERROR: Script harus menerima 1 argument berupa file backup."
    exit 1
fi

BACKUP_FILE="$1"

# ============================================================
# Validasi VMID
# ============================================================

case "$(basename "$BACKUP_FILE")" in
    vzdump-qemu-${VMID}-*.vma.zst)
        ;;
    *)
        log "ERROR: File bukan backup VM ${VMID}: $BACKUP_FILE"
        exit 1
        ;;
esac

# ============================================================
# Pastikan file backup ada
# ============================================================

if [ ! -f "$BACKUP_FILE" ]; then
    log "ERROR: File backup tidak ditemukan: $BACKUP_FILE"
    exit 1
fi

# ============================================================
# Pastikan NAS benar-benar ter-mount
# ============================================================

if ! mountpoint -q "$NAS_MOUNT"; then
    log "ERROR: NAS tidak ter-mount di $NAS_MOUNT"
    exit 1
fi

# ============================================================
# Ambil tanggal backup dari nama file
#
# Contoh:
# vzdump-qemu-107-2026_07_19-07_00_01.vma.zst
# menjadi:
# 2026-07-19
# ============================================================

BACKUP_NAME="$(basename "$BACKUP_FILE")"

BACKUP_DATE=$(echo "$BACKUP_NAME" | \
    sed -n 's/^vzdump-qemu-[0-9]*-\([0-9]\{4\}\)_\([0-9]\{2\}\)_\([0-9]\{2\}\)-.*\.vma\.zst$/\1-\2-\3/p')

if [ -z "$BACKUP_DATE" ]; then
    log "ERROR: Tidak dapat menentukan tanggal backup dari nama file."
    exit 1
fi

DEST_DIR="${NAS_BACKUP_DIR}/${BACKUP_DATE}"

# ============================================================
# Buat folder tujuan
# ============================================================

mkdir -p "$DEST_DIR"

log "============================================================"
log "Memulai transfer backup VM ${VMID}"
log "Source : $BACKUP_FILE"
log "Target : $DEST_DIR/$BACKUP_NAME"

# ============================================================
# Ambil ukuran source
# ============================================================

SOURCE_SIZE=$(stat -c%s "$BACKUP_FILE")

log "Ukuran source: $SOURCE_SIZE bytes"

# ============================================================
# Copy backup ke NAS
# ============================================================

rsync -avh --no-owner --no-group --progress \
    "$BACKUP_FILE" \
    "$DEST_DIR/"

# ============================================================
# Pastikan file tujuan ada
# ============================================================

DEST_FILE="${DEST_DIR}/${BACKUP_NAME}"

if [ ! -f "$DEST_FILE" ]; then
    log "ERROR: File hasil transfer tidak ditemukan."
    exit 1
fi

# ============================================================
# Verifikasi ukuran file
# ============================================================

DEST_SIZE=$(stat -c%s "$DEST_FILE")

log "Ukuran target: $DEST_SIZE bytes"

if [ "$SOURCE_SIZE" -ne "$DEST_SIZE" ]; then
    log "ERROR: Ukuran source dan target berbeda!"
    exit 1
fi

log "Verifikasi ukuran: OK"

# ============================================================
# Retention NAS
#
# HANYA folder backup berbentuk YYYY-MM-DD
# Simpan 2 backup terbaru.
#
# Backup lokal TIDAK disentuh.
# ============================================================

log "Memeriksa retention NAS..."

mapfile -t BACKUP_DIRS < <(
    find "$NAS_BACKUP_DIR" \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        -regextype posix-extended \
        -regex '.*/20[0-9]{2}-[0-9]{2}-[0-9]{2}' \
        -printf '%f\n' |
    sort -r
)

DIR_COUNT="${#BACKUP_DIRS[@]}"

log "Jumlah folder backup NAS: $DIR_COUNT"

if [ "$DIR_COUNT" -gt 2 ]; then

    for ((i=2; i<DIR_COUNT; i++)); do

        OLD_DIR="${BACKUP_DIRS[$i]}"
        OLD_PATH="${NAS_BACKUP_DIR}/${OLD_DIR}"

        log "Menghapus backup NAS lama: $OLD_PATH"

        rm -rf -- "$OLD_PATH"

    done

else

    log "Retention tidak perlu dijalankan. Backup NAS <= 2."

fi

# ============================================================
# Selesai
# ============================================================

log "Backup VM ${VMID} berhasil disalin dan diverifikasi."
log "Retention NAS selesai."
log "============================================================"

exit 0
