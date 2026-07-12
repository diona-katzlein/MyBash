# Cloudflare DNS & Zero Trust Tunnel Manager (v2.0)

Script Bash interaktif berfitur lengkap untuk mengelola Cloudflare DNS Records dan konfigurasi Zero Trust Tunnel (Cloudflare Tunnel / Argo Tunnel) langsung dari terminal Anda.

## 🚀 Fitur Utama

* **DNS Records Management**:
  - Menambah record baru (`A`, `AAAA`, `CNAME`, `MX`, `TXT`, `SRV`) dengan TTL otomatis/custom.
  - Mengubah status proxy (Orange Cloud / Gray Cloud) secara instan (`toggle_proxy_dns`).
  - Menampilkan daftar DNS record lengkap dalam format tabel terstruktur.
  - Menghapus record secara aman menggunakan konfirmasi interaktif.

* **Zero Trust Tunnel (Cloudflare Tunnel)**:
  - Membuat tunnel baru, mendapatkan token eksekusi, serta menghapus tunnel yang tidak terpakai.
  - Menampilkan daftar status kesehatan tunnel (`healthy`, `degraded`, `down`).
  - Menghubungkan berbagai macam aplikasi/service lokal (HTTP, HTTPS, SSH, RDP, VNC, MySQL, PostgreSQL, MongoDB, Redis, Grafana, dll) ke tunnel.
  - Menghapus dan melihat daftar route/ingress rules aktif pada tunnel.

* **Quick Setup**:
  - Menghubungkan aplikasi lokal ke tunnel sekaligus membuat DNS record CNAME secara otomatis dalam satu langkah mudah.

## 📋 Prasyarat
- Distro Linux dengan utility: `curl`, `jq`, `grep`, `awk`.
- Cloudflare API Token dengan izin (Permissions):
  - **Zone / DNS / Edit**
  - **Account / Cloudflare Tunnel / Edit**

---

## ⚙️ Konfigurasi (`config.env`)

Sebelum menjalankan script, lengkapi berkas `config.env` dengan kredensial Cloudflare Anda:
```bash
CF_API_TOKEN="api_token_cloudflare_anda"
CF_ZONE_ID="zone_id_domain_anda"
CF_ACCOUNT_ID="account_id_cloudflare_anda"
CF_DOMAIN="domain_anda.com"
CF_TUNNEL_ID="tunnel_id_aktif_anda_jika_ada"
CF_TUNNEL_NAME="nama_tunnel_anda_jika_ada"
```

---

## 🛠️ Cara Penggunaan

Anda dapat menjalankan script ini langsung menggunakan Main Launcher `main.sh` di root directory, atau secara standalone:

```bash
chmod +x cf-manager.sh
./cf-manager.sh
```

---
*Kembali ke [Halaman Utama](../../README.md)*
