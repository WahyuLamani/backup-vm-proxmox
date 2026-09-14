# Standar Implementasi Backup Proxmox VM ke NAS OpenMediaVault

**Dokumen:** Backup Proxmox → NAS OMV  
**Versi:** 1.0  
**Status:** Template Implementasi  
**Tujuan:** Menjadi standar baku pemasangan backup VM Proxmox ke NAS OpenMediaVault pada server lain.

---

## 1. Tujuan

ini digunakan untuk membangun mekanisme backup dengan alur:

**PROXMOX → BACKUP LOKAL → BACKUP SELESAI → BACKUP KE NAS OMV → RETENTION**

Prinsip utama:

1. Backup VM tetap dibuat terlebih dahulu pada storage lokal Proxmox.
2. Setelah backup lokal selesai, file backup otomatis disalin ke NAS OMV.
3. File di NAS diverifikasi berdasarkan ukuran file.
4. Retention hanya diterapkan pada backup di NAS.
5. Backup lokal Proxmox **tidak dihapus oleh mekanisme retention NAS**.
6. Retention NAS menyimpan **2 backup terbaru**.
7. Backup menggunakan snapshot mode sehingga VM tetap berjalan selama proses backup.

---

# 2. Arsitektur

```text
                         ┌──────────────────────┐
                         │      VM Proxmox       │
                         │       VMID: xxx       │
                         └──────────┬───────────┘
                                    │
                                    │ Vzdump
                                    ▼
                         ┌──────────────────────┐
                         │  Backup Lokal PVE    │
                         │ /var/lib/vz/dump/    │
                         └──────────┬───────────┘
                                    │
                              backup-end
                                    │
                                    ▼
                         ┌──────────────────────┐
                         │    Hook Script PVE   │
                         │  vzdump-hook.sh       │
                         └──────────┬───────────┘
                                    │
                                    ▼
                         ┌──────────────────────┐
                         │ Backup-to-NAS Script │
                         │ backup-to-nas.sh      │
                         └──────────┬───────────┘
                                    │
                                  NFS
                                    │
                                    ▼
                    ┌──────────────────────────────┐
                    │      NAS OpenMediaVault      │
                    │      /export/Backup_VM        │
                    │                              │
                    │      /Regional/               │
                    │        ├── YYYY-MM-DD/        │
                    │        ├── YYYY-MM-DD/        │
                    │        └── ...                │
                    └──────────────────────────────┘
```

---

# 3. Komponen yang Digunakan

| Komponen                     | Fungsi                                           |
| ---------------------------- | ------------------------------------------------ |
| Proxmox VE                   | Menjalankan VM dan membuat backup                |
| `vzdump`                     | Membuat backup VM                                |
| Vzdump Hook                  | Menjalankan proses setelah backup selesai        |
| `backup-to-nas.sh`           | Menyalin backup ke NAS dan menjalankan retention |
| OpenMediaVault               | Menyediakan storage NAS                          |
| NFS                          | Protokol akses Proxmox ke NAS                    |
| `/etc/fstab`                 | Membuat mount NFS permanen                       |
| `/etc/vzdump.conf`           | Mengaktifkan hook script                         |
| `/var/log/backup-to-nas.log` | Log proses transfer dan retention                |

---

# 4. Variabel yang Wajib Disesuaikan per Server

Sebelum implementasi, tentukan parameter berikut.

| Parameter            | Contoh              | Wajib Disesuaikan   |
| -------------------- | ------------------- | ------------------- |
| Hostname Proxmox     | `mdorgl`            | Ya                  |
| VMID                 | `107`               | Ya                  |
| IP NAS OMV           | `192.168.71.211`    | Ya                  |
| NFS Export           | `/export/Backup_VM` | Ya                  |
| Mount Point          | `/mnt/nas-backup`   | Bisa tetap          |
| Folder NAS           | `/Regional/`        | Ya                  |
| Storage backup lokal | `local`             | Sesuaikan           |
| Folder backup lokal  | `/var/lib/vz/dump/` | Sesuaikan           |
| Jadwal backup        | Minggu 07:00        | Sesuaikan kebutuhan |
| Retention NAS        | 2 backup            | Sesuaikan kebijakan |

**Catatan:** File `.sh` yang digunakan untuk implementasi sudah disiapkan terpisah. Prosedure ini hanya menjelaskan tata cara implementasinya.

---

# 5. Prasyarat Implementasi

## 5.1 Akses Administrator

Pastikan memiliki akses `root` ke Proxmox.

Verifikasi:

```bash
whoami
```

Hasil yang diharapkan:

```text
root
```

---

## 5.2 Pastikan VMID Benar

Verifikasi daftar VM:

```bash
qm list
```

Pastikan VM yang akan dibackup memiliki VMID yang sesuai.

Contoh:

```text
VMID  NAME
107   server-aplikasi
```

---

## 5.3 Pastikan VM Beroperasi Normal

VM boleh dalam keadaan running.

Backup menggunakan:

```text
--mode snapshot
```

Dengan snapshot mode, backup dapat dilakukan tanpa menghentikan VM.

Tetap pastikan workload VM dalam kondisi normal sebelum implementasi.

---

# 6. Prasyarat Waktu Server

Waktu server harus benar sebelum membuat sistem backup otomatis.

Verifikasi:

```bash
date
timedatectl
```

Pastikan timezone sesuai lokasi server.

Contoh:

```text
Asia/Makassar
```

Untuk server di wilayah WITA:

```bash
timedatectl set-timezone Asia/Makassar
```

## Catatan Penting

Jika Proxmox tidak mempunyai akses NTP/Internet, jangan membuat sistem backup bergantung pada sinkronisasi NTP yang tidak tersedia.

Jika sinkronisasi otomatis memang tidak dapat digunakan, waktu server dapat dikoreksi secara manual sesuai kebijakan operasional.

Setelah koreksi waktu, verifikasi:

```bash
date
timedatectl
hwclock
```

Waktu yang benar penting karena nama file backup dan folder retention menggunakan tanggal.

---

# 7. Prasyarat NAS OpenMediaVault

Pastikan OMV:

1. Aktif dan dapat dijangkau dari Proxmox.
2. NFS Server aktif.
3. Export NFS sudah dibuat.
4. Proxmox diizinkan mengakses export tersebut.
5. Folder tujuan dapat ditulis oleh Proxmox.
6. Kapasitas NAS mencukupi.
7. Jaringan antara Proxmox dan NAS stabil.

Contoh:

```text
NAS IP       : 192.168.71.211
NFS Export   : /export/Backup_VM
```

---

# 8. Konfigurasi NFS di OMV

Pada OMV, pastikan NFS Share mengarah ke storage backup.

Contoh export:

```text
/export/Backup_VM
```

Aturan akses harus mengizinkan IP Proxmox.

Contoh:

```text
Proxmox IP → read/write
```

Jika menggunakan opsi tambahan, konfigurasi yang telah digunakan pada implementasi referensi adalah:

```text
subtree_check,insecure
```

Sesuaikan dengan kebijakan keamanan jaringan masing-masing.

---

# 9. Pengujian Akses NFS dari Proxmox

Buat mount point:

```bash
mkdir -p /mnt/nas-backup
```

Lakukan mount sementara untuk pengujian:

```bash
mount -t nfs -o vers=3 192.168.71.211:/export/Backup_VM /mnt/nas-backup
```

Verifikasi:

```bash
mountpoint -q /mnt/nas-backup && echo "NFS OK"
```

Atau:

```bash
mount | grep /mnt/nas-backup
```

---

# 10. Pengujian Write Permission

Buat file pengujian:

```bash
touch /mnt/nas-backup/test-proxmox-write
```

Verifikasi:

```bash
ls -l /mnt/nas-backup/test-proxmox-write
```

Jika berhasil, hapus:

```bash
rm -f /mnt/nas-backup/test-proxmox-write
```

**Jangan melanjutkan implementasi backup otomatis apabila Proxmox belum dapat menulis ke NAS.**

---

# 11. Membuat Folder Tujuan Backup

Contoh:

```bash
mkdir -p /mnt/nas-backup/Regional
```

Verifikasi:

```bash
ls -ld /mnt/nas-backup/Regional
```

Folder inilah yang digunakan sebagai root backup NAS.

Struktur akhirnya:

```text
/mnt/nas-backup/
└── Regional/
```

---

# 12. Membuat Mount NFS Permanen

Edit:

```bash
nano /etc/fstab
```

Tambahkan:

```text
192.168.71.211:/export/Backup_VM /mnt/nas-backup nfs defaults,_netdev 0 0
```

Sesuaikan IP dan export dengan server masing-masing.

## Arti `_netdev`

`_netdev` memberi tahu sistem bahwa filesystem membutuhkan jaringan sehingga mount tidak diperlakukan seperti disk lokal biasa.

---

# 13. Uji Konfigurasi `/etc/fstab`

Jalankan:

```bash
mount -a
```

Jika tidak ada error, verifikasi:

```bash
mountpoint -q /mnt/nas-backup && echo "NFS mount OK"
```

Verifikasi detail:

```bash
mount | grep /mnt/nas-backup
```

**Tidak wajib melakukan reboot server produksi hanya untuk menguji `/etc/fstab`.**

`mount -a` sudah dapat digunakan untuk memvalidasi konfigurasi mount.

---

# 14. Verifikasi Storage Backup Lokal Proxmox

Periksa storage:

```bash
pvesm status
```

Pastikan storage backup lokal aktif.

Contoh:

```text
local       active
local-zfs   active
```

Periksa folder backup:

```bash
ls -lh /var/lib/vz/dump/
```

Backup lokal umumnya mempunyai format:

```text
vzdump-qemu-VMID-YYYY_MM_DD-HH_MM_SS.vma.zst
```

Contoh:

```text
vzdump-qemu-107-2026_08_02-07_00_02.vma.zst
```

---

# 15. Konfigurasi Jadwal Backup Proxmox

Periksa jadwal:

```bash
cat /etc/pve/vzdump.cron
```

Contoh konfigurasi:

```text
0 7 * * 7 root vzdump 107 --quiet 1 --mailnotification always --compress zstd --mode snapshot --storage local
```

Artinya:

- `0 7 * * 7` → setiap Minggu pukul 07:00
- `107` → VMID 107
- `--compress zstd` → menggunakan kompresi Zstandard
- `--mode snapshot` → backup tanpa menghentikan VM
- `--storage local` → backup dibuat di storage lokal
- `--mailnotification always` → notifikasi email sesuai konfigurasi Proxmox

**Jangan mengubah jadwal secara langsung tanpa menyesuaikan kebutuhan server.**

---

# 16. Jangan Menggunakan `/etc/pve/jobs.cfg` sebagai Acuan Universal

Pada Proxmox versi yang digunakan dalam implementasi referensi, konfigurasi jadwal ditemukan di:

```text
/etc/pve/vzdump.cron
```

Karena versi Proxmox dapat berbeda, selalu periksa mekanisme scheduler yang digunakan server target sebelum melakukan perubahan.

---

# 17. Instalasi Script Backup-to-NAS

File:

```text
/usr/local/sbin/backup-to-nas.sh
```

File ini bertanggung jawab untuk:

1. Menerima path file backup.
2. Memastikan file backup sesuai VMID.
3. Memastikan file sumber tersedia.
4. Memastikan NFS ter-mount.
5. Membuat folder tanggal di NAS.
6. Menyalin backup dengan `rsync`.
7. Menghindari perubahan owner/group yang tidak didukung oleh NFS.
8. Memverifikasi ukuran file.
9. Menjalankan retention NAS.
10. Menulis log.

Pastikan script yang digunakan adalah file `.sh` standar yang telah disiapkan untuk implementasi.

---

# 18. Permission Script

Pastikan script dapat dieksekusi:

```bash
chmod 750 /usr/local/sbin/backup-to-nas.sh
```

Verifikasi:

```bash
ls -l /usr/local/sbin/backup-to-nas.sh
```

Target:

```text
-rwxr-x---
```

---

# 19. Validasi Syntax Script

Sebelum digunakan:

```bash
bash -n /usr/local/sbin/backup-to-nas.sh
```

Jika tidak menghasilkan output/error, syntax shell valid.

**Jangan lanjut ke tahap produksi apabila terdapat error syntax.**

---

# 20. Konfigurasi Vzdump Hook

File:

```text
/usr/local/sbin/vzdump-hook.sh
```

Hook digunakan agar transfer ke NAS dijalankan **setelah backup lokal selesai**.

Event yang digunakan:

```text
backup-end
```

Hook mengambil file backup melalui environment variable:

```text
TARGET
```

Hook hanya memproses VMID yang telah ditentukan.

---

# 21. Permission Hook

Jalankan:

```bash
chmod 750 /usr/local/sbin/vzdump-hook.sh
```

Verifikasi:

```bash
ls -l /usr/local/sbin/vzdump-hook.sh
```

---

# 22. Validasi Syntax Hook

Jalankan:

```bash
bash -n /usr/local/sbin/vzdump-hook.sh
```

Jika tidak ada output/error, syntax valid.

---

# 23. Mengaktifkan Hook di Proxmox

Konfigurasi global vzdump berada di:

```text
/etc/vzdump.conf
```

**Sebelum menambahkan konfigurasi, periksa apakah hook sudah terdaftar.**

```bash
grep -n "^script:" /etc/vzdump.conf
```

Jika belum ada, tambahkan:

```text
script: /usr/local/sbin/vzdump-hook.sh
```

Contoh menggunakan command:

```bash
echo 'script: /usr/local/sbin/vzdump-hook.sh' >> /etc/vzdump.conf
```

Verifikasi:

```bash
grep -n "^script:" /etc/vzdump.conf
```

Hasil yang diharapkan:

```text
script: /usr/local/sbin/vzdump-hook.sh
```

**Jangan menambahkan baris `script:` lebih dari satu kali.**

---

# 24. Tidak Perlu Restart Proxmox

Perubahan pada:

```text
/etc/vzdump.conf
```

akan dibaca ketika `vzdump` dijalankan.

Tidak diperlukan restart Proxmox hanya untuk mengaktifkan konfigurasi hook.

---

# 25. Alur Eksekusi Setelah Implementasi

Setelah semuanya aktif, alurnya menjadi:

```text
1. Scheduler Proxmox aktif
          ↓
2. vzdump menjalankan backup VM
          ↓
3. VM tetap berjalan
          ↓
4. Backup dibuat ke storage lokal
          ↓
5. Backup lokal selesai
          ↓
6. Vzdump menjalankan hook backup-end
          ↓
7. Hook menerima TARGET
          ↓
8. backup-to-nas.sh dijalankan
          ↓
9. File disalin ke NAS
          ↓
10. Ukuran source dan target dibandingkan
          ↓
11. Backup dinyatakan berhasil
          ↓
12. Retention NAS dijalankan
          ↓
13. NAS menyimpan 2 backup terbaru
```

---

# 26. Struktur Folder NAS

Struktur yang digunakan:

```text
/mnt/nas-backup/
└── Regional/
    ├── 2026-08-02/
    │   └── vzdump-qemu-107-2026_08_02-07_00_02.vma.zst
    ├── 2026-08-09/
    │   └── vzdump-qemu-107-2026_08_09-07_00_02.vma.zst
    └── 2026-08-16/
        └── vzdump-qemu-107-2026_08_16-07_00_02.vma.zst
```

Folder tanggal dibuat berdasarkan tanggal yang terdapat pada nama file backup.

---

# 27. Retention NAS

Kebijakan:

> **NAS menyimpan 2 backup terbaru.**

Contoh terdapat:

```text
2026-08-02
2026-08-09
2026-08-16
```

Maka retention akan mempertahankan:

```text
2026-08-16
2026-08-09
```

dan menghapus:

```text
2026-08-02
```

Retention hanya berlaku pada:

```text
/mnt/nas-backup/Regional/
```

**Retention tidak boleh menghapus:**

```text
/var/lib/vz/dump/
```

Backup lokal tetap dibiarkan sesuai kapasitas dan kebijakan storage lokal Proxmox.

---

# 28. Mengapa Retention Berdasarkan Folder Backup

Retention menggunakan folder tanggal sebagai unit backup.

Keuntungan:

- Struktur NAS mudah dibaca.
- Mudah mengetahui kapan backup dibuat.
- Mudah melakukan audit manual.
- Backup dari satu periode tersimpan dalam satu folder.
- Penghapusan retention tidak menyentuh file lokal Proxmox.

---

# 29. Verifikasi Backup

Setelah transfer selesai, script membandingkan ukuran:

```text
Source size
        =
Target size
```

Contoh:

```text
Source : 15596830656 bytes
Target : 15596830656 bytes
```

Jika sama:

```text
Verifikasi ukuran: OK
```

Jika berbeda, backup dianggap gagal.

---

# 30. Penggunaan Rsync pada NFS

Transfer menggunakan konsep:

```text
rsync -avh --no-owner --no-group --progress
```

Parameter:

- `-a` → archive mode
- `-v` → verbose
- `-h` → human readable
- `--progress` → menampilkan progress
- `--no-owner` → tidak mencoba mengubah owner
- `--no-group` → tidak mencoba mengubah group

`--no-owner` dan `--no-group` penting pada implementasi NFS tertentu karena server NAS dapat menolak operasi `chown`.

---

# 31. Log Monitoring

Log utama:

```text
/var/log/backup-to-nas.log
```

Lihat seluruh log:

```bash
cat /var/log/backup-to-nas.log
```

Lihat bagian terakhir:

```bash
tail -50 /var/log/backup-to-nas.log
```

Monitor secara realtime:

```bash
tail -f /var/log/backup-to-nas.log
```

---

# 32. Indikator Backup Berhasil

Contoh pesan yang diharapkan:

```text
Verifikasi ukuran: OK
```

dan:

```text
Backup VM 107 berhasil disalin dan diverifikasi.
```

Hook juga akan mencatat:

```text
Backup VM 107 selesai.
TARGET: ...
Transfer backup VM 107 ke NAS berhasil.
```

---

# 33. Indikator Backup Gagal

Beberapa kondisi yang harus dianggap gagal:

1. File backup tidak ditemukan.
2. File backup bukan VMID yang ditentukan.
3. NFS tidak ter-mount.
4. NAS tidak dapat ditulis.
5. Rsync gagal.
6. Ukuran source dan target berbeda.
7. Script transfer gagal.
8. Hook gagal menjalankan script.

Jika transfer NAS gagal, hook mengembalikan exit code error.

Dengan demikian, task `vzdump` dapat terlihat gagal meskipun file backup lokal sebenarnya sudah berhasil dibuat.

**Ini merupakan perilaku yang disengaja agar kegagalan backup NAS tidak terlewatkan.**

---

# 34. Pengujian Sebelum Produksi

Untuk server produksi, hindari menjalankan backup VM secara manual jika tidak diperlukan.

Alternatif pengujian yang aman adalah menggunakan backup lokal yang sudah ada.

Contoh:

```bash
ls -lh /var/lib/vz/dump/
```

Pilih satu file backup yang valid.

Jalankan:

```bash
/usr/local/sbin/backup-to-nas.sh /var/lib/vz/dump/NAMA_FILE_BACKUP
```

Contoh:

```bash
/usr/local/sbin/backup-to-nas.sh /var/lib/vz/dump/vzdump-qemu-107-2026_08_02-07_00_02.vma.zst
```

Tujuan pengujian:

- Memastikan NFS dapat ditulis.
- Memastikan rsync berjalan.
- Memastikan transfer selesai.
- Memastikan verifikasi ukuran berhasil.
- Memastikan folder NAS dibuat.
- Memastikan retention berjalan.

---

# 35. Pengujian Transfer File Besar

Backup VM sebenarnya digunakan sebagai pengujian paling realistis.

Contoh backup:

```text
±15 GB
```

Transfer pada implementasi referensi berhasil dengan verifikasi:

```text
Source size = Target size
```

Pengujian file besar lebih relevan daripada hanya menguji file dummy karena dapat menunjukkan performa jaringan dan stabilitas transfer.

---

# 36. Pengujian Produksi Pertama

Setelah konfigurasi selesai:

**Jangan langsung memaksa backup VM produksi jika tidak diperlukan.**

Biarkan scheduler menjalankan backup sesuai jadwal.

Setelah jadwal backup berjalan, lakukan pemeriksaan:

### 36.1 Cek task Proxmox

Periksa task backup melalui:

```text
Datacenter → Tasks
```

atau CLI sesuai kebutuhan.

### 36.2 Cek backup lokal

```bash
ls -lh /var/lib/vz/dump/
```

### 36.3 Cek NAS

```bash
ls -lah /mnt/nas-backup/Regional/
```

### 36.4 Cek log

```bash
tail -100 /var/log/backup-to-nas.log
```

---

# 37. Checklist Validasi Setelah Backup Pertama

| Pemeriksaan                  | Status |
| ---------------------------- | ------ |
| VM tetap berjalan            | ☐      |
| Backup lokal terbentuk       | ☐      |
| File `.vma.zst` tersedia     | ☐      |
| Hook dipanggil               | ☐      |
| TARGET terdeteksi            | ☐      |
| NFS tetap mounted            | ☐      |
| Transfer ke NAS berhasil     | ☐      |
| Ukuran source = target       | ☐      |
| Folder tanggal NAS terbentuk | ☐      |
| Log menunjukkan sukses       | ☐      |
| Retention bekerja            | ☐      |
| Backup lokal tidak terhapus  | ☐      |

---

# 38. Pemeriksaan Retention

Jika NAS memiliki:

```text
2026-09-01/
2026-09-08/
2026-09-15/
```

setelah retention:

```text
2026-09-08/
2026-09-15/
```

Folder paling lama dihapus.

Pastikan tidak ada folder backup lokal yang ikut terhapus.

---

# 39. Pemeriksaan Mount Setelah Server Reboot

Untuk implementasi baru, sebaiknya dilakukan pada maintenance window.

Setelah reboot:

```bash
mountpoint -q /mnt/nas-backup && echo "NFS OK"
```

Kemudian:

```bash
mount | grep /mnt/nas-backup
```

Jika NFS otomatis ter-mount, konfigurasi `/etc/fstab` berhasil.

**Pada server produksi yang sedang aktif, tidak perlu reboot hanya untuk validasi awal.**

---

# 40. Troubleshooting NFS

## NFS tidak ter-mount

Cek:

```bash
mountpoint /mnt/nas-backup
```

Cek:

```bash
mount | grep nas-backup
```

Coba:

```bash
mount -a
```

Jika gagal, periksa:

- IP NAS
- NFS service OMV
- export path
- permission
- firewall
- jaringan
- konfigurasi `/etc/fstab`

---

# 41. Troubleshooting Permission Denied

Jika:

```bash
touch /mnt/nas-backup/test
```

menghasilkan:

```text
Permission denied
```

periksa:

1. Permission shared folder OMV.
2. Permission filesystem.
3. NFS client access.
4. Mapping user/group.
5. Export options.

Setelah perubahan permission di OMV, ulangi:

```bash
touch /mnt/nas-backup/test
```

Kemudian:

```bash
rm -f /mnt/nas-backup/test
```

---

# 42. Troubleshooting Rsync `Operation not permitted`

Jika rsync menghasilkan error seperti:

```text
chown ... Operation not permitted
```

gunakan konfigurasi rsync yang tidak mencoba mengubah owner/group:

```text
--no-owner --no-group
```

Jangan menganggap error tersebut sebagai kerusakan file backup sebelum melakukan verifikasi ukuran source dan target.

---

# 43. Troubleshooting Transfer Lambat

Transfer backup melalui NFS sangat bergantung pada:

- Kecepatan NIC Proxmox.
- Kecepatan NIC NAS.
- Switch.
- Kabel.
- NFS version.
- Storage NAS.
- HDD/SSD NAS.
- CPU NAS.
- Beban VM.
- Beban jaringan.

Monitoring sederhana:

```bash
ip -s link
```

dan:

```bash
mount | grep nas-backup
```

Catat kecepatan transfer aktual untuk setiap server agar dapat menjadi baseline.

---

# 44. Troubleshooting Hook Tidak Berjalan

Periksa:

```bash
grep -n "^script:" /etc/vzdump.conf
```

Pastikan:

```text
script: /usr/local/sbin/vzdump-hook.sh
```

Periksa permission:

```bash
ls -l /usr/local/sbin/vzdump-hook.sh
```

Validasi:

```bash
bash -n /usr/local/sbin/vzdump-hook.sh
```

Periksa log:

```bash
tail -100 /var/log/backup-to-nas.log
```

---

# 45. Troubleshooting Backup NAS Tidak Berhasil

Periksa:

```bash
tail -100 /var/log/backup-to-nas.log
```

Kemudian periksa:

```bash
mountpoint /mnt/nas-backup
```

Periksa file sumber:

```bash
ls -lh /var/lib/vz/dump/
```

Periksa tujuan:

```bash
ls -lah /mnt/nas-backup/Regional/
```

Jika diperlukan, jalankan script secara manual menggunakan backup yang sudah ada:

```bash
/usr/local/sbin/backup-to-nas.sh /path/backup.vma.zst
```

---

# 46. Prosedur Jika NAS Down

Jika NAS tidak tersedia ketika backup Proxmox berjalan:

1. Backup lokal Proxmox tetap menjadi backup utama sementara.
2. Hook akan mencoba transfer ke NAS.
3. Jika transfer gagal, error akan dicatat.
4. Jangan menghapus backup lokal.
5. Setelah NAS kembali normal, transfer backup dapat dilakukan menggunakan file backup lokal yang tersedia.

Contoh:

```bash
ls -lh /var/lib/vz/dump/
```

Kemudian jalankan kembali script transfer terhadap file yang sesuai.

---

# 47. Prinsip Recovery

Sistem ini mempunyai dua lokasi backup:

```text
Backup 1 → Proxmox Local Storage
Backup 2 → NAS OMV
```

Jika NAS gagal:

```text
Proxmox Local Backup
```

masih tersedia.

Jika storage Proxmox bermasalah:

```text
NAS Backup
```

dapat digunakan sebagai sumber recovery.

---

# 48. Keamanan

Implementasi ini berada pada jaringan internal/LAN.

Permission share dapat dibuat sesuai kebijakan keamanan organisasi.

Pada implementasi referensi, permission NAS dibuat sederhana agar Proxmox dapat menulis ke share.

Namun untuk deployment skala besar, disarankan menggunakan:

- IP restriction pada NFS export.
- VLAN jaringan backup.
- Firewall.
- Permission minimum yang diperlukan.
- Monitoring NAS.
- Backup NAS tambahan bila diperlukan.

**Jangan menganggap `chmod 777` sebagai praktik keamanan terbaik.** Gunakan hanya jika memang sesuai dengan kondisi jaringan dan kebijakan organisasi.

---

# 49. Standar Penamaan

Disarankan menggunakan pola:

```text
/usr/local/sbin/backup-to-nas.sh
/usr/local/sbin/vzdump-hook.sh
```

Log:

```text
/var/log/backup-to-nas.log
```

Mount:

```text
/mnt/nas-backup
```

Folder NAS:

```text
/mnt/nas-backup/<REGION>/
```

Contoh:

```text
/mnt/nas-backup/Regional/
```

---

# 50. Checklist Implementasi Server Baru

## A. Informasi Server

- [ ] Hostname Proxmox dicatat.
- [ ] IP Proxmox dicatat.
- [ ] VMID dicatat.
- [ ] Nama VM dicatat.
- [ ] Storage backup lokal dicatat.
- [ ] Jadwal backup ditentukan.

## B. Waktu

- [ ] Timezone benar.
- [ ] Tanggal benar.
- [ ] Jam benar.
- [ ] Sumber sinkronisasi waktu ditentukan.
- [ ] Jika manual, waktu sudah dikoreksi.

## C. NAS

- [ ] IP NAS benar.
- [ ] NFS aktif.
- [ ] Export benar.
- [ ] IP Proxmox diizinkan.
- [ ] Permission write benar.
- [ ] Folder tujuan tersedia.
- [ ] Kapasitas NAS mencukupi.

## D. NFS Proxmox

- [ ] `/mnt/nas-backup` dibuat.
- [ ] NFS berhasil di-mount.
- [ ] `touch` berhasil.
- [ ] File test berhasil dihapus.
- [ ] `/etc/fstab` dikonfigurasi.
- [ ] `mount -a` berhasil.

## E. Backup

- [ ] `vzdump` schedule benar.
- [ ] `--mode snapshot` digunakan.
- [ ] Backup lokal berhasil.
- [ ] File `.vma.zst` tersedia.

## F. Script

- [ ] `backup-to-nas.sh` tersedia.
- [ ] `vzdump-hook.sh` tersedia.
- [ ] Permission script benar.
- [ ] Syntax kedua script valid.
- [ ] Konfigurasi `script:` tersedia.
- [ ] Tidak ada duplicate `script:`.

## G. Testing

- [ ] Backup existing berhasil ditransfer.
- [ ] Ukuran source = target.
- [ ] Folder tanggal NAS terbentuk.
- [ ] Log sukses.
- [ ] Retention teruji.
- [ ] Backup lokal tidak terhapus.

## H. Production

- [ ] Backup scheduler berjalan.
- [ ] Backup NAS pertama berhasil.
- [ ] Log diperiksa.
- [ ] Retention diperiksa.
- [ ] Dokumentasi server diperbarui.

---

# 51. Checklist Audit Berkala

Disarankan melakukan pemeriksaan minimal setiap bulan.

```text
[ ] NAS dapat diakses
[ ] NFS mounted
[ ] Backup lokal tersedia
[ ] Backup NAS tersedia
[ ] Log tidak menunjukkan error
[ ] Retention sesuai kebijakan
[ ] Kapasitas NAS masih mencukupi
[ ] Kapasitas storage lokal masih mencukupi
[ ] Waktu server masih benar
[ ] Scheduler backup masih aktif
```

---

# 52. Catatan Operasional Penting

## 52.1 Backup Lokal dan NAS Mempunyai Fungsi Berbeda

Backup lokal digunakan sebagai recovery cepat.

Backup NAS digunakan sebagai salinan terpisah dari host Proxmox.

Jangan menganggap backup NAS sebagai pengganti backup lokal.

---

## 52.2 Retention Hanya untuk NAS

Retention:

```text
KEEP = 2 backup terbaru
```

hanya diterapkan pada:

```text
/mnt/nas-backup/Regional/
```

Tidak berlaku untuk:

```text
/var/lib/vz/dump/
```

---

## 52.3 Jangan Menghapus Backup Lokal Secara Manual Tanpa Kebijakan

Karena local storage sengaja tidak dikontrol oleh retention NAS, administrator harus mempunyai kebijakan terpisah apabila ingin membersihkan backup lokal.

---

# 53. Rekomendasi Pengembangan Versi Berikutnya

Untuk implementasi produksi jangka panjang, mekanisme berikut dapat ditambahkan:

### 53.1 Completion Marker

Setelah transfer dan verifikasi berhasil, buat marker:

```text
.complete
```

Contoh:

```text
Regional/
└── 2026-09-06/
    ├── vzdump-qemu-107-2026_09_06-07_00_02.vma.zst
    └── .complete
```

Retention kemudian hanya menghitung folder yang memiliki `.complete`.

Keuntungan:

- Folder backup yang transfernya belum selesai tidak dianggap sebagai backup valid.
- Jika transfer terputus, retention tidak salah menganggap folder tersebut sebagai backup lengkap.
- Status backup lebih mudah diaudit.

---

# 54. Prinsip Implementasi Standar

Setiap server Proxmox baru harus mengikuti prinsip:

```text
1. Pastikan waktu benar
2. Pastikan VM dan VMID benar
3. Pastikan NAS/NFS siap
4. Uji write access
5. Pastikan NFS persistent
6. Pastikan backup lokal aktif
7. Pasang backup-to-nas.sh
8. Pasang vzdump-hook.sh
9. Aktifkan hook
10. Validasi syntax
11. Uji menggunakan backup yang sudah ada
12. Tunggu/monitor backup terjadwal
13. Verifikasi backup lokal
14. Verifikasi backup NAS
15. Verifikasi log
16. Verifikasi retention
17. Dokumentasikan server
```

---

# 55. Form Data Implementasi

Gunakan formulir berikut ketika memasang pada server baru.

```text
HOSTNAME PROXMOX :
IP PROXMOX        :
PROXMOX VERSION   :

VMID              :
NAMA VM           :

STORAGE BACKUP    :
BACKUP DIRECTORY  :

NAS IP            :
NFS EXPORT        :
MOUNT POINT       :
FOLDER NAS        :

NFS VERSION       :
NFS OPTIONS       :

TIMEZONE          :
SUMBER WAKTU      :

JADWAL BACKUP     :
RETENTION NAS     :

TANGGAL INSTALASI :
TEKNISI           :
CATATAN           :
```

---

# 56. Status Implementasi Referensi

Implementasi referensi telah membuktikan:

- NFS Proxmox → OMV berhasil.
- Mount NFS berhasil.
- Write permission berhasil.
- Backup lokal Proxmox tersedia.
- Transfer backup VM nyata berukuran sekitar 15.6 GB berhasil.
- Rsync dengan `--no-owner --no-group` berhasil.
- Ukuran source dan target berhasil diverifikasi sama.
- Retention NAS telah dirancang untuk mempertahankan 2 backup terbaru.
- Vzdump hook telah dibuat.
- Hook menggunakan event `backup-end`.
- Hook menggunakan `TARGET`.
- Hook hanya memproses VMID yang ditentukan.
- Hook telah dikonfigurasi melalui `/etc/vzdump.conf`.
- Syntax script telah divalidasi.
- Server tidak perlu direboot hanya untuk mengaktifkan konfigurasi `vzdump.conf`.

---

# 57. Kesimpulan

Standar backup yang digunakan adalah:

```text
                 PROXMOX
                    │
                    ▼
             BACKUP LOKAL
                    │
                    ▼
              BACKUP SELESAI
                    │
                    ▼
             VZDUMP HOOK
                    │
                    ▼
             TRANSFER NFS
                    │
                    ▼
                NAS OMV
                    │
                    ▼
          VERIFIKASI BACKUP
                    │
                    ▼
            RETENTION = 2
```

Dengan desain ini, backup lokal Proxmox tetap tersedia sebagai salinan utama/cepat, sementara NAS OMV menyimpan salinan terpisah dengan retention yang terkontrol.

**Dokumen ini merupakan Standar implementasi. File `.sh` untuk server tidak termasuk dalam dokumen ini dan digunakan sebagai file deployment terpisah.**
