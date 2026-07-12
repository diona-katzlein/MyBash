# Nginx & PHP Auto Installer (Simple v1-B)

Script automasi ringkas untuk melakukan install web server Nginx dipadukan dengan PHP-FPM di distro Debian/Ubuntu.

## 🚀 Fitur Utama
* **One-Click Install** - Proses setup Nginx dan PHP-FPM dasar dengan satu langkah mudah.
* **Basic Configuration** - Pengaturan default directory root di `/var/www/html`.
* **UFW Firewall integration** - Otomatis membuka port 80 (HTTP) dan 443 (HTTPS) pada firewall.

## 📋 Prasyarat
- **Sistem Operasi**: Ubuntu / Debian.
- **Hak Akses**: Pengguna harus memiliki akses `root` atau `sudo`.

## 🛠️ Cara Penggunaan

Anda dapat menjalankan script ini langsung menggunakan Main Launcher `main.sh` di root directory, atau secara standalone:

```bash
chmod +x php-installer.sh
sudo ./php-installer.sh
```

---
*Kembali ke [Halaman Utama](../../README.md)*