# SSH Server Hardening Modul

Kumpulan Script Bash untuk melakukan hardening (pengamanan) konfigurasi SSH Daemon (sshd) pada distro Linux Debian/Ubuntu.

## ⚠️ Peringatan Sangat Penting Sebelum Menjalankan Script
1. **Pastikan Anda sudah mengatur SSH Key (Public/Private Key)** dan bisa login menggunakan key tersebut.
2. **JANGAN tutup terminal/SSH session Anda** setelah menjalankan script ini. Buka terminal baru dan coba login untuk memastikan konfigurasi berhasil dan Anda tidak terkunci (locked out).
3. Kedua script ini akan **mematikan login menggunakan Password** dan hanya mengizinkan **SSH Key**.

---

## 🚀 Fitur & Pilihan Versi

### 1. SSH Hardening (Advanced v1-A)
Script komprehensif interaktif yang menyediakan opsi modular penuh.
* **Ubah Port SSH** ke custom port pilihan Anda.
* **Generate SSH Host Key Baru** menggunakan algoritma modern.
* **Integrasi Fail2Ban** otomatis untuk memblokir IP penyerang bruteforce.
* **Setup SSH Key untuk User** secara otomatis dari menu.
* **Semua fitur di v1-B** (nonaktifkan root login, password auth, dll).

**Cara Penggunaan:**
```bash
chmod +x ssh-v1-a.sh
sudo ./ssh-v1-a.sh
# Mode otomatis (tanpa interaktif):
sudo ./ssh-v1-a.sh --auto
```

### 2. SSH Hardening (Simple v1-B)
Script cepat, efisien, dan non-interaktif yang langsung mengamankan parameter inti SSH.
* **Disable Root Login** langsung tanpa input tambahan.
* **Disable Password Auth & Challenge Response** (wajib SSH Key).
* **Strong Cryptography** (hanya mengaktifkan Cipher & MACs modern).
* **Auto Backup & Validation** konfigurasi sebelum restart.

**Cara Penggunaan:**
```bash
chmod +x ssh-v1-b.sh
sudo ./ssh-v1-b.sh
```

---
*Kembali ke [Halaman Utama](../README.md)*
