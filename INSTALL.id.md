# Memasang NETRA

NETRA adalah satu aplikasi: layanan pusat komando, dasbornya, dan basis datanya. Pasang di
komputer yang selalu menyala dan berada di jaringan yang sama dengan robot, lalu selesaikan
penyiapan lewat browser. (English: [INSTALL.md](INSTALL.md).)

## Yang Anda terima dari EZRA Robotics

| Item | |
|---|---|
| Installer | `NETRA-Setup-<versi>-x64.exe` (Windows), `netra_<versi>_amd64.deb` (Ubuntu/Debian), `NETRA-<versi>-macos.pkg` (macOS), atau image Docker `ghcr.io/darmawanweb/netra` |
| Lisensi | `<klien>.lic`, diterbitkan untuk ID instalasi server Anda (lihat [Lisensi](#lisensi)) |
| Panduan | panduan ini dan panduan operator (PDF) |

## Kebutuhan

- Windows 10/11 64-bit atau Windows Server 2019+, Ubuntu 22.04/24.04 atau Debian 12, atau macOS 13+.
- 4 inti CPU, memori 8 GB, ruang disk kosong 50 GB (foto dan peta bertambah seiring pemakaian).
- Alamat tetap di jaringan robot (atur reservasi DHCP di router).
- Opsional, untuk verifikasi AI: [Ollama](https://ollama.com) dengan model vision; GPU atau
  memori 16 GB untuk model 7B.

## Pemasangan

**Windows.** Jalankan `NETRA-Setup-<versi>-x64.exe` sebagai administrator. Installer memasang
NETRA dan basis datanya, menjalankan layanan **NETRA** (ikut menyala bersama Windows), membuka
port 8080 di firewall, dan membuka browser di akhir. Konfigurasi dan data:
`C:\ProgramData\NETRA` (`netra.env`, `data\`, `logs\`).

**Ubuntu atau Debian.**

```bash
sudo apt install ./netra_<versi>_amd64.deb
```

Paket ini memasang PostgreSQL bila belum ada, membuat basis data `netra`, dan menjalankan
layanan `netra`. Konfigurasi: `/etc/netra/netra.env`. Data dan cadangan: `/var/lib/netra`.
Log: `journalctl -u netra -f`.

**macOS.** Buka `NETRA-<versi>-macos.pkg` (pertama kali: klik kanan > Open). Konfigurasi dan
data: `/Library/Application Support/NETRA`.

**Docker.** Untuk server yang sudah memakai Docker: `docker-compose.yml` repositori Netra dengan
image `ghcr.io/darmawanweb/netra` ([README](README.md#deploy-on-a-server)).

## Penyiapan awal

Buka `http://<alamat server>:8080` di browser pada jaringan yang sama. Instalasi baru membuka
penyiapan:

1. **Instalasi**: ID instalasi server ini, misalnya `NETRA-7KQ3-M9XD-2WPA`. Salin ID ini:
   lisensi Anda diterbitkan untuknya.
2. **Administrator**: akun pertama, yang mengelola pengguna, robot dan lisensi.
3. **Lisensi**: tempel lisensi atau pilih berkas `.lic`. Tanpa lisensi Anda tetap bisa
   melanjutkan: fitur inti berjalan dengan satu robot sampai lisensi dipasang.

## Lisensi

Lisensi memuat nama organisasi Anda dan menentukan modul, jenis peta, jumlah robot, serta masa
berlakunya. Lisensi hanya berlaku di server yang ID instalasinya tercantum, tanpa perlu internet.

- Belum punya lisensi: kirim ID instalasi ke EZRA Robotics, lalu pasang berkas yang Anda terima.
- Memasang atau mengganti lisensi: **Pengaturan › Lisensi** (administrator), kapan saja, tanpa
  restart. Bisa juga menaruh berkasnya di lokasi lisensi pada `netra.env` lalu restart layanan.
- Pengaturan › Lisensi menampilkan status, modul, jumlah robot terhadap batasnya, dan masa
  berlaku. Mintalah perpanjangan sebelum habis; setelah habis, modul masih berjalan 14 hari.
- Server baru (atau basis data baru) punya ID instalasi baru dan memerlukan lisensi baru.

## Menghubungkan robot

Di **Pengaturan › Robot**, tambahkan tiap robot. Salin tokennya, yang hanya ditampilkan sekali,
ke konfigurasi robot bersama alamat server ini (`CC_URL`), sesuai panduan robot.

## Konfigurasi

`netra.env` menyimpan pengaturan; restart layanan setelah mengubahnya.

- Windows: services.msc > NETRA > Restart.
- Linux: `sudo systemctl restart netra`.
- macOS: `sudo launchctl kickstart -k system/id.ezrarobotics.netra`.

| Pengaturan | |
|---|---|
| `NETRA_ADDR` | port (`:8080`); `:80` agar dasbor terbuka tanpa nomor port |
| `NETRA_PUBLIC_URL` | alamat yang dipakai robot dan ponsel, misalnya `http://192.168.1.10:8080` |
| `NETRA_TLS=self-signed` | HTTPS dengan sertifikat buatan NETRA (browser meminta persetujuan sekali); atau `NETRA_TLS_CERT` dan `NETRA_TLS_KEY` untuk sertifikat sendiri |
| `NETRA_OLLAMA_URL` | verifikasi AI dengan Ollama, misalnya `http://localhost:11434` (perlu modul di lisensi) |
| `NETRA_TELEGRAM_TOKEN`, `NETRA_TELEGRAM_CHAT_ID` | notifikasi Telegram (perlu modul di lisensi) |
| `NETRA_BACKUP_KEEP_DAYS`, `NETRA_BACKUP_AT` | cadangan harian basis data: jumlah hari disimpan, jam |

## Cadangan

NETRA mencadangkan basis datanya setiap hari (pukul 02.30 secara bawaan) ke folder `backups`
di folder datanya dan menyimpannya 14 hari. Halaman **Sistem** (administrator) menampilkan daftar
cadangan, membuat cadangan saat itu juga, mengunduhnya, dan menampilkan ruang disk. Foto dan peta
berupa berkas di folder data: salin folder itu ke disk lain secara berkala.

Memulihkan, dengan layanan dihentikan:

```bash
netra restore -yes <data>/backups/netra-YYYYMMDD-HHMMSS.dump
```

## Pembaruan

Pasang versi baru di atas versi lama (installer atau paket yang sama). Data, konfigurasi dan
lisensi tetap ada; basis data diperbarui saat layanan berjalan kembali.

## Lupa kata sandi administrator

Di server, sebagai administrator:

- Windows: `"C:\Program Files\NETRA\netra.exe" reset-password admin`
- Linux: `sudo -u netra netra reset-password admin`
- macOS: `sudo -u _netra "/Library/NETRA/netra" -config "/Library/Application Support/NETRA/netra.env" reset-password admin`

Perintah ini mencetak kata sandi baru dan mengeluarkan akun tersebut dari semua sesi.

## Perintah

`netra version`, `netra installation-id`, `netra backup`, `netra restore -yes <berkas>`,
`netra license <berkas.lic>` (memeriksa lisensi terhadap server ini),
`netra reset-password <pengguna> [kata-sandi]`.

## Mengatasi masalah

| Gejala | Periksa |
|---|---|
| Halaman tidak terbuka | layanan berjalan (services.msc, `systemctl status netra`); firewall mengizinkan port; alamatnya alamat server |
| Robot tetap offline | robot bisa menjangkau server: `curl http://<server>:8080/healthz` dari robot; tokennya sama dengan yang ditampilkan saat robot ditambahkan |
| "Tidak termasuk lisensi" | modul itu tidak ada di lisensi: Pengaturan › Lisensi, lalu hubungi EZRA Robotics |
| Lisensi ditolak: "for another installation" | lisensi diterbitkan untuk ID server lain; kirim ID server ini |
| Log | Windows: `C:\ProgramData\NETRA\logs`; Linux: `journalctl -u netra`; macOS: `/Library/Application Support/NETRA/logs` |

## Mencopot

Windows: Settings > Apps > NETRA. Linux: `sudo apt remove netra` (`purge` juga menghapus
konfigurasi). Folder data dan basis data tetap ada sampai Anda menghapusnya.
