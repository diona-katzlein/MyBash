#!/bin/bash
set -euo pipefail

# ============================================================
# One-Click Install Script: Nginx, PHP (7.4 & 8.x), Git, Node.js, Python, MySQL
# Author: IsekaiID (https://github.com/diona-katzlein)
# Version: 1.0.0
# Optimasi & Hardening: Nginx, MySQL
# ============================================================

# Warna output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Cek root
if [[ $EUID -ne 0 ]]; then
   log_error "Script ini harus dijalankan sebagai root (sudo)."
   exit 1
fi

# Variabel konfigurasi
MYSQL_ROOT_PASSWORD="YourStrongRootPassword123!"   # Ganti sesuai keinginan
PHP74_VERSION="7.4"
PHP8X_VERSION="8.3"                                # Atau 8.2, 8.1, sesuaikan ketersediaan PPA
NODEJS_MAJOR="22"                                  # LTS terbaru saat ini (22.x)
TIMEZONE="Asia/Jakarta"                            # Sesuaikan zona waktu

# Set timezone
log_info "Mengatur zona waktu ke ${TIMEZONE}..."
timedatectl set-timezone "$TIMEZONE" || true

# ---------------------------------------------------------------------
# 0. Persiapan awal: Update sistem, install repo dependencies
# ---------------------------------------------------------------------
log_info "Memperbarui daftar paket..."
apt update -qq && apt upgrade -y -qq

log_info "Menginstall paket dasar (software-properties-common, dll)..."
apt install -y -qq software-properties-common apt-transport-https ca-certificates gnupg lsb-release

# ---------------------------------------------------------------------
# 1. Install Nginx + Hardening + Optimasi
# ---------------------------------------------------------------------
log_info "Menginstall Nginx..."
apt install -y -qq nginx

log_info "Melakukan hardening dan optimasi Nginx..."

# Backup konfigurasi asli
cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak

# Tulis konfigurasi Nginx yang aman dan optimal
cat > /etc/nginx/nginx.conf <<'EOF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 1024;
    multi_accept on;
    use epoll;
}

http {
    ##
    # Basic Settings
    ##
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;                # Sembunyikan versi Nginx
    client_max_body_size 100M;

    ##
    # Security Headers (diterapkan di setiap server block melalui conf.d)
    ##
    include /etc/nginx/conf.d/*.conf;

    ##
    # SSL Settings (jika perlu)
    ##
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;

    ##
    # Logging Settings
    ##
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    ##
    # Gzip Settings
    ##
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 5;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript image/svg+xml;

    ##
    # Virtual Host Configs
    ##
    include /etc/nginx/sites-enabled/*;
}
EOF

# Konfigurasi keamanan tambahan sebagai file terpisah
cat > /etc/nginx/conf.d/security.conf <<'EOF'
# Keamanan header global
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;

# Batasi metode HTTP
if ($request_method !~ ^(GET|HEAD|POST|PUT|DELETE|PATCH)$) {
    return 405;
}

# Lindungi dari serangan slowloris
client_body_timeout 10s;
client_header_timeout 10s;
send_timeout 10s;

# Batasi ukuran header
large_client_header_buffers 2 1k;
EOF

# Hapus default site yang tidak aman
rm -f /etc/nginx/sites-enabled/default

# Buat default site sederhana dengan header keamanan
cat > /etc/nginx/sites-available/default <<'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    root /var/www/html;
    index index.html index.htm index.nginx-debian.html;

    location / {
        try_files $uri $uri/ =404;
    }

    # Location untuk PHP (akan ditambahkan nanti)
}
EOF
ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default

# Tes konfigurasi dan restart
nginx -t && systemctl restart nginx
log_info "Nginx berhasil diinstal dan diamankan."

# ---------------------------------------------------------------------
# 2. Install PHP 7.4 dan 8.x (FPM & CLI) + semua package pendukung
# ---------------------------------------------------------------------
log_info "Menambahkan PPA ondrej/php untuk versi PHP lama..."
add-apt-repository -y ppa:ondrej/php
apt update -qq

log_info "Menginstall PHP 7.4 (FPM & CLI) dan ekstensi..."
apt install -y -qq \
    "php${PHP74_VERSION}-fpm" \
    "php${PHP74_VERSION}-cli" \
    "php${PHP74_VERSION}-common" \
    "php${PHP74_VERSION}-mysql" \
    "php${PHP74_VERSION}-curl" \
    "php${PHP74_VERSION}-gd" \
    "php${PHP74_VERSION}-mbstring" \
    "php${PHP74_VERSION}-xml" \
    "php${PHP74_VERSION}-zip" \
    "php${PHP74_VERSION}-intl" \
    "php${PHP74_VERSION}-bcmath" \
    "php${PHP74_VERSION}-imagick" \
    "php${PHP74_VERSION}-soap" \
    "php${PHP74_VERSION}-opcache"

log_info "Menginstall PHP ${PHP8X_VERSION} (FPM & CLI) dan ekstensi..."
apt install -y -qq \
    "php${PHP8X_VERSION}-fpm" \
    "php${PHP8X_VERSION}-cli" \
    "php${PHP8X_VERSION}-common" \
    "php${PHP8X_VERSION}-mysql" \
    "php${PHP8X_VERSION}-curl" \
    "php${PHP8X_VERSION}-gd" \
    "php${PHP8X_VERSION}-mbstring" \
    "php${PHP8X_VERSION}-xml" \
    "php${PHP8X_VERSION}-zip" \
    "php${PHP8X_VERSION}-intl" \
    "php${PHP8X_VERSION}-bcmath" \
    "php${PHP8X_VERSION}-imagick" \
    "php${PHP8X_VERSION}-soap" \
    "php${PHP8X_VERSION}-opcache" \
    "php${PHP8X_VERSION}-readline"

# Set default PHP CLI ke versi 8.x (atau sesuaikan)
update-alternatives --set php "/usr/bin/php${PHP8X_VERSION}"
log_info "PHP CLI default: ${PHP8X_VERSION}"

# Optimasi PHP-FPM (contoh untuk 8.x, sesuaikan untuk 7.4 jika perlu)
PHP8X_FPM_POOL="/etc/php/${PHP8X_VERSION}/fpm/pool.d/www.conf"
if [[ -f $PHP8X_FPM_POOL ]]; then
    sed -i "s/^pm.max_children =.*/pm.max_children = 50/" "$PHP8X_FPM_POOL"
    sed -i "s/^pm.start_servers =.*/pm.start_servers = 5/" "$PHP8X_FPM_POOL"
    sed -i "s/^pm.min_spare_servers =.*/pm.min_spare_servers = 5/" "$PHP8X_FPM_POOL"
    sed -i "s/^pm.max_spare_servers =.*/pm.max_spare_servers = 35/" "$PHP8X_FPM_POOL"
    systemctl restart "php${PHP8X_VERSION}-fpm"
fi

log_info "PHP 7.4 dan ${PHP8X_VERSION} berhasil diinstal."

# ---------------------------------------------------------------------
# 3. Install Git, Curl, Wget
# ---------------------------------------------------------------------
log_info "Menginstall Git, Curl, Wget..."
apt install -y -qq git curl wget

# ---------------------------------------------------------------------
# 4. Install Node.js (via NodeSource)
# ---------------------------------------------------------------------
NODESOURCE_URL="https://deb.nodesource.com/setup_${NODEJS_MAJOR}.x"
if curl -s --head "$NODESOURCE_URL" | head -n 1 | grep "200" > /dev/null; then
    log_info "Menginstall Node.js ${NODEJS_MAJOR}.x dari NodeSource..."
    curl -fsSL "$NODESOURCE_URL" | bash -
    apt install -y -qq nodejs
else
    log_warn "NodeSource untuk v${NODEJS_MAJOR} belum tersedia. Menggunakan v22.x (LTS)."
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
    apt install -y -qq nodejs
fi

log_info "Node.js version: $(node -v)"
log_info "npm version: $(npm -v)"

# ---------------------------------------------------------------------
# 5. Install Python (Python3, pip, venv)
# ---------------------------------------------------------------------
log_info "Menginstall Python3, pip, venv..."
apt install -y -qq python3 python3-pip python3-venv python3-dev

# Simlink python3 ke python (bila perlu)
if [[ ! -f /usr/bin/python ]]; then
    ln -s /usr/bin/python3 /usr/bin/python
fi

# ---------------------------------------------------------------------
# 6. Install MySQL dengan optimasi
# ---------------------------------------------------------------------
log_info "Menginstall MySQL Server..."

# Set password root secara non-interaktif
debconf-set-selections <<< "mysql-server mysql-server/root_password password $MYSQL_ROOT_PASSWORD"
debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $MYSQL_ROOT_PASSWORD"

apt install -y -qq mysql-server

# Hardening otomatis (seperti mysql_secure_installation)
log_info "Melakukan hardening MySQL..."
mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<EOF
-- Hapus user anonym
DELETE FROM mysql.user WHERE User='';
-- Hapus remote root (non-localhost)
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
-- Hapus database test
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
-- Set password untuk root (sudah di-set oleh debconf, tapi flush)
FLUSH PRIVILEGES;
EOF

# Optimasi MySQL (tuning dasar)
log_info "Mengoptimasi MySQL (my.cnf)..."
cp /etc/mysql/my.cnf /etc/mysql/my.cnf.bak

cat >> /etc/mysql/my.cnf <<'EOF'
# Optimasi tambahan by script
[mysqld]
# InnoDB tuning
innodb_buffer_pool_size = 1G              # Sesuaikan dengan RAM (misal 70% RAM)
innodb_log_file_size = 256M
innodb_flush_log_at_trx_commit = 2       # Performance > durability (risiko kecil)
innodb_flush_method = O_DIRECT
# Query cache (nonaktifkan di MySQL 8+)
query_cache_type = 0
query_cache_size = 0
# Connection limits
max_connections = 150
# Temp tables
tmp_table_size = 32M
max_heap_table_size = 32M
# Slow query log (aktifkan untuk debugging)
slow_query_log = 0
slow_query_log_file = /var/log/mysql/mysql-slow.log
long_query_time = 2
EOF

systemctl restart mysql
log_info "MySQL berhasil diinstal dan dioptimasi."

# ---------------------------------------------------------------------
# Selesai
# ---------------------------------------------------------------------
log_info "=============================================="
log_info "Instalasi selesai!"
log_info "Ringkasan:"
log_info "   - Nginx       : http://$(hostname -I | awk '{print $1}')"
log_info "   - PHP 7.4     : $(php7.4 -v | head -1)"
log_info "   - PHP ${PHP8X_VERSION}   : $(php -v | head -1)"
log_info "   - Node.js     : $(node -v)"
log_info "   - Python      : $(python3 --version)"
log_info "   - MySQL       : root password = ${MYSQL_ROOT_PASSWORD}"
log_info ""
log_info "Catatan:"
log_info "   - Ubah password MySQL segera setelah login."
log_info "   - Untuk menggunakan PHP 7.4 FPM di Nginx, aktifkan unix socket di site config."
log_info "   - PHP CLI default adalah ${PHP8X_VERSION}."
log_info "=============================================="
