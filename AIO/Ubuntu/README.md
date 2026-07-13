# Ubuntu All-In-One Server Stack Installer (v1)

Script *one-click* otomatisasi instalasi, konfigurasi, optimasi, dan hardening stack server lengkap untuk **Ubuntu Server/Desktop**.

## 🚀 Fitur Utama & Paket Terinstall
1. **Nginx Web Server** (Stable Version) + Hardening security headers + Optimasi static file cache/Gzip.
2. **PHP Multi-Version** (PHP 7.4 & PHP 8.3) lengkap dengan package pendukung (FPM, CLI, MySQL, XML, Curl, GD, Mbstring, Zip, Redis, Memcached, SQLite3, OPcache).
3. **MySQL Server** + Tuning performa basic untuk database VPS.
4. **Node.js 24 LTS & NPM** (melalui repo resmi NodeSource).
5. **Python 3 & PIP** virtual environment tool.
6. **Git, Curl, Wget** utilitas development dasar.
7. **UFW Firewall Security** (Auto whitelist port OpenSSH dan Nginx HTTP/HTTPS).

---

## 🛠️ Cara Penggunaan

Anda dapat menjalankan script ini langsung menggunakan Main Launcher `main.sh` di root directory, atau secara standalone:

```bash
chmod +x install-v1.sh
sudo ./install-v1.sh
```

### Opsi Kustomisasi Password MySQL & Timezone
Secara bawaan, script menggunakan password MySQL `StrongRootPass123!` dan timezone `Asia/Jakarta`. Anda dapat mengubahnya langsung saat mengeksekusi script:

```bash
sudo MYSQL_ROOT_PASSWORD='PasswordKuatAnda!123' TIMEZONE='Asia/Makassar' ./install-v1.sh
```

---
*Kembali ke [Halaman Utama](../../README.md)*
