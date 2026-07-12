# PHP Manager & Switcher (Advanced v1-A)

Script Bash interaktif yang kuat untuk menginstal beberapa versi PHP secara bersamaan (Multi-PHP) dan beralih antar versi tersebut secara fleksibel pada sistem Debian/Ubuntu.

## 🚀 Fitur Utama
* **Instalasi Multi-Version PHP** - Pilihan instalasi PHP versi 7.4, 8.0, 8.1, 8.2, dan 8.3 beserta ekstensi umum (`cli`, `fpm`, `mysql`, `xml`, `mbstring`, etc.).
* **PHP Switcher** - Mengubah versi default active PHP CLI dan PHP FPM di server secara global hanya dengan memilih angka menu.
* **Custom PPA Integration** - Otomatis menambahkan repository Ondrej Sury PHP PPA untuk mendapatkan rilis PHP terbaru & stabil di Ubuntu/Debian.
* **Service Management** - Auto restart/reload php-fpm daemon setelah terjadi perubahan versi.

## 📋 Prasyarat
- **Sistem Operasi**: Ubuntu 20.04 / 22.04 / 24.04 atau Debian 11 / 12.
- **Hak Akses**: Pengguna harus memiliki akses `root` atau `sudo`.

## 🛠️ Cara Penggunaan

Anda dapat menjalankan script ini langsung menggunakan Main Launcher `main.sh` di root directory, atau secara standalone:

```bash
chmod +x php-installer.sh
sudo ./php-installer.sh
```

---
*Kembali ke [Halaman Utama](../../README.md)*