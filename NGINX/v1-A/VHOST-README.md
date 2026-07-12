# NGINX Virtual Host Manager (Advanced v1-A)

Script utility interaktif untuk mengotomasi siklus hidup Virtual Host (Server Block) pada Nginx.

## 🚀 Fitur Utama
* **Pembuatan Virtual Host Otomatis** - Mendukung static HTML, PHP (via PHP-FPM), NodeJS, Python, dan reverse proxy.
* **Instalasi Let's Encrypt SSL** - Otomatis mendeteksi certbot untuk generate sertifikat SSL gratis secara instant.
* **Manajemen Situs** - Fitur Enable/Disable virtual host dengan mudah tanpa perlu symlink manual.
* **Auto-clean & Reload** - Cek syntax Nginx sebelum reload agar service tidak down saat terjadi error.

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