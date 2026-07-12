# NGINX Installer & Hardening (Advanced v1-A)

Script Bash modular untuk instalasi Nginx versi terbaru serta konfigurasi parameter keamanan tingkat tinggi (Hardening) sesuai standar keamanan industri.

## 🚀 Fitur Utama
* **Instalasi Nginx Terbaru** - Auto-detect dan konfigurasi PPA/repository resmi Nginx (Stable/Mainline).
* **Deep Security Hardening** - Konfigurasi keamanan meliputi:
  - Menyembunyikan nama dan versi server.
  - Penyesuaian SSL/TLS configuration (mematikan TLS 1.0, 1.1, mengaktifkan TLS 1.2, 1.3).
  - Pemasangan Diffie-Hellman Parameter (DHParam 2048/4096-bit).
  - Proteksi DDOS dasar (buffer limit, client body timeout).
  - Security headers (X-Frame-Options, CSP, XSS protection, HSTS, Referrer Policy).
* **Backup Otomatis** - Melakukan backup konfigurasi lama sebelum menimpa konfigurasi baru.
* **Log Rotation & Monitoring** - Setup logger khusus yang siap diintegrasikan dengan analyzer tools.

## 📋 Prasyarat
- **Sistem Operasi**: Ubuntu 20.04 / 22.04 / 24.04 atau Debian 11 / 12.
- **Hak Akses**: Pengguna harus memiliki akses `root` atau `sudo`.

## 🛠️ Cara Penggunaan

Anda dapat menjalankan script ini langsung menggunakan Main Launcher `main.sh` di root directory, atau secara standalone:

```bash
chmod +x nginx-installer.sh
sudo ./nginx-installer.sh
```

---
*Kembali ke [Halaman Utama](../../README.md)*