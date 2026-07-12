# ⚡ MyBash — Server Automation & Hardening Scripts

[![Security Scan](https://github.com/diona-katzlein/MyBash/actions/workflows/security.yml/badge.svg)](https://github.com/diona-katzlein/MyBash/actions/workflows/security.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/Version-1.0.0--Mondstadt-orange.svg)](#)
[![Bash Shell](https://img.shields.io/badge/Shell-Bash-4EAA25.svg?logo=gnu-bash&logoColor=white)](#)

Kumpulan Script Bash interaktif untuk mempermudah instalasi aplikasi, pengelolaan web server, dan melakukan hardening keamanan tingkat tinggi pada server berbasis **Debian/Ubuntu**.

---

## 🌟 Fitur Utama
- 🛡️ **Server Hardening**: Konfigurasi parameter keamanan terbaik secara otomatis (SSL/TLS tuning, disable signatures, secure HTTP headers, firewall configuration).
- ⚙️ **Modular & Interaktif**: Menggunakan TUI (Text User Interface) interaktif untuk navigasi menu yang mudah.
- 🚀 **Remote & Local Exec**: Script dapat dijalankan langsung secara lokal atau di-stream secara remote menggunakan `curl`/`wget`.
- 🔍 **Auto Lint & Sec Check**: Terintegrasi dengan **GitHub Actions (ShellCheck)** untuk memastikan script aman dan bebas bug sebelum dijalankan.

---

## 🛠️ Menu Launcher (`main.sh`)

Kami menyediakan base launcher interaktif untuk memilih dan menjalankan modul installer secara praktis:

```bash
# Clone repository
git clone https://github.com/diona-katzlein/MyBash.git
cd MyBash

# Jalankan Launcher Utama
sudo bash main.sh
```

### Jalankan Standalone via URL (Tanpa Clone)
Anda juga dapat menjalankan launcher utama atau sub-script secara remote langsung pada server target:

```bash
sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/diona-katzlein/MyBash/main/main.sh)"
```

---

## 📂 Struktur Repositori & Modul

| Kategori | Versi | Nama File | Deskripsi | Dokumentasi |
| :--- | :--- | :--- | :--- | :--- |
| 🌐 **APACHE** | `v1-A` (Advanced) | [install.sh](APACHE/v1-A/install.sh) | Setup Apache, Multi-vhost, PHP Switcher. | [Docs 📖](APACHE/v1-A/README.md) |
| 🌐 **APACHE** | `v1-B` (Simple) | [install.sh](APACHE/v1-B/install.sh) | Instalasi Apache, hardening dasar, logs viewer. | [Docs 📖](APACHE/v1-B/README.md) |
| 🚀 **NGINX** | `v1-A` (Advanced) | [nginx-installer.sh](NGINX/v1-A/nginx-installer.sh) | Nginx Mainline/Stable, SSL DHParam, Hardening Headers. | [Docs 📖](NGINX/v1-A/README.md) |
| 🚀 **NGINX** | `v1-A` | [vhost.sh](NGINX/v1-A/vhost.sh) | Create/Delete Virtual Host, Let's Encrypt SSL. | [Docs 📖](NGINX/v1-A/VHOST-README.md) |
| 🚀 **NGINX** | `v1-B` (Simple) | [php-installer.sh](NGINX/v1-B/php-installer.sh) | Nginx & PHP FPM Stack Installer. | [Docs 📖](NGINX/v1-B/README.md) |
| 🚀 **NGINX** | `v1-B` | [vhost.sh](NGINX/v1-B/vhost.sh) | Virtual Host generator minimalis. | [Docs 📖](NGINX/v1-B/VHOST-README.md) |
| 🐘 **PHP** | `v1-A` (Advanced) | [php-installer.sh](PHP/v1-A/php-installer.sh) | Multi-Version PHP (7.4 - 8.3) switcher global/VHost. | [Docs 📖](PHP/v1-A/README.md) |
| 🐘 **PHP** | `v1-B` (Simple) | [php-installer.sh](PHP/v1-B/php-installer.sh) | PHP-FPM install instan dan default switcher. | [Docs 📖](PHP/v1-B/README.md) |
| 🔑 **SSH** | `v1-A` (Advanced) | [ssh-v1-a.sh](SSH/ssh-v1-a.sh) | SSH Hardening (Port, Cipher/Kex, Key Auth, Fail2Ban). | [Docs 📖](SSH/README.md) |
| 🔑 **SSH** | `v1-B` (Simple)   | [ssh-v1-b.sh](SSH/ssh-v1-b.sh) | SSH Hardening non-interaktif cepat & kuat. | [Docs 📖](SSH/README.md) |

---

## 🔒 Security & Quality Control

Untuk memastikan keamanan server Anda, repositori ini menggunakan **GitHub Actions Workflow** yang secara berkala memeriksa kualitas script menggunakan [ShellCheck](https://www.shellcheck.net/):
- Mencegah error syntax & bugs.
- Mengidentifikasi kerentanan keamanan (misalnya, word splitting, unquoted variables, command injection vectors).
- Menjaga standardisasi penulisan script POSIX/Bash.

---

## 📄 Lisensi & Metadata

- **Author**: [IsekaiID](https://github.com/diona-katzlein)
- **Base URL**: [https://github.com/diona-katzlein/MyBash](https://github.com/diona-katzlein/MyBash)
- **Version**: `1.0.0 - Mondstadt`
- **Lisensi**: Open Source - [MIT License](LICENSE)
