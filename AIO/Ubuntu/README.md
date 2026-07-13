# Ubuntu All-In-One Server Stack Installer

Kumpulan Script *one-click* otomatisasi instalasi, konfigurasi, optimasi, dan hardening stack server lengkap untuk **Ubuntu Server/Desktop**.

## ⚠️ Paket yang Terinstall
1. **Nginx Web Server** (Stable) + Hardening security headers.
2. **PHP Multi-Version** (PHP 7.4 & PHP 8.x FPM/CLI).
3. **MySQL Server** + Tuning performa dasar.
4. **Node.js LTS & NPM** (melalui repo resmi NodeSource).
5. **Python 3 & PIP** virtual environment.
6. **Git, Curl, Wget** utilitas development dasar.
7. **UFW Firewall Security**.

---

## 🚀 Fitur & Pilihan Versi

### 1. AIO Stack Installer v1-A (Advanced)
Script komprehensif modular yang mendukung set MySQL password dan timezone kustom secara dinamis lewat environment variables.
* Default PHP 8.3.
* Konfigurasi cache memcache/redis PHP.
* Node.js v24.

**Cara Penggunaan:**
```bash
chmod +x install-v1-A.sh
sudo ./install-v1-A.sh
# Kustomisasi password MySQL & Timezone:
sudo MYSQL_ROOT_PASSWORD='PasswordKuatAnda!123' TIMEZONE='Asia/Makassar' ./install-v1-A.sh
```

### 2. AIO Stack Installer v1-B (Simple)
Script cepat non-interaktif yang langsung berjalan mengamankan dan menyiapkan parameter inti stack.
* Default PHP 8.3 (CLI) & 7.4.
* Node.js v22 LTS (dengan fallback).
* Hardening default site block Nginx & MySQL.

**Cara Penggunaan:**
```bash
chmod +x install-v1-B.sh
sudo ./install-v1-B.sh
```

---
*Kembali ke [Halaman Utama](../../README.md)*
