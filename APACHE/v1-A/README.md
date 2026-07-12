# Apache Web Server Setup & Management (Advanced v1-A)

Script Bash interaktif berfitur lengkap untuk instalasi, konfigurasi, optimasi, dan pengelolaan server Apache di sistem operasi berbasis Debian/Ubuntu.

## 🚀 Fitur Utama
* **Instalasi Apache Full Stack** - Otomatis mengupdate repository, menginstall apache2, ufw, mod-rewrite, headers, dan proxy.
* **Multi-Framework & Platform Support** - Dukungan virtual host siap pakai untuk Laravel, CodeIgniter, Symfony, Yii, Node.js, Python, Go, WordPress, dan Joomla.
* **Setup Reverse Proxy** - Memudahkan mapping port aplikasi backend internal ke domain public.
* **PHP Selector & Switcher** - Mengatur dan mengganti versi default PHP FPM secara global dan per Virtual Host (PHP 7.4 s.d. 8.3).
* **Security Hardening** - Konfigurasi keamanan bawaan seperti menyembunyikan versi Apache, disable HTTP Trace, setup secure headers, dan proteksi directory listing.

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