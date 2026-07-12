#!/bin/bash
set -e

# Warna untuk output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================================${NC}"
echo -e "${GREEN}  Nginx Latest Mainline Install & Hardening Script      ${NC}"
echo -e "${GREEN}========================================================${NC}"

# 1. Cek Root Privileges
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Error: Script ini harus dijalankan sebagai root (sudo).${NC}"
  exit 1
fi

# 2. Cek OS (Hanya mendukung Ubuntu/Debian)
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION_CODENAME=$VERSION_CODENAME
else
    echo -e "${RED}Error: Tidak dapat mendeteksi sistem operasi. Script ini hanya untuk Ubuntu/Debian.${NC}"
    exit 1
fi

if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
    echo -e "${RED}Error: OS tidak didukung. Script ini hanya untuk Ubuntu dan Debian.${NC}"
    exit 1
fi

echo -e "${YELLOW}[*] Sistem terdeteksi: $PRETTY_NAME${NC}"

# 3. Install Prasyarat
echo -e "${YELLOW}[*] Menginstall prasyarat...${NC}"
apt-get update -qq
apt-get install -y -qq curl gnupg2 ca-certificates lsb-release ubuntu-keyring > /dev/null 2>&1

# 4. Import Official Nginx Signing Key
echo -e "${YELLOW}[*] Mengimport Nginx GPG Key...${NC}"
curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor | tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null

# 5. Tambahkan Repository Resmi Nginx (Mainline)
echo -e "${YELLOW}[*] Menambahkan repository Nginx Mainline...${NC}"
echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/mainline/$OS $VERSION_CODENAME nginx" | tee /etc/apt/sources.list.d/nginx.list

# Pinning agar tidak tertimpa oleh repo default OS
echo -e "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" | tee /etc/apt/preferences.d/99nginx

# 6. Install Nginx
echo -e "${YELLOW}[*] Menginstall Nginx versi terbaru (Mainline)...${NC}"
apt-get update -qq
apt-get install -y -qq nginx > /dev/null 2>&1

# 7. Konfigurasi Hardening
echo -e "${YELLOW}[*] Menerapkan konfigurasi Hardening...${NC}"

cat << 'EOF' > /etc/nginx/conf.d/hardening.conf
# ==========================================
# NGINX SECURITY HARDENING CONFIGURATION
# ==========================================

# 1. Hide Nginx Version (Mencegah Information Disclosure)
server_tokens off;

# 2. Security Headers (Mencegah Clickjacking, XSS, MIME-Sniffing)
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;

# 3. Buffer Overflow Protection (Membatasi ukuran request)
client_body_buffer_size 10K;
client_header_buffer_size 1k;
# Sesuaikan client_max_body_size jika aplikasi Anda butuh upload file besar (default 1M)
client_max_body_size 8M; 
large_client_header_buffers 2 1k;

# 4. Timeouts (Mencegah serangan Slowloris / DoS)
client_body_timeout 12;
client_header_timeout 12;
keepalive_timeout 15;
send_timeout 10;

# 5. Limit Request Methods (Hanya izinkan method standar)
# Catatan: Ini diterapkan di block server default. Untuk vhost spesifik, sesuaikan di file vhost.
EOF

# Modifikasi nginx.conf utama untuk memastikan conf.d di-include dan log format aman
if ! grep -q "include /etc/nginx/conf.d/hardening.conf;" /etc/nginx/nginx.conf; then
    # Pastikan include conf.d ada (biasanya sudah ada default)
    sed -i '/http {/a \    include /etc/nginx/conf.d/*.conf;' /etc/nginx/nginx.conf 2>/dev/null || true
fi

# 8. Test Konfigurasi Nginx
echo -e "${YELLOW}[*] Menguji konfigurasi Nginx...${NC}"
nginx -t

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Konfigurasi Nginx gagal. Membatalkan restart.${NC}"
    exit 1
fi

# 9. Restart dan Enable Nginx
echo -e "${YELLOW}[*] Merestart dan mengaktifkan Nginx...${NC}"
systemctl restart nginx
systemctl enable nginx

# 10. Konfigurasi Firewall (UFW) jika ada
if command -v ufw &> /dev/null; then
    echo -e "${YELLOW}[*] Mengkonfigurasi UFW Firewall...${NC}"
    ufw allow 'Nginx Full' > /dev/null 2>&1 || true
fi

echo -e "${GREEN}========================================================${NC}"
echo -e "${GREEN}  Instalasi dan Hardening Nginx Berhasil!               ${NC}"
echo -e "${GREEN}========================================================${NC}"
echo -e "${YELLOW}Versi Nginx:${NC} $(nginx -v 2>&1)"
echo -e "${YELLOW}Status:${NC} $(systemctl is-active nginx)"
echo -e "${GREEN}========================================================${NC}"
echo -e "${YELLOW}Langkah Selanjutnya:${NC}"
echo -e "1. Buat Server Block (Virtual Host) di /etc/nginx/conf.d/domainanda.com.conf"
echo -e "2. Install SSL (Sangat Disarankan): apt install certbot python3-certbot-nginx"
echo -e "3. Jalankan: certbot --nginx -d domainanda.com"
echo -e "${GREEN}========================================================${NC}"