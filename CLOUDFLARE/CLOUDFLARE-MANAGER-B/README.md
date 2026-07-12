# Cloudflare DNS & Tunnel Manager (Simple v1-B)

Script Bash sederhana untuk mengelola Cloudflare DNS (A Record) dan Zero Trust Tunnel menggunakan Cloudflare API.

## 🚀 Fitur Utama

* **Membuat DNS Record**:
  - Membuat A Record subdomain dengan pilihan mode **Proxied (Orange Cloud)** atau **DNS Only (Grey Cloud)**.

* **Menambahkan Aplikasi ke Tunnel**:
  - Memasukkan route/ingress rule aplikasi backend (HTTP, HTTPS, TCP, SSH) ke Tunnel jarak jauh (Remote Config).
  - Mengonfigurasi parameter `"noTLSVerify": true` secara otomatis untuk backend HTTPS self-signed.

## 📋 Prasyarat
- Distro Linux dengan utility: `curl`, `jq`.
- Kredensial Cloudflare (API Token, Account ID, Zone ID).

---

## ⚙️ Cara Penggunaan

1. Buka file `cf-manager.sh` menggunakan editor teks (seperti `nano`):
   ```bash
   nano cf-manager.sh
   ```
2. Isi variabel di bagian atas berkas:
   ```bash
   CF_API_TOKEN="api_token_anda"
   CF_ACCOUNT_ID="account_id_anda"
   CF_ZONE_ID="zone_id_anda"
   ```
3. Berikan izin eksekusi dan jalankan:
   ```bash
   chmod +x cf-manager.sh
   ./cf-manager.sh
   ```

---
*Kembali ke [Halaman Utama](../../README.md)*
