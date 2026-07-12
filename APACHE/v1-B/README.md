# Apache Manager & Automation Script (Simple v1-B)

Script Bash sederhana dan efisien menggunakan menu interaktif untuk mengelola siklus hidup Apache, melakukan instalasi cepat, hardening dasar, dan monitoring log.

## 🚀 Fitur Utama
* **Instalasi Cepat** - Update repository Debian/Ubuntu, install Apache2, UFW, dan auto-enable modul penting (`rewrite`, `headers`, `proxy`).
* **Basic Hardening & Tweaking** - Menyembunyikan signature server, mematikan TRACE method, dan memasang HTTP security headers dasar.
* **Manajemen Service** - Start, Stop, Restart, dan reload Apache dengan sekali tekan tombol.
* **Log Monitor** - Fitur viewer log error dan access secara real-time untuk mempermudah debugging.

## 📋 Prasyarat
- **Sistem Operasi**: Ubuntu 20.04 / 22.04 / 24.04 atau Debian 11 / 12.
- **Hak Akses**: Pengguna harus memiliki akses `root` atau `sudo`.

## 🛠️ Cara Penggunaan

Anda dapat menjalankan script ini langsung menggunakan Main Launcher `main.sh` di root directory, atau secara standalone:

```bash
chmod +x install.sh
sudo ./install.sh
```

---
*Kembali ke [Halaman Utama](../../README.md)*