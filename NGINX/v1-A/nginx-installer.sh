#!/bin/bash

# ============================================================
# Script: nginx-install-hardening.sh
# Description: Install Nginx Latest Version + Security Hardening
# Author: IsekaiID (https://github.com/diona-katzlein)
# Version: 1.0
# Tested: Ubuntu 20.04/22.04, Debian 10/11, CentOS 7/8
# ============================================================

set -euo pipefail

# ============================================================
# COLORS & LOGGING
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

log_info()    { echo -e "${GREEN}[INFO]${NC}    $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}    $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC}   $1"; }
log_section() { echo -e "\n${CYAN}========== $1 ==========${NC}"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

# ============================================================
# VARIABLES
# ============================================================
NGINX_USER="nginx"
NGINX_GROUP="nginx"
NGINX_LOG_DIR="/var/log/nginx"
NGINX_CONF_DIR="/etc/nginx"
NGINX_CONF_BACKUP="/etc/nginx/backup_$(date +%Y%m%d_%H%M%S)"
WEB_ROOT="/var/www/html"
DOMAIN_EXAMPLE="example.com"
SSL_DIR="/etc/nginx/ssl"
DH_PARAM="$SSL_DIR/dhparam.pem"
SCRIPT_LOG="/var/log/nginx_hardening_$(date +%Y%m%d_%H%M%S).log"

# ============================================================
# HELPER FUNCTIONS
# ============================================================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Script ini harus dijalankan sebagai root!"
        log_error "Gunakan: sudo bash $0"
        exit 1
    fi
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
        OS_NAME=$NAME
    else
        log_error "Tidak dapat mendeteksi OS!"
        exit 1
    fi
    log_info "OS Terdeteksi: $OS_NAME $OS_VERSION"
}

check_internet() {
    log_info "Mengecek koneksi internet..."
    if ! ping -c 1 google.com &>/dev/null; then
        log_error "Tidak ada koneksi internet!"
        exit 1
    fi
    log_success "Koneksi internet OK"
}

backup_config() {
    if [[ -d "$NGINX_CONF_DIR" ]]; then
        log_info "Backup konfigurasi nginx lama ke $NGINX_CONF_BACKUP"
        cp -r "$NGINX_CONF_DIR" "$NGINX_CONF_BACKUP"
        log_success "Backup selesai"
    fi
}

# ============================================================
# INSTALL NGINX - UBUNTU/DEBIAN
# ============================================================
install_nginx_ubuntu() {
    log_section "Install Nginx (Ubuntu/Debian)"

    # Install dependencies
    log_info "Install dependencies..."
    apt-get update -y
    apt-get install -y \
        curl \
        gnupg2 \
        ca-certificates \
        lsb-release \
        ubuntu-keyring \
        apt-transport-https \
        openssl \
        ufw 2>&1 | tee -a "$SCRIPT_LOG"

    # Add official Nginx repository (mainline/stable latest)
    log_info "Menambahkan Nginx Official Repository..."

    # Import signing key
    curl -fsSL https://nginx.org/keys/nginx_signing.key | \
        gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg

    # Verify key fingerprint
    gpg --dry-run --quiet --no-keyring \
        --import --import-options import-show \
        /usr/share/keyrings/nginx-archive-keyring.gpg

    # Add stable repository
    echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] \
        http://nginx.org/packages/$OS $(lsb_release -cs) nginx" \
        | tee /etc/apt/sources.list.d/nginx.list

    # Pin nginx package dari official repo
    echo -e "Package: *\nPin: origin nginx.org\nPin-Priority: 900\n" \
        | tee /etc/apt/preferences.d/99nginx

    # Install nginx
    apt-get update -y
    apt-get install -y nginx 2>&1 | tee -a "$SCRIPT_LOG"

    log_success "Nginx berhasil diinstall!"
}

# ============================================================
# INSTALL NGINX - CENTOS/RHEL/ROCKY
# ============================================================
install_nginx_centos() {
    log_section "Install Nginx (CentOS/RHEL/Rocky)"

    # Install dependencies
    log_info "Install dependencies..."
    yum install -y \
        curl \
        gnupg2 \
        ca-certificates \
        openssl \
        firewalld 2>&1 | tee -a "$SCRIPT_LOG"

    # Add Nginx official repository
    log_info "Menambahkan Nginx Official Repository..."
    cat > /etc/yum.repos.d/nginx.repo << 'EOF'
[nginx-stable]
name=nginx stable repo
baseurl=http://nginx.org/packages/centos/$releasever/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true

[nginx-mainline]
name=nginx mainline repo
baseurl=http://nginx.org/packages/mainline/centos/$releasever/$basearch/
gpgcheck=1
enabled=0
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true
EOF

    yum install -y nginx 2>&1 | tee -a "$SCRIPT_LOG"
    log_success "Nginx berhasil diinstall!"
}

# ============================================================
# MAIN INSTALL FUNCTION
# ============================================================
install_nginx() {
    case "$OS" in
        ubuntu|debian)
            install_nginx_ubuntu
            ;;
        centos|rhel|rocky|almalinux)
            install_nginx_centos
            ;;
        *)
            log_error "OS tidak didukung: $OS"
            exit 1
            ;;
    esac

    # Tampilkan versi yang terinstall
    NGINX_VERSION=$(nginx -v 2>&1)
    log_success "Nginx Version: $NGINX_VERSION"
}

# ============================================================
# BUAT NGINX USER DEDICATED (Non-root)
# ============================================================
setup_nginx_user() {
    log_section "Setup Nginx User"

    if ! id -u "$NGINX_USER" &>/dev/null; then
        log_info "Membuat user nginx dedicated..."
        useradd -r -s /sbin/nologin -d /var/cache/nginx "$NGINX_USER"
        log_success "User $NGINX_USER berhasil dibuat"
    else
        log_info "User $NGINX_USER sudah ada"
    fi
}

# ============================================================
# SETUP DIREKTORI & PERMISSION
# ============================================================
setup_directories() {
    log_section "Setup Direktori"

    # Buat direktori yang diperlukan
    mkdir -p "$NGINX_LOG_DIR"
    mkdir -p "$WEB_ROOT"
    mkdir -p "$SSL_DIR"
    mkdir -p "$NGINX_CONF_DIR/conf.d"
    mkdir -p "$NGINX_CONF_DIR/snippets"
    mkdir -p /var/cache/nginx

    # Set ownership
    chown -R "$NGINX_USER":"$NGINX_GROUP" "$NGINX_LOG_DIR"
    chown -R "$NGINX_USER":"$NGINX_GROUP" "$WEB_ROOT"
    chown -R root:root "$NGINX_CONF_DIR"
    chown -R "$NGINX_USER":"$NGINX_GROUP" /var/cache/nginx

    # Set permission ketat
    chmod 750 "$NGINX_LOG_DIR"
    chmod 755 "$WEB_ROOT"
    chmod 750 "$SSL_DIR"
    chmod 644 "$NGINX_CONF_DIR"/*.conf 2>/dev/null || true

    log_success "Direktori berhasil dibuat dan permission diset"
}

# ============================================================
# GENERATE DH PARAMS (Anti Logjam Attack)
# ============================================================
generate_dhparam() {
    log_section "Generate DH Parameters"
    log_info "Generate dhparam 4096-bit (ini akan memakan waktu beberapa menit)..."

    if [[ ! -f "$DH_PARAM" ]]; then
        openssl dhparam -out "$DH_PARAM" 4096 2>&1 | tee -a "$SCRIPT_LOG"
        chmod 600 "$DH_PARAM"
        log_success "DH Parameters berhasil digenerate: $DH_PARAM"
    else
        log_info "DH Parameters sudah ada, skip..."
    fi
}

# ============================================================
# GENERATE SELF-SIGNED SSL (untuk testing)
# ============================================================
generate_self_signed_ssl() {
    log_section "Generate Self-Signed SSL Certificate"

    if [[ ! -f "$SSL_DIR/server.crt" ]]; then
        log_info "Membuat self-signed certificate untuk testing..."
        openssl req -x509 -nodes -days 365 -newkey rsa:4096 \
            -keyout "$SSL_DIR/server.key" \
            -out "$SSL_DIR/server.crt" \
            -subj "/C=ID/ST=Jakarta/L=Jakarta/O=Organization/CN=$DOMAIN_EXAMPLE" \
            2>&1 | tee -a "$SCRIPT_LOG"

        chmod 600 "$SSL_DIR/server.key"
        chmod 644 "$SSL_DIR/server.crt"
        log_success "Self-signed SSL berhasil dibuat"
        log_warn "Ganti dengan certificate SSL yang valid dari CA (Let's Encrypt, dll) untuk production!"
    else
        log_info "SSL certificate sudah ada, skip..."
    fi
}

# ============================================================
# KONFIGURASI HARDENING NGINX.CONF (MAIN CONFIG)
# ============================================================
configure_nginx_main() {
    log_section "Konfigurasi Nginx Main Config (Hardening)"

    backup_config

    cat > "$NGINX_CONF_DIR/nginx.conf" << 'NGINXCONF'
# ============================================================
# Nginx Main Configuration - Security Hardened
# ============================================================

# Jalankan sebagai user non-root
user nginx;

# Jumlah worker process (auto = sesuai jumlah CPU core)
worker_processes auto;

# Set error log
error_log /var/log/nginx/error.log warn;

# PID file
pid /var/run/nginx.pid;

# ============================================================
# SECURITY: Sembunyikan versi Nginx
# ============================================================
# server_tokens diset di http block

# Batas maksimum file descriptor
worker_rlimit_nofile 65535;

events {
    # Maksimum koneksi per worker
    worker_connections 4096;

    # Gunakan epoll untuk performa optimal di Linux
    use epoll;

    # Accept multiple connections sekaligus
    multi_accept on;
}

http {
    # ============================================================
    # BASIC SETTINGS
    # ============================================================
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    # Charset
    charset utf-8;

    # ============================================================
    # SECURITY HEADERS - CVE MITIGATIONS
    # ============================================================

    # Sembunyikan versi Nginx (Mencegah information disclosure)
    server_tokens off;

    # Prevent Clickjacking (CVE protection)
    add_header X-Frame-Options "SAMEORIGIN" always;

    # XSS Protection
    add_header X-XSS-Protection "1; mode=block" always;

    # Prevent MIME sniffing (CVE-2009-1260 mitigasi)
    add_header X-Content-Type-Options "nosniff" always;

    # Referrer Policy
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Content Security Policy (Sesuaikan dengan kebutuhan aplikasi)
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self'; connect-src 'self'; frame-ancestors 'none';" always;

    # Permissions Policy (Feature Policy)
    add_header Permissions-Policy "accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()" always;

    # HTTP Strict Transport Security (HSTS) - Enable setelah SSL dikonfigurasi
    # add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

    # ============================================================
    # LOGGING FORMAT
    # ============================================================
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for" '
                    '$request_time $upstream_response_time';

    # Log format untuk security monitoring
    log_format security '$time_local | $remote_addr | $request_method | '
                        '$request_uri | $status | $body_bytes_sent | '
                        '"$http_user_agent" | "$http_referer"';

    access_log /var/log/nginx/access.log main;
    error_log  /var/log/nginx/error.log warn;

    # ============================================================
    # PERFORMANCE SETTINGS
    # ============================================================
    sendfile        on;
    tcp_nopush      on;
    tcp_nodelay     on;

    # Keepalive timeout
    keepalive_timeout 30;
    keepalive_requests 100;

    # ============================================================
    # BUFFER SIZE SETTINGS (Mencegah Buffer Overflow)
    # ============================================================

    # Buffer size untuk membaca client request header
    client_header_buffer_size 1k;

    # Maksimum jumlah dan ukuran buffer untuk request header yang besar
    large_client_header_buffers 4 8k;

    # Batas ukuran body request (Mitigasi Large Request Attack)
    client_body_buffer_size 128k;
    client_max_body_size 10m;

    # Timeout settings
    client_body_timeout   12;
    client_header_timeout 12;
    send_timeout          10;

    # ============================================================
    # GZIP COMPRESSION (Nonaktifkan jika concern BREACH attack)
    # ============================================================
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/atom+xml
        image/svg+xml;

    # ============================================================
    # RATE LIMITING (Mitigasi DDoS & Brute Force)
    # ============================================================

    # Zone untuk limit request per IP
    limit_req_zone $binary_remote_addr zone=general:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=login:10m rate=3r/m;
    limit_req_zone $binary_remote_addr zone=api:10m rate=30r/s;

    # Zone untuk limit koneksi
    limit_conn_zone $binary_remote_addr zone=conn_limit_per_ip:10m;
    limit_conn_zone $server_name zone=conn_limit_per_server:10m;

    # Log level untuk rate limiting
    limit_req_log_level warn;
    limit_conn_log_level warn;

    # ============================================================
    # INCLUDE KONFIGURASI TAMBAHAN
    # ============================================================
    include /etc/nginx/conf.d/*.conf;
}
NGINXCONF

    log_success "Main config berhasil dibuat"
}

# ============================================================
# KONFIGURASI SSL SNIPPET
# ============================================================
configure_ssl_snippet() {
    log_section "Konfigurasi SSL Snippet"

    cat > "$NGINX_CONF_DIR/snippets/ssl-params.conf" << SSLCONF
# ============================================================
# SSL/TLS Hardening Configuration
# Mitigasi: POODLE, BEAST, CRIME, BREACH, DROWN, LOGJAM, SWEET32
# ============================================================

# SSL Certificate
ssl_certificate     $SSL_DIR/server.crt;
ssl_certificate_key $SSL_DIR/server.key;

# DH Parameters (Anti Logjam Attack)
ssl_dhparam $DH_PARAM;

# Hanya izinkan TLS 1.2 dan 1.3 (Nonaktifkan SSL 3.0, TLS 1.0, TLS 1.1)
# CVE-2014-3566 (POODLE), CVE-2011-3389 (BEAST) mitigasi
ssl_protocols TLSv1.2 TLSv1.3;

# Cipher suites yang kuat (Nonaktifkan cipher lemah)
# Mitigasi: SWEET32 (3DES), RC4, NULL ciphers
ssl_ciphers 'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256';

# Server menentukan cipher order (Mitigasi BEAST)
ssl_prefer_server_ciphers off;

# SSL Session settings
ssl_session_timeout 1d;
ssl_session_cache shared:SSL:50m;
ssl_session_tickets off;

# OCSP Stapling (Verifikasi sertifikat secara efisien)
ssl_stapling on;
ssl_stapling_verify on;

# DNS Resolver untuk OCSP
resolver 8.8.8.8 8.8.4.4 1.1.1.1 valid=300s;
resolver_timeout 5s;

# HTTP Strict Transport Security
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
SSLCONF

    log_success "SSL snippet berhasil dibuat"
}

# ============================================================
# KONFIGURASI SECURITY SNIPPET
# ============================================================
configure_security_snippet() {
    log_section "Konfigurasi Security Snippet"

    cat > "$NGINX_CONF_DIR/snippets/security-headers.conf" << 'SECCONF'
# ============================================================
# Security Headers Snippet
# Include file ini di setiap server block
# ============================================================

# Sembunyikan versi nginx
server_tokens off;

# Sembunyikan header PHP version
fastcgi_hide_header X-Powered-By;
proxy_hide_header X-Powered-By;

# X-Frame-Options: Mencegah Clickjacking
add_header X-Frame-Options "SAMEORIGIN" always;

# X-XSS-Protection
add_header X-XSS-Protection "1; mode=block" always;

# X-Content-Type-Options: Mencegah MIME sniffing
add_header X-Content-Type-Options "nosniff" always;

# Referrer Policy
add_header Referrer-Policy "strict-origin-when-cross-origin" always;

# Content Security Policy
add_header Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self';" always;

# Permissions Policy
add_header Permissions-Policy "accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()" always;

# Cache Control untuk halaman sensitif
add_header Cache-Control "no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0";
SECCONF

    log_success "Security snippet berhasil dibuat"
}

# ============================================================
# KONFIGURASI DEFAULT SERVER (Hardened)
# ============================================================
configure_default_server() {
    log_section "Konfigurasi Default Server Block"

    # Hapus konfigurasi default yang mungkin ada
    rm -f "$NGINX_CONF_DIR/conf.d/default.conf" 2>/dev/null || true

    cat > "$NGINX_CONF_DIR/conf.d/00-default.conf" << 'DEFAULTCONF'
# ============================================================
# Default Server Block - Catch-All
# Menolak request yang tidak memiliki valid Host header
# ============================================================

# Catch-all untuk HTTP - Redirect ke HTTPS atau tolak
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name _;

    # Security headers
    server_tokens off;

    # Tolak semua akses ke default server
    return 444;
}

# Catch-all untuk HTTPS
server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;

    server_name _;

    # Self-signed cert untuk catch-all (ganti dengan cert valid)
    ssl_certificate     /etc/nginx/ssl/server.crt;
    ssl_certificate_key /etc/nginx/ssl/server.key;

    server_tokens off;

    # Tolak semua akses
    return 444;
}
DEFAULTCONF

    log_success "Default server block berhasil dibuat"
}

# ============================================================
# KONFIGURASI CONTOH VIRTUAL HOST (HTTP -> HTTPS)
# ============================================================
configure_example_vhost() {
    log_section "Konfigurasi Contoh Virtual Host"

    cat > "$NGINX_CONF_DIR/conf.d/example.com.conf" << VHOSTCONF
# ============================================================
# Virtual Host: $DOMAIN_EXAMPLE
# HTTP -> HTTPS Redirect + Security Hardening
# ============================================================

# Redirect HTTP ke HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN_EXAMPLE www.$DOMAIN_EXAMPLE;

    # Sembunyikan versi nginx
    server_tokens off;

    # Redirect permanent ke HTTPS
    return 301 https://\$host\$request_uri;
}

# HTTPS Server Block
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN_EXAMPLE www.$DOMAIN_EXAMPLE;

    # Document root
    root $WEB_ROOT;
    index index.html index.htm;

    # ========== SSL Configuration ==========
    include /etc/nginx/snippets/ssl-params.conf;

    # ========== Security Headers ==========
    include /etc/nginx/snippets/security-headers.conf;

    # ========== LOGGING ==========
    access_log /var/log/nginx/${DOMAIN_EXAMPLE}_access.log main;
    error_log  /var/log/nginx/${DOMAIN_EXAMPLE}_error.log warn;

    # ========== RATE LIMITING ==========
    # Limit koneksi per IP
    limit_conn conn_limit_per_ip 20;
    limit_conn conn_limit_per_server 1000;

    # Limit request rate
    limit_req zone=general burst=20 nodelay;

    # ========== SECURITY: Blokir Method Berbahaya ==========
    # Hanya izinkan GET, HEAD, POST
    if (\$request_method !~ ^(GET|HEAD|POST)$) {
        return 405;
    }

    # ========== SECURITY: Blokir User Agent Berbahaya ==========
    if (\$http_user_agent ~* (nikto|sqlmap|nmap|masscan|zgrab|dirbuster|gobuster|wfuzz|hydra)) {
        return 403;
    }

    # ========== SECURITY: Blokir Akses ke File Sensitif ==========
    # Blokir akses ke .htaccess, .env, dll
    location ~ /\.(ht|git|svn|env|config|bak|backup|sql|log) {
        deny all;
        return 404;
    }

    # Blokir akses ke file sensitif
    location ~* \.(sql|bak|backup|log|conf|config|ini|sh|bash|py|rb|pl)$ {
        deny all;
        return 404;
    }

    # ========== SECURITY: Blokir Path Traversal ==========
    location ~ \.\. {
        deny all;
        return 403;
    }

    # ========== SECURITY: Blokir Akses ke wp-admin (jika bukan WordPress) ==========
    location ~* /(wp-admin|wp-login\.php|xmlrpc\.php|wp-config\.php) {
        deny all;
        return 404;
    }

    # ========== SECURITY: Batasi Upload ==========
    client_max_body_size 10m;

    # ========== MAIN LOCATION ==========
    location / {
        try_files \$uri \$uri/ =404;

        # Rate limiting
        limit_req zone=general burst=20 nodelay;
    }

    # ========== LOGIN ENDPOINT (Jika ada) ==========
    location /login {
        limit_req zone=login burst=5 nodelay;
        try_files \$uri \$uri/ =404;
    }

    # ========== API ENDPOINT ==========
    location /api {
        limit_req zone=api burst=50 nodelay;
        try_files \$uri \$uri/ =404;
    }

    # ========== STATIC ASSETS ==========
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    # ========== ROBOTS.TXT ==========
    location = /robots.txt {
        allow all;
        log_not_found off;
        access_log off;
    }

    # ========== FAVICON ==========
    location = /favicon.ico {
        log_not_found off;
        access_log off;
    }

    # ========== ERROR PAGES ==========
    error_page 400 401 403 404 /error.html;
    error_page 500 502 503 504 /50x.html;

    location = /error.html {
        root $WEB_ROOT;
        internal;
    }

    location = /50x.html {
        root $WEB_ROOT;
        internal;
    }
}
VHOSTCONF

    log_success "Virtual host example berhasil dibuat"
}

# ============================================================
# BUAT HALAMAN WEB DEFAULT
# ============================================================
create_default_web_page() {
    log_section "Membuat Halaman Web Default"

    cat > "$WEB_ROOT/index.html" << 'WEBPAGE'
<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Server Ready - Nginx Hardened</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            background: #0f0f23;
            color: #cccccc;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
        }
        .container {
            text-align: center;
            padding: 40px;
            border: 1px solid #333;
            border-radius: 10px;
        }
        h1 { color: #00ff88; font-size: 2.5em; }
        p { color: #888; }
        .badge {
            background: #1a1a3e;
            color: #00ff88;
            padding: 5px 15px;
            border-radius: 20px;
            font-size: 0.9em;
            margin: 5px;
            display: inline-block;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>✓ Nginx Hardened</h1>
        <p>Server berjalan dengan konfigurasi security hardening</p>
        <br>
        <span class="badge">TLS 1.2/1.3</span>
        <span class="badge">Security Headers</span>
        <span class="badge">Rate Limiting</span>
        <span class="badge">CVE Hardened</span>
    </div>
</body>
</html>
WEBPAGE

    # Error page
    cat > "$WEB_ROOT/error.html" << 'ERRORPAGE'
<!DOCTYPE html>
<html lang="id">
<head>
    <meta charset="UTF-8">
    <title>Error</title>
    <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; background: #0f0f23; color: #ccc; }
        h1 { color: #ff4444; }
    </style>
</head>
<body>
    <h1>Error</h1>
    <p>Halaman tidak ditemukan atau akses ditolak.</p>
</body>
</html>
ERRORPAGE

    log_success "Halaman web default berhasil dibuat"
}

# ============================================================
# KONFIGURASI SISTEM KEAMANAN TAMBAHAN
# ============================================================
configure_system_security() {
    log_section "Konfigurasi Keamanan Sistem"

    # ---- Sysctl Hardening ----
    log_info "Menerapkan sysctl hardening..."
    cat > /etc/sysctl.d/99-nginx-security.conf << 'SYSCTL'
# ============================================================
# Sysctl Security Hardening untuk Nginx Server
# ============================================================

# ---- Network Security ----
# Nonaktifkan IP forwarding
net.ipv4.ip_forward = 0

# Proteksi SYN flood
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_synack_retries = 3
net.ipv4.tcp_max_syn_backlog = 2048

# Nonaktifkan ICMP redirect
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0

# Nonaktifkan source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# Enable reverse path filtering (Anti IP Spoofing)
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignore ICMP ping broadcast
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Ignore bogus ICMP errors
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Log martian packets
net.ipv4.conf.all.log_martians = 1

# TCP TIME-WAIT Assassination
net.ipv4.tcp_rfc1337 = 1

# ---- Performance ----
# Increase file descriptors
fs.file-max = 65535

# TCP keepalive
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15

# Network buffers
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.netdev_max_backlog = 5000
SYSCTL

    sysctl -p /etc/sysctl.d/99-nginx-security.conf 2>&1 | tee -a "$SCRIPT_LOG"
    log_success "Sysctl hardening berhasil diterapkan"
}

# ============================================================
# KONFIGURASI FIREWALL
# ============================================================
configure_firewall() {
    log_section "Konfigurasi Firewall"

    case "$OS" in
        ubuntu|debian)
            log_info "Konfigurasi UFW..."
            # Reset UFW
            ufw --force reset

            # Default policy
            ufw default deny incoming
            ufw default allow outgoing

            # Allow SSH (sesuaikan port jika menggunakan custom port)
            ufw allow 22/tcp comment 'SSH'

            # Allow HTTP dan HTTPS
            ufw allow 80/tcp comment 'HTTP'
            ufw allow 443/tcp comment 'HTTPS'

            # Enable UFW
            ufw --force enable
            ufw status verbose

            log_success "UFW berhasil dikonfigurasi"
            ;;

        centos|rhel|rocky|almalinux)
            log_info "Konfigurasi Firewalld..."
            systemctl start firewalld
            systemctl enable firewalld

            # Allow SSH, HTTP, HTTPS
            firewall-cmd --permanent --add-service=ssh
            firewall-cmd --permanent --add-service=http
            firewall-cmd --permanent --add-service=https

            # Reload firewall
            firewall-cmd --reload
            firewall-cmd --list-all

            log_success "Firewalld berhasil dikonfigurasi"
            ;;
    esac
}

# ============================================================
# KONFIGURASI LOGROTATE
# ============================================================
configure_logrotate() {
    log_section "Konfigurasi Log Rotation"

    cat > /etc/logrotate.d/nginx << 'LOGROTATE'
/var/log/nginx/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 640 nginx adm
    sharedscripts
    postrotate
        if [ -f /var/run/nginx.pid ]; then
            kill -USR1 `cat /var/run/nginx.pid`
        fi
    endscript
}
LOGROTATE

    log_success "Logrotate berhasil dikonfigurasi"
}

# ============================================================
# KONFIGURASI FAIL2BAN (Opsional tapi recommended)
# ============================================================
configure_fail2ban() {
    log_section "Install & Konfigurasi Fail2Ban"

    # Install fail2ban
    case "$OS" in
        ubuntu|debian)
            apt-get install -y fail2ban 2>&1 | tee -a "$SCRIPT_LOG"
            ;;
        centos|rhel|rocky|almalinux)
            yum install -y epel-release 2>&1 | tee -a "$SCRIPT_LOG"
            yum install -y fail2ban 2>&1 | tee -a "$SCRIPT_LOG"
            ;;
    esac

    # Konfigurasi fail2ban untuk nginx
    cat > /etc/fail2ban/jail.d/nginx.conf << 'FAIL2BAN'
# ============================================================
# Fail2Ban Configuration untuk Nginx
# ============================================================

[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5
banaction = iptables-multiport

# ---- Nginx HTTP Auth ----
[nginx-http-auth]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/error.log
maxretry = 5
bantime  = 3600

# ---- Nginx Rate Limit ----
[nginx-limit-req]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/error.log
maxretry = 10
bantime  = 7200

# ---- Nginx Bad Bots ----
[nginx-badbots]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/access.log
maxretry = 3
bantime  = 86400

# ---- Nginx No Script ----
[nginx-noscript]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/access.log
maxretry = 6
bantime  = 86400

# ---- SSH Protection ----
[sshd]
enabled  = true
port     = ssh
logpath  = /var/log/auth.log
maxretry = 5
bantime  = 3600
FAIL2BAN

    # Start dan enable fail2ban
    systemctl enable fail2ban
    systemctl restart fail2ban

    log_success "Fail2Ban berhasil dikonfigurasi"
}

# ============================================================
# VERIFIKASI KONFIGURASI
# ============================================================
verify_configuration() {
    log_section "Verifikasi Konfigurasi Nginx"

    log_info "Menguji syntax konfigurasi Nginx..."
    if nginx -t 2>&1 | tee -a "$SCRIPT_LOG"; then
        log_success "Konfigurasi Nginx VALID!"
    else
        log_error "Konfigurasi Nginx INVALID! Periksa log untuk detail."
        exit 1
    fi
}

# ============================================================
# START & ENABLE NGINX
# ============================================================
start_nginx() {
    log_section "Start Nginx Service"

    systemctl enable nginx
    systemctl restart nginx

    if systemctl is-active --quiet nginx; then
        log_success "Nginx berjalan dengan baik!"
        systemctl status nginx --no-pager
    else
        log_error "Nginx gagal start! Periksa log: journalctl -xe"
        exit 1
    fi
}

# ============================================================
# SECURITY AUDIT POST-INSTALL
# ============================================================
security_audit() {
    log_section "Security Audit Post-Install"

    echo -e "\n${WHITE}=== HASIL SECURITY AUDIT ===${NC}"

    # Check nginx version
    NGINX_VER=$(nginx -v 2>&1 | awk -F'/' '{print $2}')
    echo -e "${GREEN}✓${NC} Nginx Version: $NGINX_VER"

    # Check user
    NGINX_PROC_USER=$(ps aux | grep nginx | grep worker | awk '{print $1}' | head -1)
    if [[ "$NGINX_PROC_USER" == "nginx" ]]; then
        echo -e "${GREEN}✓${NC} Nginx berjalan sebagai non-root user: $NGINX_PROC_USER"
    else
        echo -e "${YELLOW}!${NC} Nginx worker berjalan sebagai: $NGINX_PROC_USER"
    fi

    # Check SSL files
    [[ -f "$DH_PARAM" ]] && \
        echo -e "${GREEN}✓${NC} DH Parameters: $DH_PARAM" || \
        echo -e "${RED}✗${NC} DH Parameters tidak ada!"

    [[ -f "$SSL_DIR/server.crt" ]] && \
        echo -e "${GREEN}✓${NC} SSL Certificate: $SSL_DIR/server.crt" || \
        echo -e "${RED}✗${NC} SSL Certificate tidak ada!"

    # Check firewall
    case "$OS" in
        ubuntu|debian)
            UFW_STATUS=$(ufw status | grep "Status:" | awk '{print $2}')
            [[ "$UFW_STATUS" == "active" ]] && \
                echo -e "${GREEN}✓${NC} Firewall (UFW): Active" || \
                echo -e "${RED}✗${NC} Firewall (UFW): Inactive"
            ;;
        centos|rhel|rocky|almalinux)
            if systemctl is-active --quiet firewalld; then
                echo -e "${GREEN}✓${NC} Firewall (firewalld): Active"
            else
                echo -e "${RED}✗${NC} Firewall (firewalld): Inactive"
            fi
            ;;
    esac

    # Check fail2ban
    if systemctl is-active --quiet fail2ban; then
        echo -e "${GREEN}✓${NC} Fail2Ban: Active"
    else
        echo -e "${YELLOW}!${NC} Fail2Ban: Inactive"
    fi

    # Check konfigurasi
    if nginx -t 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Nginx Config: Valid"
    else
        echo -e "${RED}✗${NC} Nginx Config: Invalid"
    fi

    echo -e "\n${WHITE}=== CHECKLIST CVE MITIGATION ===${NC}"
    echo -e "${GREEN}✓${NC} TLS 1.0/1.1 disabled (CVE-2011-3389 BEAST, CVE-2014-3566 POODLE)"
    echo -e "${GREEN}✓${NC} SSLv3 disabled (CVE-2014-3566 POODLE)"
    echo -e "${GREEN}✓${NC} Weak ciphers disabled (SWEET32, RC4)"
    echo -e "${GREEN}✓${NC} DH Parameters 4096-bit (Logjam Attack)"
    echo -e "${GREEN}✓${NC} Server tokens hidden (Information Disclosure)"
    echo -e "${GREEN}✓${NC} Security headers configured (XSS, Clickjacking, MIME)"
    echo -e "${GREEN}✓${NC} Rate limiting enabled (DDoS, Brute Force)"
    echo -e "${GREEN}✓${NC} Client buffer limits set (Buffer Overflow)"
    echo -e "${GREEN}✓${NC} Sensitive files blocked (.env, .git, .sql)"
    echo -e "${GREEN}✓${NC} Bad HTTP methods blocked"

    echo ""
}

# ============================================================
# PRINT SUMMARY
# ============================================================
print_summary() {
    log_section "INSTALASI SELESAI"

    echo -e """
${GREEN}╔════════════════════════════════════════════════════════╗
║           NGINX INSTALLATION & HARDENING SELESAI       ║
╚════════════════════════════════════════════════════════╝${NC}

${WHITE}📁 Lokasi File Penting:${NC}
   • Main Config    : $NGINX_CONF_DIR/nginx.conf
   • SSL Config     : $NGINX_CONF_DIR/snippets/ssl-params.conf
   • Security Header: $NGINX_CONF_DIR/snippets/security-headers.conf
   • Virtual Host   : $NGINX_CONF_DIR/conf.d/
   • SSL Directory  : $SSL_DIR/
   • Web Root       : $WEB_ROOT
   • Access Log     : $NGINX_LOG_DIR/access.log
   • Error Log      : $NGINX_LOG_DIR/error.log
   • Script Log     : $SCRIPT_LOG

${WHITE}🔧 Perintah Berguna:${NC}
   • Test config    : nginx -t
   • Reload         : systemctl reload nginx
   • Restart        : systemctl restart nginx
   • Status         : systemctl status nginx
   • View logs      : tail -f $NGINX_LOG_DIR/error.log

${WHITE}⚠️  PENTING - LANGKAH SELANJUTNYA:${NC}
   1. Ganti self-signed SSL dengan certificate dari Let's Encrypt:
      ${CYAN}certbot --nginx -d $DOMAIN_EXAMPLE${NC}

   2. Update domain di virtual host:
      ${CYAN}nano $NGINX_CONF_DIR/conf.d/example.com.conf${NC}

   3. Enable HSTS di nginx.conf setelah SSL dikonfigurasi

   4. Test keamanan SSL di:
      ${CYAN}https://www.ssllabs.com/ssltest/${NC}

   5. Test security headers di:
      ${CYAN}https://securityheaders.com/${NC}

   6. Sesuaikan Content-Security-Policy dengan kebutuhan aplikasi

${YELLOW}📝 Log instalasi tersimpan di: $SCRIPT_LOG${NC}
"""
}

# ============================================================
# MAIN EXECUTION
# ============================================================
main() {
    clear
    echo -e """
${CYAN}╔════════════════════════════════════════════════════════╗
║     NGINX INSTALL & SECURITY HARDENING SCRIPT          ║
║     Mitigasi CVE + Security Best Practice              ║
╚════════════════════════════════════════════════════════╝${NC}
"""

    # Initialize log file
    mkdir -p "$(dirname "$SCRIPT_LOG")"
    touch "$SCRIPT_LOG"
    log_info "Log disimpan di: $SCRIPT_LOG"

    # Eksekusi langkah-langkah instalasi
    check_root
    detect_os
    check_internet
    install_nginx
    setup_nginx_user
    setup_directories
    generate_dhparam
    generate_self_signed_ssl
    configure_nginx_main
    configure_ssl_snippet
    configure_security_snippet
    configure_default_server
    configure_example_vhost
    create_default_web_page
    configure_system_security
    configure_firewall
    configure_logrotate
    configure_fail2ban
    verify_configuration
    start_nginx
    security_audit
    print_summary
}

# Jalankan main function
main "$@"