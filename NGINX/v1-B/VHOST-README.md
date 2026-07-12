# NGINX Virtual Host Configurator (Simple v1-B)

Script interaktif minimalis untuk generate konfigurasi Virtual Host Nginx baru.

## 🚀 Fitur Utama
* **Template Generator** - Otomatis membuat template server block untuk static HTML maupun PHP.
* **Symlink Automatik** - Membuat file konfigurasi di `sites-available` dan langsung mengaktifkannya (symlink) di `sites-enabled`.
* **Testing Syntax** - Memvalidasi file konfigurasi agar tidak merusak service Nginx yang sedang berjalan.

## 📋 Prasyarat
- **Sistem Operasi**: Debian/Ubuntu dengan Nginx terinstall.
- **Hak Akses**: Pengguna harus memiliki akses `root` atau `sudo`.

## 🛠️ Cara Penggunaan

Anda dapat menjalankan script ini langsung menggunakan Main Launcher `main.sh` di root directory, atau secara standalone:

```bash
chmod +x vhost.sh
sudo ./vhost.sh
```

---
*Kembali ke [Halaman Utama](../../README.md)*