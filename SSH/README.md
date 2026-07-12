# SSH Server Hardening (v1-A)

Script Bash komprehensif interaktif untuk meningkatkan keamanan konfigurasi server SSH Daemon (sshd) pada distro Linux Debian/Ubuntu.

## 🚀 Fitur Utama
* **Ubah Port SSH** - Menghindari serangan bruteforce automated bot dengan mengganti port SSH default 22 ke custom port (default: 2222).
* **Nonaktifkan Root Login** - Memblokir user root login langsung via SSH (mewajibkan user biasa dengan privilege sudo).
* **Nonaktifkan Password Authentication** - Mematikan authentikasi password tradisional (mewajibkan SSH Key Pair).
* **Security Cryptography Tuning** - Hanya menggunakan cipher, key exchange, dan MACs yang kuat (Ed25519, AES-256, chacha20, dll).
* **Session & Timeout Control** - Mengatur batas timeout idle session, pembatasan jumlah kegagalan login (MaxAuthTries), dan jumlah concurrent session.
* **Fail2Ban Integration** - Auto install dan konfigurasi proteksi Fail2Ban untuk memblokir IP penyerang bruteforce.
* **Banner Warning** - Menampilkan banner peringatan hukum saat login ke SSH.
* **Backup & Validasi** - Melakukan backup otomatis ke `/root/ssh_backup` sebelum menerapkan perubahan, dan memvalidasi konfigurasi dengan `sshd -t` sebelum merestart service.

## 📋 Prasyarat
- **Sistem Operasi**: Ubuntu / Debian.
- **Hak Akses**: Pengguna harus memiliki akses `root` atau `sudo`.

## 🛠️ Cara Penggunaan

Anda dapat menjalankan script ini langsung menggunakan Main Launcher `main.sh` di root directory, atau secara standalone:

```bash
chmod +x ssh-v1-a.sh
sudo ./ssh-v1-a.sh
```

### Opsi Non-Interaktif (Otomatis)
Jalankan script langsung dengan konfigurasi hardening default tanpa interaksi user:
```bash
sudo ./ssh-v1-a.sh --auto
```

---
*Kembali ke [Halaman Utama](../README.md)*
