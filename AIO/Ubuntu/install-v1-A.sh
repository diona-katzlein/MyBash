#!/usr/bin/env bash

# ============================================================
# One-Click Install Server Stack (Ubuntu)
# Author: IsekaiID (https://github.com/diona-katzlein)
# Version: 1.0.0
# Description: All-In-One script to install Nginx, PHP, Node.js, Python, MySQL
# ============================================================

set -euo pipefail

# =========================
# CONFIG
# =========================
PHP74_VERSION="7.4"
PHP8_VERSION="8.3"
NODE_MAJOR="24"

MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-StrongRootPass123!}"
TIMEZONE="${TIMEZONE:-Asia/Jakarta}"

# =========================
# HELPER
# =========================
log() {
  echo -e "\n\033[1;32m[INFO]\033[0m $1"
}

warn() {
  echo -e "\n\033[1;33m[WARN]\033[0m $1"
}

error() {
  echo -e "\n\033[1;31m[ERROR]\033[0m $1"
}

require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    error "Jalankan script ini sebagai root atau dengan sudo."
    exit 1
  fi
}

detect_ubuntu() {
  if ! grep -qi ubuntu /etc/os-release; then
    error "Script ini hanya untuk Ubuntu."
    exit 1
  fi
}

# =========================
# START
# =========================
require_root
detect_ubuntu

log "Set timezone"
timedatectl set-timezone "$TIMEZONE" || true

log "Update system"
apt update -y
DEBIAN_FRONTEND=noninteractive apt upgrade -y

log "Install dependencies dasar"
apt install -y software-properties-common ca-certificates apt-transport-https lsb-release gnupg2 unzip zip tar jq build-essential ufw

# =========================
# ADD REPOSITORIES
# =========================
log "Tambah repository Ondrej PHP"
add-apt-repository -y ppa:ondrej/php

log "Tambah repository Nginx stable"
curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/ubuntu $(lsb_release -cs) nginx" > /etc/apt/sources.list.d/nginx.list
echo "Package: *" > /etc/apt/preferences.d/99nginx
echo "Pin: origin nginx.org" >> /etc/apt/preferences.d/99nginx
echo "Pin-Priority: 900" >> /etc/apt/preferences.d/99nginx

log "Tambah repository Node.js ${NODE_MAJOR}.x"
curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash -

log "Tambah repository MySQL"
wget https://dev.mysql.com/get/mysql-apt-config_0.8.33-1_all.deb -O /tmp/mysql-apt-config.deb
DEBIAN_FRONTEND=noninteractive dpkg -i /tmp/mysql-apt-config.deb || apt -f install -y
apt update -y

# =========================
# INSTALL PACKAGES
# =========================
log "Install Nginx"
apt install -y nginx

log "Install utilitas"
apt install -y git curl wget

log "Install Python"
apt install -y python3 python3-pip python3-venv python-is-python3

log "Install Node.js"
apt install -y nodejs

log "Install MySQL Server"
DEBIAN_FRONTEND=noninteractive apt install -y mysql-server

log "Preconfigure MySQL root password (best effort)"
mysql --connect-expired-password -uroot <<EOF || true
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASSWORD}';
FLUSH PRIVILEGES;
EOF

log "Install PHP ${PHP74_VERSION} packages"
apt install -y \
"php${PHP74_VERSION}" "php${PHP74_VERSION}-fpm" "php${PHP74_VERSION}-cli" "php${PHP74_VERSION}-common" \
"php${PHP74_VERSION}-mysql" "php${PHP74_VERSION}-xml" "php${PHP74_VERSION}-xmlrpc" "php${PHP74_VERSION}-curl" \
"php${PHP74_VERSION}-gd" "php${PHP74_VERSION}-imagick" "php${PHP74_VERSION}-mbstring" "php${PHP74_VERSION}-zip" \
"php${PHP74_VERSION}-bcmath" "php${PHP74_VERSION}-soap" "php${PHP74_VERSION}-intl" "php${PHP74_VERSION}-readline" \
"php${PHP74_VERSION}-opcache" "php${PHP74_VERSION}-redis" "php${PHP74_VERSION}-memcached" \
"php${PHP74_VERSION}-sqlite3"

log "Install PHP ${PHP8_VERSION} packages"
apt install -y \
"php${PHP8_VERSION}" "php${PHP8_VERSION}-fpm" "php${PHP8_VERSION}-cli" "php${PHP8_VERSION}-common" \
"php${PHP8_VERSION}-mysql" "php${PHP8_VERSION}-xml" "php${PHP8_VERSION}-xmlrpc" "php${PHP8_VERSION}-curl" \
"php${PHP8_VERSION}-gd" "php${PHP8_VERSION}-imagick" "php${PHP8_VERSION}-mbstring" "php${PHP8_VERSION}-zip" \
"php${PHP8_VERSION}-bcmath" "php${PHP8_VERSION}-soap" "php${PHP8_VERSION}-intl" "php${PHP8_VERSION}-readline" \
"php${PHP8_VERSION}-opcache" "php${PHP8_VERSION}-redis" "php${PHP8_VERSION}-memcached" \
"php${PHP8_VERSION}-sqlite3"

# =========================
# NGINX HARDENING + OPTIMIZE
# =========================
log "Backup nginx.conf lama"
cp /etc/nginx/nginx.conf "/etc/nginx/nginx.conf.bak.$(date +%F-%H%M%S)" || true

log "Tulis nginx.conf optimized"
cat > /etc/nginx/nginx.conf <<'EOF'
user nginx;
worker_processes auto;
pid /var/run/nginx.pid;

events {
    worker_connections 4096;
    multi_accept on;
    use epoll;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    server_tokens off;
    charset utf-8;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    types_hash_max_size 2048;
    server_names_hash_bucket_size 128;
    client_max_body_size 64M;
    client_body_timeout 15s;
    client_header_timeout 15s;
    keepalive_timeout 20s;
    send_timeout 15s;

    reset_timedout_connection on;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log warn;

    gzip on;
    gzip_comp_level 5;
    gzip_min_length 256;
    gzip_proxied any;
    gzip_vary on;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/rss+xml
        application/xml
        image/svg+xml;

    open_file_cache max=200000 inactive=20s;
    open_file_cache_valid 30s;
    open_file_cache_min_uses 2;
    open_file_cache_errors on;

    include /etc/nginx/conf.d/*.conf;
}
EOF

log "Tambahkan security headers global"
cat > /etc/nginx/conf.d/security.conf <<'EOF'
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
EOF

log "Buat default server"
cat > /etc/nginx/conf.d/default.conf <<EOF
server {
    listen 80 default_server;
    server_name _;
    root /var/www/html;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_index index.php;
        fastcgi_pass unix:/run/php/php${PHP8_VERSION}-fpm.sock;
    }

    location ~ /\.ht {
        deny all;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }
}
EOF

# =========================
# PHP OPTIMIZE
# =========================
log "Optimize PHP ${PHP74_VERSION}"
PHP74_INI="/etc/php/${PHP74_VERSION}/fpm/php.ini"
PHP74_POOL="/etc/php/${PHP74_VERSION}/fpm/pool.d/www.conf"

sed -i "s/^memory_limit = .*/memory_limit = 256M/" "$PHP74_INI"
sed -i "s/^upload_max_filesize = .*/upload_max_filesize = 64M/" "$PHP74_INI"
sed -i "s/^post_max_size = .*/post_max_size = 64M/" "$PHP74_INI"
sed -i "s/^max_execution_time = .*/max_execution_time = 120/" "$PHP74_INI"
sed -i "s/^;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/" "$PHP74_INI" || true

cat >> "$PHP74_INI" <<'EOF'

[opcache]
opcache.enable=1
opcache.enable_cli=1
opcache.memory_consumption=192
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=20000
opcache.validate_timestamps=1
opcache.revalidate_freq=2
EOF

sed -i "s/^pm = .*/pm = ondemand/" "$PHP74_POOL"
sed -i "s/^pm.max_children = .*/pm.max_children = 30/" "$PHP74_POOL" || true
sed -i "s/^pm.process_idle_timeout = .*/pm.process_idle_timeout = 10s/" "$PHP74_POOL" || true
sed -i "s/^;pm.max_requests = .*/pm.max_requests = 500/" "$PHP74_POOL" || true

log "Optimize PHP ${PHP8_VERSION}"
PHP8_INI="/etc/php/${PHP8_VERSION}/fpm/php.ini"
PHP8_POOL="/etc/php/${PHP8_VERSION}/fpm/pool.d/www.conf"

sed -i "s/^memory_limit = .*/memory_limit = 256M/" "$PHP8_INI"
sed -i "s/^upload_max_filesize = .*/upload_max_filesize = 64M/" "$PHP8_INI"
sed -i "s/^post_max_size = .*/post_max_size = 64M/" "$PHP8_INI"
sed -i "s/^max_execution_time = .*/max_execution_time = 120/" "$PHP8_INI"
sed -i "s/^;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/" "$PHP8_INI" || true

cat >> "$PHP8_INI" <<'EOF'

[opcache]
opcache.enable=1
opcache.enable_cli=1
opcache.memory_consumption=192
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=20000
opcache.validate_timestamps=1
opcache.revalidate_freq=2
EOF

sed -i "s/^pm = .*/pm = ondemand/" "$PHP8_POOL"
sed -i "s/^pm.max_children = .*/pm.max_children = 30/" "$PHP8_POOL" || true
sed -i "s/^pm.process_idle_timeout = .*/pm.process_idle_timeout = 10s/" "$PHP8_POOL" || true
sed -i "s/^;pm.max_requests = .*/pm.max_requests = 500/" "$PHP8_POOL" || true

# =========================
# MYSQL OPTIMIZE
# =========================
log "Configure MySQL basic optimization"
cat > /etc/mysql/mysql.conf.d/99-custom.cnf <<'EOF'
[mysqld]
bind-address = 127.0.0.1
max_connections = 200
thread_cache_size = 50
table_open_cache = 4000
open_files_limit = 65535
max_allowed_packet = 64M
tmp_table_size = 64M
max_heap_table_size = 64M

# InnoDB
innodb_buffer_pool_size = 512M
innodb_buffer_pool_instances = 1
innodb_log_file_size = 128M
innodb_flush_method = O_DIRECT
innodb_flush_log_at_trx_commit = 1
innodb_file_per_table = 1

# Disable DNS lookup
skip-name-resolve

# Slow query log
slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow.log
long_query_time = 2
EOF

log "Secure MySQL basic setup"
mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" <<EOF || true
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF

# =========================
# FIREWALL
# =========================
log "Configure UFW"
ufw allow OpenSSH || true
ufw allow 'Nginx Full' || true
ufw --force enable || true

# =========================
# ENABLE SERVICES
# =========================
log "Enable and restart services"
systemctl enable nginx
systemctl enable "php${PHP74_VERSION}-fpm"
systemctl enable "php${PHP8_VERSION}-fpm"
systemctl enable mysql

nginx -t
systemctl restart "php${PHP74_VERSION}-fpm"
systemctl restart "php${PHP8_VERSION}-fpm"
systemctl restart mysql
systemctl restart nginx

# =========================
# INFO
# =========================
log "Versi terpasang:"
echo "Nginx: $(nginx -v 2>&1)"
echo "PHP ${PHP74_VERSION}: $(php${PHP74_VERSION} -v | head -n 1)"
echo "PHP ${PHP8_VERSION}: $(php${PHP8_VERSION} -v | head -n 1)"
echo "Node: $(node -v)"
echo "NPM: $(npm -v)"
echo "Python: $(python3 --version)"
echo "MySQL: $(mysql --version)"

log "Selesai."
echo "MySQL root password: ${MYSQL_ROOT_PASSWORD}"
echo "Default web root: /var/www/html"
echo "Default Nginx PHP socket: php${PHP8_VERSION}-fpm"
