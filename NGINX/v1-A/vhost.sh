#!/bin/bash

# ============================================================
# NGINX VHost Manager - Advanced Configuration Tool
# Author: NGINX VHost Manager
# Version: 2.0
# ============================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Configuration
NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
NGINX_CONF="/etc/nginx/nginx.conf"
WEBROOT="/var/www"
LOG_DIR="/var/log/nginx"
SSL_DIR="/etc/nginx/ssl"
CERTBOT_PATH=$(which certbot 2>/dev/null)

# ============================================================
# UTILITY FUNCTIONS
# ============================================================

print_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║           NGINX VHost Manager - Advanced Tool v2.0           ║"
    echo "║        Reverse Proxy | Laravel | WordPress | Node.js         ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_step() {
    echo -e "\n${BLUE}[→]${NC} ${BOLD}$1${NC}"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_info() {
    echo -e "${CYAN}[i]${NC} $1"
}

print_separator() {
    echo -e "${CYAN}────────────────────────────────────────────────────────────${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Script ini harus dijalankan sebagai root!"
        echo -e "Gunakan: ${YELLOW}sudo $0${NC}"
        exit 1
    fi
}

check_nginx() {
    if ! command -v nginx &>/dev/null; then
        print_error "NGINX tidak ditemukan!"
        read -p "Install NGINX sekarang? (y/n): " install_nginx
        if [[ "$install_nginx" =~ ^[Yy]$ ]]; then
            install_nginx_package
        else
            exit 1
        fi
    fi
}

install_nginx_package() {
    print_step "Menginstall NGINX..."
    if command -v apt &>/dev/null; then
        apt update -qq && apt install -y nginx
    elif command -v yum &>/dev/null; then
        yum install -y nginx
    elif command -v dnf &>/dev/null; then
        dnf install -y nginx
    fi
    systemctl enable nginx
    systemctl start nginx
    print_success "NGINX berhasil diinstall!"
}

create_directories() {
    mkdir -p "$NGINX_SITES_AVAILABLE"
    mkdir -p "$NGINX_SITES_ENABLED"
    mkdir -p "$SSL_DIR"
    mkdir -p "$LOG_DIR"
}

validate_domain() {
    local domain=$1
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z]{2,})+$ ]]; then
        print_error "Format domain tidak valid: $domain"
        return 1
    fi
    return 0
}

validate_port() {
    local port=$1
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
        print_error "Port tidak valid: $port (harus 1-65535)"
        return 1
    fi
    return 0
}

check_port_available() {
    local port=$1
    if ss -tlnp | grep -q ":$port "; then
        print_warning "Port $port sudah digunakan!"
        ss -tlnp | grep ":$port "
        return 1
    fi
    return 0
}

backup_config() {
    local config_file=$1
    if [[ -f "$config_file" ]]; then
        local backup="${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$config_file" "$backup"
        print_info "Backup dibuat: $backup"
    fi
}

reload_nginx() {
    print_step "Validasi konfigurasi NGINX..."
    if nginx -t 2>/dev/null; then
        print_success "Konfigurasi valid!"
        systemctl reload nginx
        print_success "NGINX berhasil direload!"
        return 0
    else
        nginx -t
        print_error "Konfigurasi NGINX tidak valid!"
        return 1
    fi
}

get_server_ip() {
    hostname -I | awk '{print $1}' 2>/dev/null || echo "127.0.0.1"
}

# ============================================================
# SSL/TLS CERTIFICATE MANAGEMENT
# ============================================================

ssl_menu() {
    print_banner
    echo -e "${BOLD}${MAGENTA}  SSL/TLS Certificate Manager${NC}"
    print_separator
    echo -e "  ${WHITE}1.${NC} Generate Self-Signed Certificate"
    echo -e "  ${WHITE}2.${NC} Generate Let's Encrypt Certificate (Certbot)"
    echo -e "  ${WHITE}3.${NC} Generate Let's Encrypt Wildcard Certificate"
    echo -e "  ${WHITE}4.${NC} Renew Let's Encrypt Certificate"
    echo -e "  ${WHITE}5.${NC} Generate CSR + Private Key"
    echo -e "  ${WHITE}6.${NC} Install Custom Certificate"
    echo -e "  ${WHITE}7.${NC} List Certificates"
    echo -e "  ${WHITE}8.${NC} Check Certificate Info"
    echo -e "  ${WHITE}9.${NC} Auto-Renewal Setup (Crontab)"
    echo -e "  ${WHITE}0.${NC} Kembali ke Menu Utama"
    print_separator

    read -p "Pilih opsi [0-9]: " ssl_choice

    case $ssl_choice in
        1) generate_self_signed ;;
        2) generate_letsencrypt ;;
        3) generate_letsencrypt_wildcard ;;
        4) renew_letsencrypt ;;
        5) generate_csr ;;
        6) install_custom_cert ;;
        7) list_certificates ;;
        8) check_cert_info ;;
        9) setup_auto_renewal ;;
        0) return ;;
        *) print_error "Pilihan tidak valid!"; sleep 2; ssl_menu ;;
    esac
}

generate_self_signed() {
    print_banner
    echo -e "${BOLD}Generate Self-Signed Certificate${NC}"
    print_separator

    read -p "Domain (contoh: example.com): " domain
    validate_domain "$domain" || { sleep 2; return; }

    read -p "Validity (hari) [365]: " validity
    validity=${validity:-365}

    read -p "Country Code [ID]: " country
    country=${country:-ID}

    read -p "State/Province [Jakarta]: " state
    state=${state:-Jakarta}

    read -p "Organization [My Organization]: " org
    org=${org:-"My Organization"}

    local cert_dir="$SSL_DIR/$domain"
    mkdir -p "$cert_dir"

    print_step "Membuat Self-Signed Certificate untuk $domain..."

    # Generate private key dan certificate
    openssl req -x509 -nodes -days "$validity" \
        -newkey rsa:4096 \
        -keyout "$cert_dir/private.key" \
        -out "$cert_dir/certificate.crt" \
        -subj "/C=$country/ST=$state/L=$state/O=$org/CN=$domain" \
        -addext "subjectAltName=DNS:$domain,DNS:www.$domain,IP:$(get_server_ip)" \
        2>/dev/null

    if [[ $? -eq 0 ]]; then
        chmod 600 "$cert_dir/private.key"
        chmod 644 "$cert_dir/certificate.crt"

        # Generate DH params untuk security
        print_step "Generating DH Parameters (ini mungkin butuh waktu)..."
        openssl dhparam -out "$cert_dir/dhparam.pem" 2048 2>/dev/null
        
        print_success "Certificate berhasil dibuat!"
        echo ""
        echo -e "${CYAN}Certificate Details:${NC}"
        echo -e "  Private Key : ${GREEN}$cert_dir/private.key${NC}"
        echo -e "  Certificate : ${GREEN}$cert_dir/certificate.crt${NC}"
        echo -e "  DH Params   : ${GREEN}$cert_dir/dhparam.pem${NC}"
        echo -e "  Validity    : ${YELLOW}$validity hari${NC}"
        
        # Show cert info
        echo ""
        print_info "Certificate Info:"
        openssl x509 -in "$cert_dir/certificate.crt" -noout -text | \
            grep -E "(Subject:|Not Before|Not After|DNS:)" | \
            sed 's/^[[:space:]]*/  /'
    else
        print_error "Gagal membuat certificate!"
    fi

    read -p $'\nTekan Enter untuk melanjutkan...'
}

generate_letsencrypt() {
    print_banner
    echo -e "${BOLD}Generate Let's Encrypt Certificate${NC}"
    print_separator

    # Check certbot
    if [[ -z "$CERTBOT_PATH" ]]; then
        print_warning "Certbot tidak ditemukan. Menginstall..."
        if command -v apt &>/dev/null; then
            apt install -y certbot python3-certbot-nginx
        elif command -v yum &>/dev/null; then
            yum install -y certbot python3-certbot-nginx
        fi
        CERTBOT_PATH=$(which certbot)
    fi

    read -p "Domain utama (contoh: example.com): " domain
    validate_domain "$domain" || { sleep 2; return; }

    read -p "Tambah www.$domain? (y/n) [y]: " add_www
    add_www=${add_www:-y}

    read -p "Email untuk notifikasi SSL: " email

    read -p "Webroot path [$WEBROOT/$domain/public]: " webroot
    webroot=${webroot:-"$WEBROOT/$domain/public"}

    print_step "Pilih metode verifikasi:"
    echo "  1. Webroot (recommended - server harus sudah running)"
    echo "  2. Standalone (akan stop web server sementara)"
    echo "  3. DNS Challenge (untuk wildcard/internal server)"
    read -p "Pilih [1]: " verify_method
    verify_method=${verify_method:-1}

    print_step "Mendapatkan certificate untuk $domain..."

    local domains="-d $domain"
    if [[ "$add_www" =~ ^[Yy]$ ]]; then
        domains="$domains -d www.$domain"
    fi

    case $verify_method in
        1)
            mkdir -p "$webroot"
            certbot certonly --webroot \
                -w "$webroot" \
                $domains \
                --email "$email" \
                --agree-tos \
                --non-interactive \
                --rsa-key-size 4096
            ;;
        2)
            systemctl stop nginx
            certbot certonly --standalone \
                $domains \
                --email "$email" \
                --agree-tos \
                --non-interactive \
                --rsa-key-size 4096
            systemctl start nginx
            ;;
        3)
            certbot certonly --manual \
                --preferred-challenges dns \
                $domains \
                --email "$email" \
                --agree-tos \
                --rsa-key-size 4096
            ;;
    esac

    if [[ $? -eq 0 ]]; then
        local cert_path="/etc/letsencrypt/live/$domain"
        print_success "Let's Encrypt certificate berhasil dibuat!"
        echo ""
        echo -e "${CYAN}Certificate Paths:${NC}"
        echo -e "  Cert      : ${GREEN}$cert_path/fullchain.pem${NC}"
        echo -e "  Key       : ${GREEN}$cert_path/privkey.pem${NC}"
        echo -e "  Chain     : ${GREEN}$cert_path/chain.pem${NC}"
        echo ""
        print_info "Certificate berlaku 90 hari dan akan auto-renew jika crontab dikonfigurasi"
    else
        print_error "Gagal mendapatkan certificate!"
    fi

    read -p $'\nTekan Enter untuk melanjutkan...'
}

generate_letsencrypt_wildcard() {
    print_banner
    echo -e "${BOLD}Generate Let's Encrypt Wildcard Certificate${NC}"
    print_separator

    read -p "Domain (contoh: example.com): " domain
    read -p "Email: " email

    print_warning "Wildcard certificate memerlukan DNS Challenge!"
    print_info "Anda perlu menambahkan TXT record ke DNS provider Anda"
    echo ""

    certbot certonly \
        --manual \
        --preferred-challenges dns \
        -d "$domain" \
        -d "*.$domain" \
        --email "$email" \
        --agree-tos \
        --rsa-key-size 4096

    read -p $'\nTekan Enter untuk melanjutkan...'
}

renew_letsencrypt() {
    print_banner
    echo -e "${BOLD}Renew Let's Encrypt Certificate${NC}"
    print_separator

    echo -e "  ${WHITE}1.${NC} Renew semua certificate"
    echo -e "  ${WHITE}2.${NC} Renew certificate spesifik"
    echo -e "  ${WHITE}3.${NC} Dry-run (test tanpa renew)"
    read -p "Pilih [1]: " renew_choice

    case $renew_choice in
        1)
            certbot renew --nginx
            ;;
        2)
            read -p "Domain yang akan direnew: " domain
            certbot renew --cert-name "$domain" --nginx
            ;;
        3)
            certbot renew --dry-run
            ;;
    esac

    read -p $'\nTekan Enter untuk melanjutkan...'
}

generate_csr() {
    print_banner
    echo -e "${BOLD}Generate CSR + Private Key${NC}"
    print_separator

    read -p "Domain: " domain
    read -p "Country [ID]: " country
    country=${country:-ID}
    read -p "State [Jakarta]: " state
    state=${state:-Jakarta}
    read -p "Organization: " org
    read -p "Email: " email

    local cert_dir="$SSL_DIR/$domain"
    mkdir -p "$cert_dir"

    print_step "Membuat CSR untuk $domain..."

    openssl req -new -newkey rsa:4096 -nodes \
        -keyout "$cert_dir/private.key" \
        -out "$cert_dir/${domain}.csr" \
        -subj "/C=$country/ST=$state/L=$state/O=$org/CN=$domain/emailAddress=$email"

    if [[ $? -eq 0 ]]; then
        chmod 600 "$cert_dir/private.key"
        print_success "CSR berhasil dibuat!"
        echo ""
        echo -e "  Private Key : ${GREEN}$cert_dir/private.key${NC}"
        echo -e "  CSR File    : ${GREEN}$cert_dir/${domain}.csr${NC}"
        echo ""
        print_info "Submit CSR berikut ke CA (Certificate Authority):"
        echo ""
        cat "$cert_dir/${domain}.csr"
    fi

    read -p $'\nTekan Enter untuk melanjutkan...'
}

install_custom_cert() {
    print_banner
    echo -e "${BOLD}Install Custom Certificate${NC}"
    print_separator

    read -p "Domain: " domain
    read -p "Path ke Certificate file (.crt/.pem): " cert_file
    read -p "Path ke Private Key file (.key): " key_file
    read -p "Path ke CA Bundle (opsional, tekan Enter untuk skip): " ca_file

    if [[ ! -f "$cert_file" ]]; then
        print_error "Certificate file tidak ditemukan: $cert_file"
        return
    fi

    if [[ ! -f "$key_file" ]]; then
        print_error "Private key file tidak ditemukan: $key_file"
        return
    fi

    local cert_dir="$SSL_DIR/$domain"
    mkdir -p "$cert_dir"

    cp "$cert_file" "$cert_dir/certificate.crt"
    cp "$key_file" "$cert_dir/private.key"
    chmod 600 "$cert_dir/private.key"
    chmod 644 "$cert_dir/certificate.crt"

    if [[ -n "$ca_file" && -f "$ca_file" ]]; then
        cat "$cert_file" "$ca_file" > "$cert_dir/fullchain.crt"
        print_info "Fullchain dibuat: $cert_dir/fullchain.crt"
    fi

    print_success "Certificate berhasil diinstall!"
    echo -e "  Lokasi: ${GREEN}$cert_dir/${NC}"

    read -p $'\nTekan Enter untuk melanjutkan...'
}

list_certificates() {
    print_banner
    echo -e "${BOLD}Daftar Certificates${NC}"
    print_separator

    echo -e "\n${YELLOW}Self-Signed Certificates ($SSL_DIR):${NC}"
    if [[ -d "$SSL_DIR" ]]; then
        for domain_dir in "$SSL_DIR"/*/; do
            if [[ -d "$domain_dir" ]]; then
                domain=$(basename "$domain_dir")
                cert_file="$domain_dir/certificate.crt"
                if [[ -f "$cert_file" ]]; then
                    expiry=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
                    echo -e "  ${GREEN}$domain${NC} - Expires: ${YELLOW}$expiry${NC}"
                fi
            fi
        done
    fi

    echo -e "\n${YELLOW}Let's Encrypt Certificates:${NC}"
    if [[ -d "/etc/letsencrypt/live" ]]; then
        for domain_dir in /etc/letsencrypt/live/*/; do
            domain=$(basename "$domain_dir")
            cert_file="$domain_dir/fullchain.pem"
            if [[ -f "$cert_file" ]]; then
                expiry=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
                days_left=$(( ($(date -d "$expiry" +%s) - $(date +%s)) / 86400 ))
                color="${GREEN}"
                [[ $days_left -lt 30 ]] && color="${YELLOW}"
                [[ $days_left -lt 7 ]] && color="${RED}"
                echo -e "  ${GREEN}$domain${NC} - Expires: ${color}$expiry ($days_left hari)${NC}"
            fi
        done
    fi

    read -p $'\nTekan Enter untuk melanjutkan...'
}

check_cert_info() {
    print_banner
    echo -e "${BOLD}Check Certificate Info${NC}"
    print_separator

    read -p "Domain atau path ke certificate: " input

    local cert_file=""
    if [[ -f "$input" ]]; then
        cert_file="$input"
    elif [[ -f "$SSL_DIR/$input/certificate.crt" ]]; then
        cert_file="$SSL_DIR/$input/certificate.crt"
    elif [[ -f "/etc/letsencrypt/live/$input/fullchain.pem" ]]; then
        cert_file="/etc/letsencrypt/live/$input/fullchain.pem"
    else
        # Check remote
        read -p "Check certificate dari server langsung? (y/n): " check_remote
        if [[ "$check_remote" =~ ^[Yy]$ ]]; then
            read -p "Port [443]: " port
            port=${port:-443}
            echo | openssl s_client -connect "$input:$port" -servername "$input" 2>/dev/null | \
                openssl x509 -noout -text | \
                grep -E "(Subject:|Issuer:|Not Before|Not After|DNS:)"
            read -p $'\nTekan Enter...'
            return
        fi
    fi

    if [[ -n "$cert_file" ]]; then
        echo ""
        openssl x509 -in "$cert_file" -noout -text | \
            grep -E "(Subject:|Issuer:|Not Before|Not After|DNS:|IP Address)" | \
            sed 's/^[[:space:]]*/  /'
    else
        print_error "Certificate tidak ditemukan!"
    fi

    read -p $'\nTekan Enter untuk melanjutkan...'
}

setup_auto_renewal() {
    print_step "Setup Auto-Renewal untuk Let's Encrypt..."

    local cron_job="0 2 * * * /usr/bin/certbot renew --quiet --nginx && systemctl reload nginx"

    # Check if already exists
    if crontab -l 2>/dev/null | grep -q "certbot renew"; then
        print_warning "Auto-renewal sudah dikonfigurasi!"
        crontab -l | grep "certbot"
    else
        (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
        print_success "Auto-renewal berhasil dikonfigurasi!"
        print_info "Cron: $cron_job"
    fi

    # Systemd timer alternative
    if systemctl list-units --type=timer | grep -q certbot; then
        print_info "Certbot systemd timer juga aktif"
        systemctl status certbot.timer --no-pager | head -5
    fi

    read -p $'\nTekan Enter untuk melanjutkan...'
}

# ============================================================
# VHOST CONFIGURATIONS
# ============================================================

# --- REVERSE PROXY (Node.js, Python, Ruby, Go, etc.) ---
create_reverse_proxy() {
    print_banner
    echo -e "${BOLD}${CYAN}Create Reverse Proxy VHost${NC}"
    print_separator

    read -p "Domain (contoh: app.example.com): " domain
    validate_domain "$domain" || { sleep 2; return; }

    read -p "Upstream host [127.0.0.1]: " upstream_host
    upstream_host=${upstream_host:-127.0.0.1}

    read -p "Upstream port [3000]: " upstream_port
    upstream_port=${upstream_port:-3000}

    read -p "Nama aplikasi (untuk PM2/logging): " app_name
    app_name=${app_name:-app}

    read -p "Enable WebSocket support? (y/n) [n]: " enable_ws
    read -p "Enable SSL? (y/n) [n]: " enable_ssl
    read -p "Enable rate limiting? (y/n) [y]: " enable_rate

    enable_rate=${enable_rate:-y}

    local ssl_config=""
    local ssl_redirect=""

    if [[ "$enable_ssl" =~ ^[Yy]$ ]]; then
        ssl_config=$(get_ssl_config "$domain")
        ssl_redirect="
server {
    listen 80;
    server_name $domain www.$domain;
    return 301 https://\$server_name\$request_uri;
}
"
    fi

    local ws_config=""
    if [[ "$enable_ws" =~ ^[Yy]$ ]]; then
        ws_config="
    # WebSocket Support
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \"upgrade\";"
    fi

    local rate_config=""
    if [[ "$enable_rate" =~ ^[Yy]$ ]]; then
        rate_config="
    # Rate Limiting
    limit_req zone=api burst=20 nodelay;
    limit_req_status 429;"
    fi

    local config_file="$NGINX_SITES_AVAILABLE/$domain"

    cat > "$config_file" << EOF
# ============================================================
# Reverse Proxy VHost: $domain
# App: $app_name | Upstream: $upstream_host:$upstream_port
# Generated: $(date)
# ============================================================

# Upstream definition
upstream ${app_name}_backend {
    server $upstream_host:$upstream_port;

    # Load balancing (uncomment jika multiple instance)
    # server $upstream_host:$((upstream_port + 1));
    # server $upstream_host:$((upstream_port + 2));

    keepalive 32;
    keepalive_requests 100;
    keepalive_timeout 60s;
}

$ssl_redirect

server {
    $(if [[ "$enable_ssl" =~ ^[Yy]$ ]]; then echo "listen 443 ssl http2;"; else echo "listen 80;"; fi)
    listen [::]:$(if [[ "$enable_ssl" =~ ^[Yy]$ ]]; then echo "443 ssl http2;"; else echo "80;"; fi)

    server_name $domain www.$domain;
    charset utf-8;

    # ─── Logging ────────────────────────────────────────────
    access_log $LOG_DIR/${domain}_access.log combined buffer=512k flush=1m;
    error_log  $LOG_DIR/${domain}_error.log warn;

    $ssl_config

    # ─── Security Headers ───────────────────────────────────
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;
    $(if [[ "$enable_ssl" =~ ^[Yy]$ ]]; then echo 'add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;'; fi)

    # ─── Body Size ──────────────────────────────────────────
    client_max_body_size 50M;
    client_body_buffer_size 128k;

    # ─── Proxy to Backend ───────────────────────────────────
    location / {
        $rate_config

        proxy_pass http://${app_name}_backend;
        $ws_config

        # Proxy headers
        proxy_set_header Host              \$http_host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host  \$host;
        proxy_set_header X-Forwarded-Port  \$server_port;

        # Proxy timeouts
        proxy_connect_timeout   60s;
        proxy_send_timeout      60s;
        proxy_read_timeout      60s;

        # Proxy buffers
        proxy_buffering         on;
        proxy_buffer_size       4k;
        proxy_buffers           8 4k;
        proxy_busy_buffers_size 8k;

        # Error handling
        proxy_next_upstream error timeout invalid_header http_500 http_502 http_503;
        proxy_next_upstream_tries 3;
    }

    # ─── API Endpoints (optional) ───────────────────────────
    location /api/ {
        limit_req zone=api burst=10 nodelay;

        proxy_pass http://${app_name}_backend;
        proxy_set_header Host            \$http_host;
        proxy_set_header X-Real-IP       \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 30s;
    }

    # ─── Health Check ────────────────────────────────────────
    location /health {
        access_log off;
        proxy_pass http://${app_name}_backend;
        proxy_set_header Host \$host;
    }

    # ─── Static Files (jika disajikan langsung) ──────────────
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        # Coba serve static dulu, fallback ke backend
        try_files \$uri @backend;
        expires 30d;
        add_header Cache-Control "public, no-transform";
        access_log off;
    }

    location @backend {
        proxy_pass http://${app_name}_backend;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    # ─── Block Bad Bots ──────────────────────────────────────
    location = /robots.txt {
        access_log off;
        log_not_found off;
    }

    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    # ─── Custom Error Pages ──────────────────────────────────
    error_page 502 503 504 /50x.html;
    location = /50x.html {
        root /usr/share/nginx/html;
        internal;
    }
}
EOF

    enable_vhost "$domain"
    read -p $'\nTekan Enter untuk melanjutkan...'
}

# --- LARAVEL ---
create_laravel_vhost() {
    print_banner
    echo -e "${BOLD}${CYAN}Create Laravel VHost${NC}"
    print_separator

    read -p "Domain (contoh: myapp.com): " domain
    validate_domain "$domain" || { sleep 2; return; }

    read -p "Laravel project path [$WEBROOT/$domain]: " project_path
    project_path=${project_path:-"$WEBROOT/$domain"}

    read -p "PHP Version (7.4/8.0/8.1/8.2/8.3) [8.2]: " php_version
    php_version=${php_version:-8.2}

    read -p "Enable SSL? (y/n) [n]: " enable_ssl
    read -p "Enable OPcache optimizations? (y/n) [y]: " enable_opcache
    enable_opcache=${enable_opcache:-y}

    local webroot="$project_path/public"
    mkdir -p "$webroot"

    local ssl_config=""
    local ssl_redirect=""
    local ssl_listen="listen 80;"

    if [[ "$enable_ssl" =~ ^[Yy]$ ]]; then
        ssl_config=$(get_ssl_config "$domain")
        ssl_listen="listen 443 ssl http2;"
        ssl_redirect="
server {
    listen 80;
    server_name $domain www.$domain;
    return 301 https://\$server_name\$request_uri;
}"
    fi

    cat > "$NGINX_SITES_AVAILABLE/$domain" << EOF
# ============================================================
# Laravel VHost: $domain
# PHP: $php_version | Root: $webroot
# Generated: $(date)
# ============================================================

$ssl_redirect

server {
    $ssl_listen
    listen [::]:$(if [[ "$enable_ssl" =~ ^[Yy]$ ]]; then echo "443 ssl http2;"; else echo "80;"; fi)

    server_name $domain www.$domain;
    root $webroot;
    index index.php index.html;
    charset utf-8;

    # ─── Logging ────────────────────────────────────────────
    access_log $LOG_DIR/${domain}_access.log combined buffer=512k flush=1m;
    error_log  $LOG_DIR/${domain}_error.log warn;

    $ssl_config

    # ─── Security Headers ───────────────────────────────────
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    $(if [[ "$enable_ssl" =~ ^[Yy]$ ]]; then echo 'add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;'; fi)

    # ─── Upload Size ─────────────────────────────────────────
    client_max_body_size 100M;
    client_body_buffer_size 128k;

    # ─── Laravel Main Router ─────────────────────────────────
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    # ─── PHP-FPM ─────────────────────────────────────────────
    location ~ \.php$ {
        fastcgi_pass   unix:/var/run/php/php${php_version}-fpm.sock;
        fastcgi_index  index.php;
        fastcgi_param  SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include        fastcgi_params;

        # FastCGI tuning
        fastcgi_connect_timeout    60s;
        fastcgi_send_timeout       180s;
        fastcgi_read_timeout       180s;
        fastcgi_buffer_size        128k;
        fastcgi_buffers            4 256k;
        fastcgi_busy_buffers_size  256k;
        fastcgi_temp_file_write_size 256k;
        fastcgi_intercept_errors   off;

        # PHP settings via FastCGI
        fastcgi_param PHP_VALUE "
            upload_max_filesize = 100M
            post_max_size = 100M
            max_execution_time = 300
            memory_limit = 256M
        ";

        $(if [[ "$enable_opcache" =~ ^[Yy]$ ]]; then
        echo "# OPcache headers"
        echo "        fastcgi_param PHP_VALUE \"opcache.enable=1\nopcache.memory_consumption=256\nopcache.interned_strings_buffer=16\nopcache.max_accelerated_files=20000\";"
        fi)
    }

    # ─── Static Assets dengan Cache ──────────────────────────
    location ~* \.(jpg|jpeg|png|gif|ico|svg|webp|avif)$ {
        expires 30d;
        add_header Cache-Control "public, no-transform, immutable";
        access_log off;
        try_files \$uri =404;
    }

    location ~* \.(css|js|woff|woff2|ttf|eot)$ {
        expires 7d;
        add_header Cache-Control "public, no-transform";
        access_log off;
        try_files \$uri =404;
    }

    # ─── Laravel Storage & Public ────────────────────────────
    location /storage/ {
        alias $project_path/storage/app/public/;
        expires 7d;
        access_log off;
    }

    # ─── Artisan & Config Files Protection ───────────────────
    location ~ /\.(env|git|htaccess|htpasswd) {
        deny all;
        return 404;
    }

    location ~ ^/(artisan|composer\.(json|lock)|package\.json|webpack\.mix\.js)$ {
        deny all;
        return 404;
    }

    # ─── Block PHP in Uploads ─────────────────────────────────
    location ~* /(?:uploads|files|storage)/.*\.php$ {
        deny all;
    }

    # ─── Telescope (Development - disable in production) ─────
    # location /telescope {
    #     allow 127.0.0.1;
    #     deny all;
    # }

    # ─── Horizon (Queue Monitor) ──────────────────────────────
    # location /horizon {
    #     allow 127.0.0.1;
    #     deny all;
    # }

    # ─── Misc ─────────────────────────────────────────────────
    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    error_page 404 /index.php;
}
EOF

    # Set proper permissions
    if [[ -d "$project_path" ]]; then
        chown -R www-data:www-data "$project_path"
        find "$project_path" -type f -exec chmod 644 {} \;
        find "$project_path" -type d -exec chmod 755 {} \;
        chmod -R 775 "$project_path/storage" "$project_path/bootstrap/cache" 2>/dev/null
        print_success "Permissions set untuk Laravel"
    fi

    enable_vhost "$domain"
    read -p $'\nTekan Enter untuk melanjutkan...'
}

# --- WORDPRESS ---
create_wordpress_vhost() {
    print_banner
    echo -e "${BOLD}${CYAN}Create WordPress VHost${NC}"
    print_separator

    read -p "Domain: " domain
    validate_domain "$domain" || { sleep 2; return; }

    read -p "WordPress path [$WEBROOT/$domain]: " wp_path
    wp_path=${wp_path:-"$WEBROOT/$domain"}

    read -p "PHP Version [8.2]: " php_version
    php_version=${php_version:-8.2}

    read -p "Enable SSL? (y/n) [n]: " enable_ssl
    read -p "Enable WordPress Multisite? (y/n) [n]: " enable_multisite
    read -p "Enable WooCommerce optimizations? (y/n) [n]: " enable_woo

    local ssl_redirect=""
    local ssl_listen="listen 80;"
    local ssl_config=""

    if [[ "$enable_ssl" =~ ^[Yy]$ ]]; then
        ssl_config=$(get_ssl_config "$domain")
        ssl_listen="listen 443 ssl http2;"
        ssl_redirect="
server {
    listen 80;
    server_name $domain www.$domain;
    return 301 https://\$server_name\$request_uri;
}"
    fi

    local multisite_config=""
    if [[ "$enable_multisite" =~ ^[Yy]$ ]]; then
        multisite_config="
    # WordPress Multisite
    if (!-e \$request_filename) {
        rewrite /wp-admin$ \$scheme://\$host\$uri/ permanent;
        rewrite ^(/[^/]+)?(/wp-.*) \$2 last;
        rewrite ^(/[^/]+)?(/.*\.php) \$2 last;
    }"
    fi

    local woo_config=""
    if [[ "$enable_woo" =~ ^[Yy]$ ]]; then
        woo_config="
    # WooCommerce - Skip cache for cart/checkout
    set \$skip_cache 0;
    if (\$request_uri ~* \"/wc-api/|/cart/|/checkout/|/my-account/\") {
        set \$skip_cache 1;
    }"
    fi

    cat > "$NGINX_SITES_AVAILABLE/$domain" << EOF
# ============================================================
# WordPress VHost: $domain
# PHP: $php_version | Root: $wp_path
# Generated: $(date)
# ============================================================

$ssl_redirect

# FastCGI Cache (uncomment untuk enable)
# fastcgi_cache_path /tmp/nginx_cache levels=1:2 keys_zone=${domain%%.*}_cache:100m inactive=60m;
# fastcgi_cache_key "\$scheme\$request_method\$host\$request_uri";

server {
    $ssl_listen
    listen [::]:$(if [[ "$enable_ssl" =~ ^[Yy]$ ]]; then echo "443 ssl http2;"; else echo "80;"; fi)

    server_name $domain www.$domain;
    root $wp_path;
    index index.php index.html;
    charset utf-8;

    # ─── Logging ────────────────────────────────────────────
    access_log $LOG_DIR/${domain}_access.log combined buffer=512k flush=1m;
    error_log  $LOG_DIR/${domain}_error.log warn;

    $ssl_config

    # ─── Security Headers ───────────────────────────────────
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    $(if [[ "$enable_ssl" =~ ^[Yy]$ ]]; then echo 'add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;'; fi)

    # ─── Body Size ──────────────────────────────────────────
    client_max_body_size 64M;

    # ─── Cache Control ──────────────────────────────────────
    $woo_config

    set \$skip_cache 0;
    if (\$request_method = POST)         { set \$skip_cache 1; }
    if (\$query_string != "")            { set \$skip_cache 1; }
    if (\$http_cookie ~* "comment_author|wordpress_[a-f0-9]+|wp-postpass|wordpress_no_cache|wordpress_logged_in") {
        set \$skip_cache 1;
    }

    # ─── WordPress Main ──────────────────────────────────────
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
        $multisite_config
    }

    # ─── PHP-FPM ─────────────────────────────────────────────
    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass unix:/var/run/php/php${php_version}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_index index.php;

        # PHP tuning for WordPress
        fastcgi_buffer_size        128k;
        fastcgi_buffers            256 16k;
        fastcgi_busy_buffers_size  256k;
        fastcgi_temp_file_write_size 256k;
        fastcgi_read_timeout       300s;
        fastcgi_send_timeout       300s;

        fastcgi_param PHP_VALUE "
            upload_max_filesize = 64M
            post_max_size = 64M
            max_execution_time = 300
            memory_limit = 256M
        ";

        # FastCGI Cache (uncomment untuk enable)
        # fastcgi_cache ${domain%%.*}_cache;
        # fastcgi_cache_valid 200 60m;
        # fastcgi_cache_bypass \$skip_cache;
        # fastcgi_no_cache \$skip_cache;
        # add_header X-FastCGI-Cache \$upstream_cache_status;
    }

    # ─── WordPress Admin ─────────────────────────────────────
    location /wp-admin {
        try_files \$uri \$uri/ /index.php?\$args;

        # Optional: Restrict wp-admin access by IP
        # allow 1.2.3.4;
        # deny all;
    }

    # ─── WordPress Login Protection ──────────────────────────
    location = /wp-login.php {
        # Rate limiting untuk brute force protection
        limit_req zone=login burst=3 nodelay;

        include fastcgi_params;
        fastcgi_pass unix:/var/run/php/php${php_version}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    # ─── WP Cron via FastCGI ─────────────────────────────────
    location = /wp-cron.php {
        access_log off;
        include fastcgi_params;
        fastcgi_pass unix:/var/run/php/php${php_version}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    # ─── Static Files ─────────────────────────────────────────
    location ~* \.(jpg|jpeg|png|gif|ico|svg|webp)$ {
        expires 30d;
        add_header Cache-Control "public, no-transform";
        access_log off;
    }

    location ~* \.(css|js|woff|woff2)$ {
        expires 7d;
        add_header Cache-Control "public, no-transform";
        access_log off;
    }

    # ─── WordPress Uploads Protection ────────────────────────
    location ~* /(?:uploads|files)/.*\.php$ {
        deny all;
    }

    # ─── Block Bad Requests ───────────────────────────────────
    location ~* \.(htaccess|htpasswd|ini|log|sh|sql|conf)$ {
        deny all;
    }

    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    # ─── xmlrpc.php Protection ────────────────────────────────
    location = /xmlrpc.php {
        deny all;
        access_log off;
        log_not_found off;
    }

    # ─── Disable Direct PHP in Uploads ───────────────────────
    location ~* /wp-content/uploads/.*\.(php|php5|phtml)$ {
        deny all;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }
}
EOF

    # Set permissions
    if [[ -d "$wp_path" ]]; then
        chown -R www-data:www-data "$wp_path"
        find "$wp_path" -type d -exec chmod 755 {} \;
        find "$wp_path" -type f -exec chmod 644 {} \;
        print_success "Permissions set untuk WordPress"
    fi

    enable_vhost "$domain"
    read -p $'\nTekan Enter untuk melanjutkan...'
}

# --- CODEIGNITER ---
create_codeigniter_vhost() {
    print_banner
    echo -e "${BOLD}${CYAN}Create CodeIgniter VHost${NC}"
    print_separator

    read -p "Domain: " domain
    validate_domain "$domain" || { sleep 2; return; }

    read -p "CodeIgniter path [$WEBROOT/$domain]: " ci_path
    ci_path=${ci_path:-"$WEBROOT/$domain"}

    read -p "PHP Version [8.2]: " php_version
    php_version=${php_version:-8.2}

    echo -e "\nCodeIgniter Version:"
    echo "  1. CodeIgniter 3"
    echo "  2. CodeIgniter 4 (recommended)"
    read -p "Pilih [2]: " ci_version
    ci_version=${ci_version:-2}

    read -p "Enable SSL? (y/n) [n]: " enable_ssl

    local webroot="$ci_path"
    local try_files_config="try_files \$uri \$uri/ /index.php?\$query_string;"

    if [[ "$ci_version" == "2" ]]; then
        # CI4 - webroot adalah public/
        webroot="$ci_path/public"
    fi

    local ssl_config=""
    local ssl_redirect=""
    local ssl_listen="listen 80;"

    if [[ "$enable_ssl" =~ ^[Yy]$ ]]; then
        ssl_config=$(get_ssl_config "$domain")
        ssl_listen="listen 443 ssl http2;"
        ssl_redirect="
server {
    listen 80;
    server_name $domain www.$domain;
    return 301 https://\$server_name\$request_uri;
}"
    fi

    cat > "$NGINX_SITES_AVAILABLE/$domain" << EOF
# ============================================================
# CodeIgniter $(if [[ "$ci_version" == "2" ]]; then echo "4"; else echo "3"; fi) VHost: $domain
# Generated: $(date)
# ============================================================

$ssl_redirect

server {
    $ssl_listen
    listen [::]:$(if [[ "$enable_ssl" =~ ^[Yy]$ ]]; then echo "443 ssl http2;"; else echo "80;"; fi)

    server_name $domain www.$domain;
    root $webroot;
    index index.php index.html;
    charset utf-8;

    # ─── Logging ────────────────────────────────────────────
    access_log $LOG_DIR/${domain}_access.log combined;
    error_log  $LOG_DIR/${domain}_error.log warn;

    $ssl_config

    # ─── Security Headers ───────────────────────────────────
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    client_max_body_size 32M;

    # ─── CodeIgniter Routing ──────────────────────────────────
    location / {
        $try_files_config
    }

    # ─── PHP-FPM ─────────────────────────────────────────────
    location ~ \.php$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/var/run/php/php${php_version}-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;

        fastcgi_buffer_size       128k;
        fastcgi_buffers           4 256k;
        fastcgi_busy_buffers_size 256k;
        fastcgi_read_timeout      300;
    }

    $(if [[ "$ci_version" == "2" ]]; then
    # CI4 specific
    echo "    # ─── CI4 Spark CLI Protection ───────────────────────────"
    echo "    location ~ ^/spark { deny all; }"
    echo ""
    echo "    # ─── CI4 Writable Directory Protection ─────────────────"
    echo "    location ~ ^/writable { deny all; }"
    fi)

    # ─── Static Files ─────────────────────────────────────────
    location ~* \.(jpg|jpeg|gif|png|svg|ico|css|js|woff|woff2)$ {
        expires 30d;
        add_header Cache-Control "public, no-transform";
        access_log off;
    }

    # ─── Block System Folders ────────────────────────────────
    location ~* ^/(application|system|vendor)/ {
        deny all;
        return 404;
    }

    location ~ /\. {
        deny all;
        access_log off;
    }

    location ~* \.(htaccess|htpasswd|env|log|sh|sql)$ {
        deny all;
    }
}
EOF

    chown -R www-data:www-data "$ci_path" 2>/dev/null
    enable_vhost "$domain"
    read -p $'\nTekan Enter untuk melanjutkan...'
}

# --- SYMFONY ---
create_symfony_vhost() {
    print_banner
    echo -e "${BOLD}${CYAN}Create Symfony VHost${NC}"
    print_separator

    read -p "Domain: " domain
    validate_domain "$domain" || { sleep 2; return; }

    read -p "Symfony project path [$WEBROOT/$domain]: " sf_path
    sf_path=${sf_path:-"$WEBROOT/$domain"}

    read -p "PHP Version [8.2]: " php_version
    php_version=${php_version:-8.2}

    read -p "Environment (prod/dev) [prod]: " sf_env
    sf_env=${sf_env:-prod}

    read -p "Enable SSL? (y/n) [n]: " enable_ssl

    local ssl_config=""
    local ssl_redirect=""
    local ssl_listen="listen 80;"

    if [[ "$enable_ssl" =~ ^[Yy]$ ]]; then
        ssl_config=$(get_ssl_config "$domain")
        ssl_listen="listen 443 ssl http2;"
        ssl_redirect="
server {
    listen 80;
    server_name $domain www.$domain;
    return 301 https://\$server_name\$request_uri;
}"
    fi

    cat > "$NGINX_SITES_AVAILABLE/$domain" << EOF
# ============================================================
# Symfony VHost: $domain
# PHP: $php_version | Env: $sf_env
# Generated: $(date)
# ============================================================

$ssl_redirect

server {
    $ssl_listen
    listen [::]:$(if [[ "$enable_ssl" =~ ^[Yy]$ ]]; then echo "443 ssl http2;"; else echo "80;"; fi)

    server_name $domain www.$domain;
    root $sf_path/public;
    index index.php;
    charset utf-8;

    # ─── Logging ────────────────────────────────────────────
    access_log $LOG_DIR/${domain}_access.log combined;
    error_log  $LOG_DIR/${domain}_error.log warn;

    $ssl_config

    # ─── Security Headers ───────────────────────────────────
    add_header X-Frame-Options "DENY" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    $(if [[ "$enable_ssl" =~ ^[Yy]$ ]]; then echo 'add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;'; fi)

    client_max_body_size 50M;

    # ─── Symfony Main Router ─────────────────────────────────
    location / {
        try_files \$uri /index.php\$is_args\$args;
    }

    # ─── PHP-FPM ─────────────────────────────────────────────
    location ~ ^/index\.php(/|$) {
        fastcgi_pass unix:/var/run/php/php${php_version}-fpm.sock;
        fastcgi_split_path_info ^(.+\.php)(/.*)$;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT \$realpath_root;
        fastcgi_param APP_ENV $sf_env;

        # Security: only execute index.php
        internal;

        fastcgi_buffer_size       128k;
        fastcgi_buffers           4 256k;
        fastcgi_busy_buffers_size 256k;
        fastcgi_read_timeout      300;

        fastcgi_param PHP_VALUE "
            upload_max_filesize = 50M
            post_max_size = 50M
            max_execution_time = 300
            memory_limit = 512M
            realpath_cache_size = 4096k
            realpath_cache_ttl = 600
        ";
    }

    # ─── Block Direct PHP Access ──────────────────────────────
    location ~ \.php$ {
        return 404;
    }

    # ─── Static Files ─────────────────────────────────────────
    location ~* \.(jpg|jpeg|gif|png|svg|ico|webp)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    location ~* \.(css|js|woff|woff2|ttf|eot)$ {
        expires 7d;
        add_header Cache-Control "public";
        access_log off;
    }

    # ─── Webpack Encore Assets ────────────────────────────────
    location ~* ^/build/ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    # ─── Symfony Profiler (Development only) ──────────────────
    $(if [[ "$sf_env" == "dev" ]]; then
    echo "    location ~ ^/(_(profiler|wdt)|css|images|js)/ {"
    echo "        try_files \$uri /index.php\$is_args\$args;"
    echo "    }"
    fi)

    # ─── Security ─────────────────────────────────────────────
    location ~ /\. {
        deny all;
        access_log off;
    }

    location ~* \.(env|lock|json|yaml|yml|xml)$ {
        deny all;
        return 404;
    }
}
EOF

    chown -R www-data:www-data "$sf_path" 2>/dev/null
    enable_vhost "$domain"
    read -p $'\nTekan Enter untuk melanjutkan...'
}

# --- YII FRAMEWORK ---
create_yii_vhost() {
    print_banner
    echo -e "${BOLD}${CYAN}Create Yii Framework VHost${NC}"
    print_separator

    read -p "Domain: " domain
    validate_domain "$domain" || { sleep 2; return; }

    read -p "Yii project path [$WEBROOT/$domain]: " yii_path
    yii_path=${yii_path:-"$WEBROOT/$domain"}

    read -p "PHP Version [8.2]: " php_version
    php_version=${php_version:-8.2}

    echo -e "\nYii Version:"
    echo "  1. Yii 1.x"
    echo "  2. Yii 2.x (recommended)"
    read -p "Pilih [2]: " yii_version
    yii_version=${yii_version:-2}

    read -p "Enable SSL? (y/n) [n]: " enable_ssl

    local webroot="$yii_path/web"
    [[ "$yii_version" == "1" ]] && webroot="$yii_path"

    local ssl_config=""
    local ssl_redirect=""
    local ssl_listen="listen 80;"

    if [[ "$enable_ssl" =~ ^[Yy]$ ]]; then
        ssl_config=$(get_ssl_config "$domain")
        ssl_listen="listen 443 ssl http2;"
        ssl_redirect="
server {
    listen 80;
    server_name $domain www.$domain;
    return 301 https://\$server_name\$request_uri;
}"
    fi

    cat > "$NGINX_SITES_AVAILABLE/$domain" << EOF
# ============================================================
# Yii $(if [[ "$yii_version" == "2" ]]; then echo "2.x"; else echo "1.x"; fi) VHost: $domain
# Generated: $(date)
# ============================================================

$ssl_redirect

server {
    $ssl_listen
    listen [::]:$(if [[ "$enable_ssl" =~ ^[Yy]$ ]]; then echo "443 ssl http2;"; else echo "80;"; fi)

    server_name $domain www.$domain;
    root $webroot;
    index index.php;
    charset utf-8;

    # ─── Logging ────────────────────────────────────────────
    access_log $LOG_DIR/${domain}_access.log combined;
    error_log  $LOG_DIR/${domain}_error.log warn;

    $ssl_config

    # ─── Security Headers ───────────────────────────────────
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;

    client_max_body_size 32M;

    # ─── Yii Routing ─────────────────────────────────────────
    location / {
        try_files \$uri \$uri/ /index.php\$is_args\$args;
    }

    # ─── PHP-FPM ─────────────────────────────────────────────
    location ~ \.php$ {
        try_files \$uri =404;
        fastcgi_pass unix:/var/run/php/php${php_version}-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;

        fastcgi_buffer_size       128k;
        fastcgi_buffers           4 256k;
        fastcgi_busy_buffers_size 256k;
        fastcgi_read_timeout      300;
    }

    # ─── Yii Debug & Gii (Development) ───────────────────────
    # location ~ ^/(debug|gii) {
    #     allow 127.0.0.1;
    #     deny all;
    # }

    # ─── Block Protected Yii Directories ────────────────────
    location ~* ^/(protected|framework|themes/\w+/views) {
        deny all;
    }

    # ─── Static Files ─────────────────────────────────────────
    location ~* \.(jpg|jpeg|gif|png|svg|ico|css|js|woff|woff2)$ {
        expires 30d;
        add_header Cache-Control "public, no-transform";
        access_log off;
    }

    location ~ /\. {
        deny all;
        access_log off;
    }
}
EOF

    chown -R www-data:www-data "$yii_path" 2>/dev/null
    enable_vhost "$domain"
    read -p $'\nTekan Enter untuk melanjutkan...'
}

# --- STATIC HTML ---
create_static_vhost() {
    print_banner
    echo -e "${BOLD}${CYAN}Create Static Site VHost${NC}"
    print_separator

    read -p "Domain: " domain
    validate_domain "$domain" || { sleep 2; return; }

    read -p "Document root [$WEBROOT/$domain]: " doc_root
    doc_root=${doc_root:-"$WEBROOT/$domain"}

    read -p "Enable SSL? (y/n) [n]: " enable_ssl
    read -p "Enable gzip? (y/n) [y]: " enable_gzip
    enable_gzip=${enable_gzip:-y}

    local ssl_config=""
    local ssl_redirect=""
    local ssl_listen="listen 80;"

    if [[ "$enable_ssl" =~ ^[Yy]$ ]]; then
        ssl_config=$(get_ssl_config "$domain")
        ssl_listen="listen 443 ssl http2;"
        ssl_redirect="
server {
    listen 80;
    server_name $domain www.$domain;
    return 301 https://\$server_name\$request_uri;
}"
    fi

    cat > "$NGINX_SITES_AVAILABLE/$domain" << EOF
# ============================================================
# Static Site VHost: $domain
# Generated: $(date)
# ============================================================

$ssl_redirect

server {
    $ssl_listen
    listen [::]:$(if [[ "$enable_ssl" =~ ^[Yy]$ ]]; then echo "443 ssl http2;"; else echo "80;"; fi)

    server_name $domain www.$domain;
    root $doc_root;
    index index.html index.htm;
    charset utf-8;

    access_log $LOG_DIR/${domain}_access.log combined;
    error_log  $LOG_DIR/${domain}_error.log warn;

    $ssl_config

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~* \.(jpg|jpeg|gif|png|svg|ico|webp|avif)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    location ~* \.(css|js|woff|woff2|ttf|eot)$ {
        expires 7d;
        add_header Cache-Control "public";
        access_log off;
    }

    location ~ /\. {
        deny all;
    }

    error_page 404 /404.html;
}
EOF

    mkdir -p "$doc_root"
    chown -R www-data:www-data "$doc_root"

    enable_vhost "$domain"
    read -p $'\nTekan Enter untuk melanjutkan...'
}

# ============================================================
# HELPER: Get SSL Config
# ============================================================

get_ssl_config() {
    local domain=$1
    local cert_path=""
    local key_path=""
    local dhparam_path=""

    # Check Let's Encrypt first
    if [[ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]]; then
        cert_path="/etc/letsencrypt/live/$domain/fullchain.pem"
        key_path="/etc/letsencrypt/live/$domain/privkey.pem"
    elif [[ -f "$SSL_DIR/$domain/certificate.crt" ]]; then
        cert_path="$SSL_DIR/$domain/certificate.crt"
        key_path="$SSL_DIR/$domain/private.key"
    else
        # Default paths
        cert_path="$SSL_DIR/$domain/certificate.crt"
        key_path="$SSL_DIR/$domain/private.key"
        print_warning "Certificate tidak ditemukan! Harap buat certificate terlebih dahulu."
    fi

    if [[ -f "$SSL_DIR/$domain/dhparam.pem" ]]; then
        dhparam_path="    ssl_dhparam $SSL_DIR/$domain/dhparam.pem;"
    fi

    cat << EOF

    # ─── SSL Configuration ───────────────────────────────────
    ssl_certificate     $cert_path;
    ssl_certificate_key $key_path;
    $dhparam_path

    # Modern SSL Config
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256';
    ssl_prefer_server_ciphers off;

    # SSL Session
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    # OCSP Stapling
    ssl_stapling        on;
    ssl_stapling_verify on;
    resolver            8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout    5s;

EOF
}

# ============================================================
# NGINX TWEAKING / OPTIMIZATION
# ============================================================

tweak_nginx() {
    print_banner
    echo -e "${BOLD}${MAGENTA}  NGINX Global Optimization${NC}"
    print_separator
    echo -e "  ${WHITE}1.${NC} Apply Global Performance Tweaks"
    echo -e "  ${WHITE}2.${NC} Configure Rate Limiting"
    echo -e "  ${WHITE}3.${NC} Configure Gzip Compression"
    echo -e "  ${WHITE}4.${NC} Configure FastCGI Cache"
    echo -e "  ${WHITE}5.${NC} Configure Proxy Cache"
    echo -e "  ${WHITE}6.${NC} Security Hardening"
    echo -e "  ${WHITE}7.${NC} Configure Worker Processes"
    echo -e "  ${WHITE}8.${NC} Optimize Timeouts & Buffers"
    echo -e "  ${WHITE}9.${NC} Apply All Tweaks (Recommended)"
    echo -e "  ${WHITE}0.${NC} Kembali"
    print_separator

    read -p "Pilih opsi [0-9]: " tweak_choice

    case $tweak_choice in
        1) apply_performance_tweaks ;;
        2) configure_rate_limiting ;;
        3) configure_gzip ;;
        4) configure_fastcgi_cache ;;
        5) configure_proxy_cache ;;
        6) security_hardening ;;
        7) configure_workers ;;
        8) configure_timeouts ;;
        9) apply_all_tweaks ;;
        0) return ;;
        *) print_error "Pilihan tidak valid!"; sleep 2; tweak_nginx ;;
    esac
}

apply_all_tweaks() {
    print_step "Mengaplikasikan semua optimizations..."
    configure_workers_auto
    configure_gzip_auto
    configure_rate_limiting_auto
    security_hardening_auto
    configure_timeouts_auto
    print_success "Semua tweaks berhasil diaplikasikan!"
    reload_nginx
    read -p $'\nTekan Enter untuk melanjutkan...'
}

configure_workers_auto() {
    local cpu_cores=$(nproc)
    local worker_connections=1024
    local total_ram=$(free -m | awk '/^Mem:/{print $2}')

    # Adjust worker_connections based on RAM
    [[ $total_ram -gt 4096 ]] && worker_connections=4096
    [[ $total_ram -gt 8192 ]] && worker_connections=8192

    backup_config "$NGINX_CONF"

    sed -i "s/worker_processes.*/worker_processes $cpu_cores;/" "$NGINX_CONF"

    if ! grep -q "worker_rlimit_nofile" "$NGINX_CONF"; then
        sed -i "/worker_processes/a worker_rlimit_nofile $((worker_connections * 2));" "$NGINX_CONF"
    fi

    print_success "Worker processes: $cpu_cores (CPU cores), connections: $worker_connections"
}

configure_workers() {
    print_banner
    echo -e "${BOLD}Configure Worker Processes${NC}"
    print_separator

    local cpu_cores=$(nproc)
    local current_workers=$(grep "worker_processes" "$NGINX_CONF" | awk '{print $2}' | tr -d ';')

    print_info "CPU Cores: $cpu_cores"
    print_info "Current worker_processes: $current_workers"

    read -p "Worker processes (auto/$cpu_cores): " workers
    workers=${workers:-$cpu_cores}

    read -p "Worker connections [2048]: " connections
    connections=${connections:-2048}

    read -p "Worker rlimit nofile [$((connections * 2))]: " rlimit
    rlimit=${rlimit:-$((connections * 2))}

    backup_config "$NGINX_CONF"

    sed -i "s/worker_processes.*/worker_processes $workers;/" "$NGINX_CONF"

    # Add/update worker_events
    if grep -q "events {" "$NGINX_CONF"; then
        sed -i "/events {/,/}/ s/worker_connections.*/worker_connections $connections;/" "$NGINX_CONF"
    fi

    print_success "Worker configuration updated!"
    reload_nginx
    read -p $'\nTekan Enter...'
}

configure_gzip_auto() {
    local gzip_conf="/etc/nginx/conf.d/gzip.conf"
    cat > "$gzip_conf" << 'EOF'
# ─── Gzip Compression ────────────────────────────────────────
gzip on;
gzip_vary on;
gzip_proxied any;
gzip_comp_level 6;
gzip_buffers 16 8k;
gzip_http_version 1.1;
gzip_min_length 256;
gzip_types
    application/atom+xml
    application/geo+json
    application/javascript
    application/x-javascript
    application/json
    application/ld+json
    application/manifest+json
    application/rdf+xml
    application/rss+xml
    application/xhtml+xml
    application/xml
    font/eot
    font/otf
    font/ttf
    image/svg+xml
    text/css
    text/javascript
    text/plain
    text/xml;
EOF
    print_success "Gzip configuration applied!"
}

configure_gzip() {
    print_banner
    echo -e "${BOLD}Configure Gzip Compression${NC}"
    print_separator

    read -p "Compression level (1-9) [6]: " comp_level
    comp_level=${comp_level:-6}

    configure_gzip_auto

    reload_nginx
    read -p $'\nTekan Enter...'
}

configure_rate_limiting_auto() {
    local rate_conf="/etc/nginx/conf.d/rate_limiting.conf"
    cat > "$rate_conf" << 'EOF'
# ─── Rate Limiting Zones ─────────────────────────────────────
# General API rate limiting
limit_req_zone $binary_remote_addr zone=api:10m     rate=30r/m;
limit_req_zone $binary_remote_addr zone=login:10m   rate=5r/m;
limit_req_zone $binary_remote_addr zone=general:10m rate=100r/m;
limit_req_zone $binary_remote_addr zone=static:10m  rate=200r/m;

# Connection limiting
limit_conn_zone $binary_remote_addr zone=conn_limit_per_ip:10m;
limit_conn_zone $server_name        zone=conn_limit_per_server:10m;

# Status codes for rate limited requests
limit_req_status 429;
limit_conn_status 429;
EOF
    print_success "Rate limiting zones configured!"
}

configure_rate_limiting() {
    print_banner
    echo -e "${BOLD}Configure Rate Limiting${NC}"
    print_separator

    read -p "API rate limit (requests/minute) [30]: " api_rate
    api_rate=${api_rate:-30}
    read -p "Login rate limit (requests/minute) [5]: " login_rate
    login_rate=${login_rate:-5}
    read -p "General rate limit (requests/minute) [100]: " gen_rate
    gen_rate=${gen_rate:-100}

    local rate_conf="/etc/nginx/conf.d/rate_limiting.conf"
    cat > "$rate_conf" << EOF
# ─── Rate Limiting Zones ─────────────────────────────────────
limit_req_zone \$binary_remote_addr zone=api:10m     rate=${api_rate}r/m;
limit_req_zone \$binary_remote_addr zone=login:10m   rate=${login_rate}r/m;
limit_req_zone \$binary_remote_addr zone=general:10m rate=${gen_rate}r/m;
limit_req_zone \$binary_remote_addr zone=static:10m  rate=200r/m;

limit_conn_zone \$binary_remote_addr zone=conn_limit_per_ip:10m;
limit_conn_zone \$server_name        zone=conn_limit_per_server:10m;

limit_req_status 429;
limit_conn_status 429;
EOF

    reload_nginx
    print_success "Rate limiting configured!"
    read -p $'\nTekan Enter...'
}

configure_timeouts_auto() {
    local timeout_conf="/etc/nginx/conf.d/timeouts.conf"
    cat > "$timeout_conf" << 'EOF'
# ─── Timeouts & Buffers ──────────────────────────────────────
# Client timeouts
client_body_timeout         12s;
client_header_timeout       12s;
keepalive_timeout           65s;
keepalive_requests          100;
send_timeout                10s;
reset_timedout_connection   on;

# Buffers
client_body_buffer_size     128k;
client_header_buffer_size   1k;
client_max_body_size        100m;
large_client_header_buffers 4 4k;
output_buffers              1 32k;
postpone_output             1460;

# File cache
open_file_cache             max=200000 inactive=20s;
open_file_cache_valid       30s;
open_file_cache_min_uses    2;
open_file_cache_errors      on;

# Sendfile
sendfile        on;
sendfile_max_chunk 1m;
tcp_nopush      on;
tcp_nodelay     on;

# Hide NGINX version
server_tokens off;
EOF
    print_success "Timeouts & buffers configured!"
}

configure_timeouts() {
    print_banner
    echo -e "${BOLD}Configure Timeouts & Buffers${NC}"
    print_separator
    print_info "Mengapply konfigurasi optimal..."
    configure_timeouts_auto
    reload_nginx
    read -p $'\nTekan Enter...'
}

apply_performance_tweaks() {
    configure_workers_auto
    configure_gzip_auto
    configure_timeouts_auto
    print_success "Performance tweaks applied!"
    reload_nginx
    read -p $'\nTekan Enter...'
}

configure_fastcgi_cache() {
    print_banner
    echo -e "${BOLD}Configure FastCGI Cache${NC}"
    print_separator

    read -p "Cache path [/tmp/nginx_fastcgi_cache]: " cache_path
    cache_path=${cache_path:-/tmp/nginx_fastcgi_cache}
    read -p "Cache size (MB) [1000]: " cache_size
    cache_size=${cache_size:-1000}
    read -p "Cache inactive time [60m]: " cache_inactive
    cache_inactive=${cache_inactive:-60m}

    mkdir -p "$cache_path"
    chown www-data:www-data "$cache_path"

    cat > "/etc/nginx/conf.d/fastcgi_cache.conf" << EOF
# ─── FastCGI Cache ────────────────────────────────────────────
fastcgi_cache_path $cache_path levels=1:2 keys_zone=fastcgi_cache:${cache_size}m inactive=$cache_inactive max_size=${cache_size}m;
fastcgi_cache_key "\$scheme\$request_method\$host\$request_uri";
fastcgi_cache_use_stale error timeout invalid_header http_500 http_503;
fastcgi_ignore_headers Cache-Control Expires Set-Cookie;
fastcgi_cache_lock on;
EOF

    reload_nginx
    print_success "FastCGI cache configured!"
    read -p $'\nTekan Enter...'
}

configure_proxy_cache() {
    print_banner
    echo -e "${BOLD}Configure Proxy Cache${NC}"
    print_separator

    read -p "Cache path [/tmp/nginx_proxy_cache]: " cache_path
    cache_path=${cache_path:-/tmp/nginx_proxy_cache}
    read -p "Cache size (MB) [1000]: " cache_size
    cache_size=${cache_size:-1000}

    mkdir -p "$cache_path"
    chown www-data:www-data "$cache_path"

    cat > "/etc/nginx/conf.d/proxy_cache.conf" << EOF
# ─── Proxy Cache ──────────────────────────────────────────────
proxy_cache_path $cache_path levels=1:2 keys_zone=proxy_cache:${cache_size}m inactive=60m max_size=${cache_size}m;
proxy_cache_key "\$scheme\$request_method\$host\$request_uri";
proxy_cache_use_stale error timeout invalid_header updating http_500 http_502 http_503 http_504;
proxy_cache_lock on;
proxy_cache_valid 200 1d;
proxy_cache_valid 301 302 1h;
proxy_cache_valid any 1m;
EOF

    reload_nginx
    print_success "Proxy cache configured!"
    read -p $'\nTekan Enter...'
}

security_hardening() {
    print_banner
    echo -e "${BOLD}Security Hardening${NC}"
    print_separator
    security_hardening_auto
    reload_nginx
    read -p $'\nTekan Enter...'
}

security_hardening_auto() {
    cat > "/etc/nginx/conf.d/security.conf" << 'EOF'
# ─── Security Hardening ───────────────────────────────────────
# Hide server version
server_tokens off;

# Limit HTTP methods
# (Apply per-server block sesuai kebutuhan)
# if ($request_method !~ ^(GET|HEAD|POST|PUT|DELETE|PATCH)$) { return 405; }

# Block bad User-Agents
map $http_user_agent $blocked_agent {
    default 0;
    ~*malbot   1;
    ~*masscan  1;
    ~*nikto    1;
    ~*sqlmap   1;
    ~*openvas  1;
    ~*nmap     1;
    ~*zgrab    1;
    ""         1;
}

# Block bad referers
map $http_referer $blocked_referer {
    default 0;
    ~*semalt.com  1;
    ~*buttons-for-website.com 1;
}

# Real IP from proxy/CDN (Cloudflare)
# set_real_ip_from 103.21.244.0/22;
# set_real_ip_from 103.22.200.0/22;
# set_real_ip_from 103.31.4.0/22;
# set_real_ip_from 104.16.0.0/13;
# set_real_ip_from 104.24.0.0/14;
# set_real_ip_from 108.162.192.0/18;
# set_real_ip_from 131.0.72.0/22;
# set_real_ip_from 141.101.64.0/18;
# set_real_ip_from 162.158.0.0/15;
# set_real_ip_from 172.64.0.0/13;
# set_real_ip_from 173.245.48.0/20;
# set_real_ip_from 188.114.96.0/20;
# set_real_ip_from 190.93.240.0/20;
# set_real_ip_from 197.234.240.0/22;
# set_real_ip_from 198.41.128.0/17;
# real_ip_header CF-Connecting-IP;
EOF
    print_success "Security hardening applied!"
}

# ============================================================
# VHOST MANAGEMENT
# ============================================================

enable_vhost() {
    local domain=$1
    local config="$NGINX_SITES_AVAILABLE/$domain"
    local link="$NGINX_SITES_ENABLED/$domain"

    if [[ ! -f "$config" ]]; then
        print_error "Config tidak ditemukan: $config"
        return 1
    fi

    if [[ -L "$link" ]]; then
        print_warning "VHost sudah diaktifkan!"
    else
        ln -s "$config" "$link"
        print_success "VHost $domain berhasil diaktifkan!"
    fi

    if reload_nginx; then
        echo ""
        echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║         VHost Berhasil Dibuat!           ║${NC}"
        echo -e "${GREEN}╠══════════════════════════════════════════╣${NC}"
        echo -e "${GREEN}║${NC} Domain  : ${CYAN}http$(if [[ -f "$SSL_DIR/$domain/certificate.crt" ]] || [[ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]]; then echo "s"; fi)://$domain${NC}"
        echo -e "${GREEN}║${NC} Config  : ${YELLOW}$config${NC}"
        echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
    fi
}

disable_vhost() {
    print_banner
    echo -e "${BOLD}Disable VHost${NC}"
    print_separator

    list_vhosts_simple

    read -p "Domain yang akan dinonaktifkan: " domain
    local link="$NGINX_SITES_ENABLED/$domain"

    if [[ -L "$link" ]]; then
        rm "$link"
        reload_nginx
        print_success "VHost $domain berhasil dinonaktifkan!"
    else
        print_error "VHost $domain tidak aktif atau tidak ditemukan!"
    fi

    read -p $'\nTekan Enter...'
}

delete_vhost() {
    print_banner
    echo -e "${BOLD}Delete VHost${NC}"
    print_separator

    list_vhosts_simple

    read -p "Domain yang akan dihapus: " domain

    echo -e "\n${RED}PERINGATAN: Ini akan menghapus konfigurasi untuk $domain!${NC}"
    read -p "Yakin? (ketik 'yes' untuk konfirmasi): " confirm

    if [[ "$confirm" == "yes" ]]; then
        rm -f "$NGINX_SITES_ENABLED/$domain"
        rm -f "$NGINX_SITES_AVAILABLE/$domain"
        reload_nginx
        print_success "VHost $domain berhasil dihapus!"
    else
        print_info "Dibatalkan"
    fi

    read -p $'\nTekan Enter...'
}

list_vhosts_simple() {
    echo -e "\n${YELLOW}Available VHosts:${NC}"
    for f in "$NGINX_SITES_AVAILABLE"/*; do
        [[ -f "$f" ]] || continue
        local name=$(basename "$f")
        if [[ -L "$NGINX_SITES_ENABLED/$name" ]]; then
            echo -e "  ${GREEN}● $name${NC} (aktif)"
        else
            echo -e "  ${RED}○ $name${NC} (nonaktif)"
        fi
    done
}

list_vhosts() {
    print_banner
    echo -e "${BOLD}Daftar VHosts${NC}"
    print_separator

    echo -e "\n${CYAN}{'●'=aktif, '○'=nonaktif}${NC}\n"
    printf "%-30s %-10s %-20s\n" "DOMAIN" "STATUS" "SSL"
    print_separator

    for f in "$NGINX_SITES_AVAILABLE"/*; do
        [[ -f "$f" ]] || continue
        local name=$(basename "$f")
        local status="${RED}Nonaktif${NC}"
        local ssl_status="${RED}No SSL${NC}"

        [[ -L "$NGINX_SITES_ENABLED/$name" ]] && status="${GREEN}Aktif${NC}"

        if [[ -f "/etc/letsencrypt/live/$name/fullchain.pem" ]]; then
            ssl_status="${GREEN}Let's Encrypt${NC}"
        elif [[ -f "$SSL_DIR/$name/certificate.crt" ]]; then
            ssl_status="${YELLOW}Self-Signed${NC}"
        fi

        printf "%-30s %-10b %-20b\n" "$name" "$status" "$ssl_status"
    done

    echo ""
    read -p "Tekan Enter untuk melanjutkan..."
}

view_vhost_config() {
    print_banner
    echo -e "${BOLD}View VHost Config${NC}"
    print_separator

    list_vhosts_simple

    read -p "\nDomain yang ingin dilihat: " domain
    local config="$NGINX_SITES_AVAILABLE/$domain"

    if [[ -f "$config" ]]; then
        echo ""
        cat "$config" | highlight_config
    else
        print_error "Config tidak ditemukan!"
    fi

    read -p $'\nTekan Enter...'
}

highlight_config() {
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*# ]]; then
            echo -e "${CYAN}$line${NC}"
        elif [[ "$line" =~ server_name|root|listen ]]; then
            echo -e "${GREEN}$line${NC}"
        elif [[ "$line" =~ ssl_|proxy_pass|fastcgi_pass ]]; then
            echo -e "${YELLOW}$line${NC}"
        else
            echo "$line"
        fi
    done
}

# ============================================================
# NGINX STATUS & MONITORING
# ============================================================

show_status() {
    print_banner
    echo -e "${BOLD}NGINX Status & Monitoring${NC}"
    print_separator

    echo -e "\n${YELLOW}Service Status:${NC}"
    systemctl status nginx --no-pager -l | head -20

    echo -e "\n${YELLOW}Active Connections:${NC}"
    if curl -s http://localhost/nginx_status &>/dev/null; then
        curl -s http://localhost/nginx_status
    else
        ss -tnp | grep nginx | head -10
    fi

    echo -e "\n${YELLOW}Request Statistics (last 10 lines access log):${NC}"
    tail -10 "$LOG_DIR/access.log" 2>/dev/null || echo "Log tidak ditemukan"

    echo -e "\n${YELLOW}Top IPs:${NC}"
    cat $LOG_DIR/*_access.log 2>/dev/null | \
        awk '{print $1}' | sort | uniq -c | sort -rn | head -10

    echo -e "\n${YELLOW}Top URLs:${NC}"
    cat $LOG_DIR/*_access.log 2>/dev/null | \
        awk '{print $7}' | sort | uniq -c | sort -rn | head -10

    read -p $'\nTekan Enter...'
}

enable_nginx_status() {
    cat > "/etc/nginx/conf.d/nginx_status.conf" << 'EOF'
server {
    listen 127.0.0.1:80;
    server_name localhost;

    location /nginx_status {
        stub_status on;
        access_log off;
        allow 127.0.0.1;
        deny all;
    }
}
EOF
    reload_nginx
    print_success "NGINX status endpoint enabled at http://127.0.0.1/nginx_status"
}

# ============================================================
# MAIN MENU
# ============================================================

main_menu() {
    while true; do
        print_banner

        local nginx_status="${RED}Stopped${NC}"
        systemctl is-active nginx &>/dev/null && nginx_status="${GREEN}Running${NC}"
        local nginx_version=$(nginx -v 2>&1 | grep -oP 'nginx/\K[0-9.]+')
        local server_ip=$(get_server_ip)

        echo -e "  Server IP: ${CYAN}$server_ip${NC} | NGINX: ${CYAN}v$nginx_version${NC} | Status: $nginx_status"
        print_separator

        echo -e "\n  ${BOLD}${YELLOW}[ CREATE VHOST ]${NC}"
        echo -e "  ${WHITE}1.${NC}  Reverse Proxy        ${CYAN}(Node.js/PM2/Python/Go/etc)${NC}"
        echo -e "  ${WHITE}2.${NC}  Laravel              ${CYAN}(PHP Framework)${NC}"
        echo -e "  ${WHITE}3.${NC}  WordPress            ${CYAN}(CMS)${NC}"
        echo -e "  ${WHITE}4.${NC}  CodeIgniter          ${CYAN}(CI3/CI4)${NC}"
        echo -e "  ${WHITE}5.${NC}  Symfony              ${CYAN}(PHP Framework)${NC}"
        echo -e "  ${WHITE}6.${NC}  Yii Framework        ${CYAN}(Yii1/Yii2)${NC}"
        echo -e "  ${WHITE}7.${NC}  Static Site          ${CYAN}(HTML/CSS/JS)${NC}"

        echo -e "\n  ${BOLD}${YELLOW}[ SSL/TLS MANAGEMENT ]${NC}"
        echo -e "  ${WHITE}8.${NC}  SSL Certificate Manager"

        echo -e "\n  ${BOLD}${YELLOW}[ NGINX TWEAKING ]${NC}"
        echo -e "  ${WHITE}9.${NC}  NGINX Optimization & Tweaking"

        echo -e "\n  ${BOLD}${YELLOW}[ VHOST MANAGEMENT ]${NC}"
        echo -e "  ${WHITE}10.${NC} List VHosts"
        echo -e "  ${WHITE}11.${NC} Enable VHost"
        echo -e "  ${WHITE}12.${NC} Disable VHost"
        echo -e "  ${WHITE}13.${NC} Delete VHost"
        echo -e "  ${WHITE}14.${NC} View VHost Config"

        echo -e "\n  ${BOLD}${YELLOW}[ SYSTEM ]${NC}"
        echo -e "  ${WHITE}15.${NC} NGINX Status & Monitoring"
        echo -e "  ${WHITE}16.${NC} Test NGINX Configuration"
        echo -e "  ${WHITE}17.${NC} Reload NGINX"
        echo -e "  ${WHITE}18.${NC} Enable NGINX Status Endpoint"
        echo -e "  ${WHITE}0.${NC}  Exit"

        print_separator
        read -p "Pilih opsi [0-18]: " choice

        case $choice in
            1)  create_reverse_proxy ;;
            2)  create_laravel_vhost ;;
            3)  create_wordpress_vhost ;;
            4)  create_codeigniter_vhost ;;
            5)  create_symfony_vhost ;;
            6)  create_yii_vhost ;;
            7)  create_static_vhost ;;
            8)  ssl_menu ;;
            9)  tweak_nginx ;;
            10) list_vhosts ;;
            11)
                list_vhosts_simple
                read -p "Domain yang akan diaktifkan: " domain
                enable_vhost "$domain"
                read -p $'\nTekan Enter...'
                ;;
            12) disable_vhost ;;
            13) delete_vhost ;;
            14) view_vhost_config ;;
            15) show_status ;;
            16)
                nginx -t
                read -p $'\nTekan Enter...'
                ;;
            17) reload_nginx; read -p $'\nTekan Enter...' ;;
            18) enable_nginx_status; read -p $'\nTekan Enter...' ;;
            0)
                echo -e "\n${GREEN}Goodbye!${NC}\n"
                exit 0
                ;;
            *)
                print_error "Pilihan tidak valid!"
                sleep 1
                ;;
        esac
    done
}

# ============================================================
# ENTRY POINT
# ============================================================

main() {
    check_root
    check_nginx
    create_directories

    # Check untuk argument CLI
    case "${1:-}" in
        --create-proxy)   create_reverse_proxy ;;
        --create-laravel) create_laravel_vhost ;;
        --create-wp)      create_wordpress_vhost ;;
        --ssl)            ssl_menu ;;
        --tweak)          apply_all_tweaks ;;
        --status)         show_status ;;
        --list)           list_vhosts ;;
        *)                main_menu ;;
    esac
}

main "$@"