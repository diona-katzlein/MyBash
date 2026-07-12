#!/bin/bash

# ==========================================
# NGINX VHOST MANAGER & TWEAKER
# Support: Node.js, Laravel, CI, Symfony, Yii, WP
# ==========================================

# Warna Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Direktori Default
NGINX_AVAIL="/etc/nginx/sites-available"
NGINX_ENABL="/etc/nginx/sites-enabled"
WEB_ROOT="/var/www"
SNIPPET_DIR="/etc/nginx/snippets"

# Cek Root Privilege
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Error: Script ini harus dijalankan sebagai root (sudo).${NC}"
  exit 1
fi

# Fungsi untuk membuat direktori snippet jika belum ada
setup_snippets() {
    mkdir -p $SNIPPET_DIR
}

# ==========================================
# FITUR 1: NGINX TWEAKING (PERFORMA & KEAMANAN)
# ==========================================
tweak_nginx() {
    echo -e "${YELLOW}[*] Menerapkan Nginx Tweaking...${NC}"
    
    # Backup nginx.conf asli
    if [ -f /etc/nginx/nginx.conf ]; then
        cp /etc/nginx/nginx.conf "/etc/nginx/nginx.conf.bak.$(date +%F)"
    fi

    # Buat file snippet untuk Gzip dan Security
    cat <<EOF > $SNIPPET_DIR/gzip.conf
gzip on;
gzip_vary on;
gzip_proxied any;
gzip_comp_level 6;
gzip_types text/plain text/css text/xml application/json application/javascript application/xml+rss application/atom+xml image/svg+xml;
EOF

    cat <<EOF > $SNIPPET_DIR/security.conf
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header X-Content-Type-Options "nosniff" always;
add_header Referrer-Policy "no-referrer-when-downgrade" always;
# Hapus komentar di bawah jika menggunakan HTTPS penuh
# add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
EOF

    cat <<EOF > $SNIPPET_DIR/cache.conf
location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)$ {
    expires 30d;
    add_header Cache-Control "public, no-transform";
    access_log off;
}
EOF

    # Tweaking nginx.conf utama
    cat <<EOF > /etc/nginx/nginx.conf
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 2048;
    multi_accept on;
    use epoll;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;
    client_max_body_size 64M;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;

    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;

    include $SNIPPET_DIR/gzip.conf;
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF

    echo -e "${GREEN}[+] Nginx Tweaking berhasil diterapkan!${NC}"
    nginx -t && systemctl reload nginx
}

# ==========================================
# FITUR 2: GENERATE SSL (CERTBOT / LET'S ENCRYPT)
# ==========================================
generate_ssl() {
    read -p "Masukkan domain untuk SSL (contoh: example.com): " DOMAIN
    
    if ! command -v certbot &> /dev/null; then
        echo -e "${YELLOW}[*] Certbot belum terinstall. Menginstall...${NC}"
        apt-get update
        apt-get install -y certbot python3-certbot-nginx
    fi

    echo -e "${YELLOW}[*] Memproses SSL untuk $DOMAIN...${NC}"
    certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[+] SSL berhasil dipasang untuk $DOMAIN!${NC}"
    else
        echo -e "${RED}[-] Gagal memasang SSL. Pastikan DNS sudah mengarah ke IP server ini.${NC}"
    fi
}

# ==========================================
# FITUR 3: CREATE VHOST BERDASARKAN APLIKASI
# ==========================================
create_vhost() {
    echo "=========================================="
    echo "       PILIH JENIS APLIKASI"
    echo "=========================================="
    echo "1) Node.js (PM2 Reverse Proxy)"
    echo "2) Laravel"
    echo "3) CodeIgniter (CI4 / Modern)"
    echo "4) Symfony"
    echo "5) Yii2"
    echo "6) WordPress"
    echo "=========================================="
    read -p "Pilih [1-6]: " APP_TYPE

    read -p "Masukkan nama domain (contoh: app.domain.com): " DOMAIN
    read -p "Masukkan path root project (default: $WEB_ROOT/$DOMAIN): " DOC_ROOT
    DOC_ROOT=${DOC_ROOT:-$WEB_ROOT/$DOMAIN}

    # Buat direktori jika belum ada
    mkdir -p $DOC_ROOT
    chown -R www-data:www-data $DOC_ROOT

    # Template dasar Nginx
    NGINX_CONF="$NGINX_AVAIL/$DOMAIN"

    case $APP_TYPE in
        1) # Node.js PM2
            read -p "Masukkan Port aplikasi Node.js (contoh: 3000): " NODE_PORT
            cat <<EOF > $NGINX_CONF
server {
    listen 80;
    server_name $DOMAIN;
    
    include $SNIPPET_DIR/security.conf;
    include $SNIPPET_DIR/cache.conf;

    location / {
        proxy_pass http://127.0.0.1:$NODE_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF
            ;;
        2) # Laravel
            read -p "Masukkan versi PHP (contoh: 8.1): " PHP_VER
            cat <<EOF > $NGINX_CONF
server {
    listen 80;
    server_name $DOMAIN;
    root $DOC_ROOT/public;
    index index.php index.html;

    include $SNIPPET_DIR/security.conf;
    include $SNIPPET_DIR/cache.conf;

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";

    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    error_page 404 /index.php;

    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/php$PHP_VER-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF
            ;;
        3) # CodeIgniter 4
            read -p "Masukkan versi PHP (contoh: 8.1): " PHP_VER
            cat <<EOF > $NGINX_CONF
server {
    listen 80;
    server_name $DOMAIN;
    root $DOC_ROOT/public;
    index index.php index.html;

    include $SNIPPET_DIR/security.conf;
    include $SNIPPET_DIR/cache.conf;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/php$PHP_VER-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
}
EOF
            ;;
        4) # Symfony
            read -p "Masukkan versi PHP (contoh: 8.1): " PHP_VER
            cat <<EOF > $NGINX_CONF
server {
    listen 80;
    server_name $DOMAIN;
    root $DOC_ROOT/public;
    index index.php;

    include $SNIPPET_DIR/security.conf;
    include $SNIPPET_DIR/cache.conf;

    location / {
        try_files \$uri /index.php\$is_args\$args;
    }

    location ~ ^/index\.php(/|\$) {
        fastcgi_pass unix:/var/run/php/php$PHP_VER-fpm.sock;
        fastcgi_split_path_info ^(.+\.php)(/.*)\$;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT \$realpath_root;
        internal;
    }

    location ~ \.php\$ {
        return 404;
    }
}
EOF
            ;;
        5) # Yii2
            read -p "Masukkan versi PHP (contoh: 8.1): " PHP_VER
            cat <<EOF > $NGINX_CONF
server {
    listen 80;
    server_name $DOMAIN;
    root $DOC_ROOT/web;
    index index.php index.html;

    include $SNIPPET_DIR/security.conf;
    include $SNIPPET_DIR/cache.conf;

    location / {
        try_files \$uri \$uri/ /index.php\$is_args\$args;
    }

    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/php$PHP_VER-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
}
EOF
            ;;
        6) # WordPress
            read -p "Masukkan versi PHP (contoh: 8.1): " PHP_VER
            cat <<EOF > $NGINX_CONF
server {
    listen 80;
    server_name $DOMAIN;
    root $DOC_ROOT;
    index index.php index.html;

    include $SNIPPET_DIR/security.conf;
    include $SNIPPET_DIR/cache.conf;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/php$PHP_VER-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }
    
    # Block access to sensitive files
    location ~* wp-config.php {
        deny all;
    }
}
EOF
            ;;
        *)
            echo -e "${RED}Pilihan tidak valid!${NC}"
            exit 1
            ;;
    esac

    # Enable Site
    ln -s $NGINX_CONF $NGINX_ENABL/
    
    # Test & Reload Nginx
    if nginx -t; then
        systemctl reload nginx
        echo -e "${GREEN}[+] Vhost untuk $DOMAIN berhasil dibuat dan diaktifkan!${NC}"
        
        read -p "Apakah Anda ingin langsung memasang SSL (Let's Encrypt) sekarang? (y/n): " INSTALL_SSL
        if [[ "$INSTALL_SSL" == "y" || "$INSTALL_SSL" == "Y" ]]; then
            generate_ssl
        fi
    else
        echo -e "${RED}[-] Konfigurasi Nginx error. Silakan cek manual.${NC}"
    fi
}

# ==========================================
# MENU UTAMA
# ==========================================
while true; do
    clear
    echo "=========================================="
    echo "   NGINX VHOST MANAGER & TWEAKER"
    echo "=========================================="
    echo "1) Buat Vhost Baru (Node/Laravel/CI/dll)"
    echo "2) Terapkan Nginx Tweaking (Performa & Security)"
    echo "3) Pasang / Generate SSL (Let's Encrypt)"
    echo "4) Hapus Vhost"
    echo "5) Keluar"
    echo "=========================================="
    read -p "Pilih Menu [1-5]: " MENU

    case $MENU in
        1) create_vhost ;;
        2) setup_snippets; tweak_nginx ;;
        3) generate_ssl ;;
        4) 
            read -p "Masukkan domain yang ingin dihapus: " DEL_DOMAIN
            rm -f $NGINX_ENABL/$DEL_DOMAIN
            rm -f $NGINX_AVAIL/$DEL_DOMAIN
            nginx -t && systemctl reload nginx
            echo -e "${GREEN}[+] Vhost $DEL_DOMAIN telah dihapus.${NC}"
            read -p "Tekan Enter untuk lanjutkan..."
            ;;
        5) exit 0 ;;
        *) echo -e "${RED}Pilihan tidak valid!${NC}" ;;
    esac
    read -p "Tekan Enter untuk lanjutkan..."
done