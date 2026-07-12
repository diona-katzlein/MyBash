#!/bin/bash

# ============================================================
# Apache Web Server Setup & Management Script
# Support: Laravel/CI/Symfony/Yii, Node.js/Python/Go,
#          WordPress/Joomla, Reverse Proxy, PHP Switch
# Author  : IsekaiID (https://github.com/diona-katzlein)
# Version : 2.0
# ============================================================

# ─────────────────────────────────────────
# COLOR & FORMATTING
# ─────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# ─────────────────────────────────────────
# GLOBAL VARIABLES
# ─────────────────────────────────────────
LOG_FILE="/var/log/apache-setup.log"
APACHE_DIR="/etc/apache2"
VHOST_DIR="${APACHE_DIR}/sites-available"
WEBROOT="/var/www"
PHP_VERSIONS=("7.4" "8.0" "8.1" "8.2" "8.3")
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# ─────────────────────────────────────────
# UTILITY FUNCTIONS
# ─────────────────────────────────────────
log() {
    echo -e "${TIMESTAMP} - $1" >> "${LOG_FILE}"
    echo -e "$1"
}

info()    { log "${CYAN}[INFO]${NC}    $1"; }
success() { log "${GREEN}[SUCCESS]${NC} $1"; }
warning() { log "${YELLOW}[WARNING]${NC} $1"; }
error()   { log "${RED}[ERROR]${NC}   $1"; }
header()  { echo -e "\n${BLUE}${BOLD}══════════════════════════════════════${NC}"; \
            echo -e "${WHITE}${BOLD}  $1${NC}"; \
            echo -e "${BLUE}${BOLD}══════════════════════════════════════${NC}\n"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Script harus dijalankan sebagai root!"
        exit 1
    fi
}

check_os() {
    if [[ ! -f /etc/debian_version ]] && [[ ! -f /etc/ubuntu_release ]]; then
        if ! grep -qi "debian\|ubuntu" /etc/os-release 2>/dev/null; then
            error "Script ini hanya support Debian/Ubuntu!"
            exit 1
        fi
    fi
}

press_enter() {
    echo -e "\n${YELLOW}Tekan [Enter] untuk melanjutkan...${NC}"
    read -r
}

confirm() {
    local msg="$1"
    echo -e "${YELLOW}${msg} (y/n): ${NC}"
    read -r answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# ─────────────────────────────────────────
# 1. INSTALL APACHE
# ─────────────────────────────────────────
install_apache() {
    header "INSTALL APACHE WEB SERVER"

    info "Mengupdate package list..."
    apt-get update -qq >> "${LOG_FILE}" 2>&1

    info "Menginstall Apache2..."
    apt-get install -y apache2 apache2-utils >> "${LOG_FILE}" 2>&1

    info "Menginstall dependencies tambahan..."
    apt-get install -y \
        curl wget git unzip zip \
        openssl ssl-cert \
        libapache2-mod-security2 \
        libapache2-mod-evasive \
        fail2ban \
        >> "${LOG_FILE}" 2>&1

    # Install PHP dengan berbagai versi
    info "Menambahkan PHP repository (ondrej/php)..."
    apt-get install -y software-properties-common >> "${LOG_FILE}" 2>&1
    add-apt-repository -y ppa:ondrej/php >> "${LOG_FILE}" 2>&1
    apt-get update -qq >> "${LOG_FILE}" 2>&1

    info "Menginstall PHP versi multiple..."
    for ver in "${PHP_VERSIONS[@]}"; do
        info "  → Installing PHP ${ver}..."
        apt-get install -y \
            "php${ver}" \
            "php${ver}-fpm" \
            "php${ver}-cli" \
            "php${ver}-common" \
            "php${ver}-mysql" \
            "php${ver}-pgsql" \
            "php${ver}-sqlite3" \
            "php${ver}-curl" \
            "php${ver}-gd" \
            "php${ver}-mbstring" \
            "php${ver}-xml" \
            "php${ver}-zip" \
            "php${ver}-bcmath" \
            "php${ver}-intl" \
            "php${ver}-json" \
            "php${ver}-opcache" \
            "php${ver}-redis" \
            "php${ver}-memcached" \
            "php${ver}-imagick" \
            >> "${LOG_FILE}" 2>&1
        success "  ✓ PHP ${ver} terinstall"
    done

    # Install Composer
    info "Menginstall Composer..."
    if ! command -v composer &>/dev/null; then
        curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer >> "${LOG_FILE}" 2>&1
        success "Composer terinstall"
    else
        warning "Composer sudah terinstall, skip..."
    fi

    # Enable Apache & start
    systemctl enable apache2 >> "${LOG_FILE}" 2>&1
    systemctl start apache2 >> "${LOG_FILE}" 2>&1

    success "Apache berhasil diinstall!"
    apache2 -v
    press_enter
}

# ─────────────────────────────────────────
# 2. TWEAKING & HARDENING APACHE
# ─────────────────────────────────────────
harden_apache() {
    header "TWEAKING & HARDENING APACHE"

    # Backup konfigurasi asli
    info "Backup konfigurasi Apache..."
    cp "${APACHE_DIR}/apache2.conf" "${APACHE_DIR}/apache2.conf.bak.$(date +%Y%m%d)" 2>/dev/null
    cp "${APACHE_DIR}/conf-available/security.conf" "${APACHE_DIR}/conf-available/security.conf.bak.$(date +%Y%m%d)" 2>/dev/null

    # ── Security Headers ──
    info "Konfigurasi Security Headers..."
    cat > "${APACHE_DIR}/conf-available/hardening.conf" << 'EOF'
# ════════════════════════════════════════
# Apache Hardening & Security Configuration
# ════════════════════════════════════════

# Hide Apache Version & OS Info
ServerTokens Prod
ServerSignature Off

# Disable TRACE & TRACK methods
TraceEnable Off

# Security Headers
<IfModule mod_headers.c>
    # Prevent Clickjacking
    Header always set X-Frame-Options "SAMEORIGIN"

    # XSS Protection
    Header always set X-XSS-Protection "1; mode=block"

    # Prevent MIME Sniffing
    Header always set X-Content-Type-Options "nosniff"

    # Referrer Policy
    Header always set Referrer-Policy "strict-origin-when-cross-origin"

    # Content Security Policy (sesuaikan dengan kebutuhan)
    Header always set Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline';"

    # Permissions Policy
    Header always set Permissions-Policy "geolocation=(), microphone=(), camera=()"

    # Remove X-Powered-By
    Header unset X-Powered-By
    Header always unset X-Powered-By

    # HSTS (aktifkan jika sudah pakai SSL)
    # Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
</IfModule>

# Disable Directory Listing
<Directory />
    Options -Indexes -FollowSymLinks
    AllowOverride None
    Require all denied
</Directory>

<Directory /var/www/>
    Options -Indexes +FollowSymLinks
    AllowOverride All
    Require all granted
</Directory>

# Deny access to sensitive files
<FilesMatch "(^\.htaccess|^\.htpasswd|^\.git|^\.env|\.bak$|\.backup$|\.sql$|\.db$)">
    Require all denied
</FilesMatch>

# Disable ETags (mencegah inode info exposure)
FileETag None

# Limit Request Size (10MB default)
LimitRequestBody 10485760

# Timeout settings
Timeout 60
KeepAlive On
MaxKeepAliveRequests 100
KeepAliveTimeout 5

# Disable unused HTTP methods
<LimitExcept GET POST PUT DELETE PATCH OPTIONS HEAD>
    Require all denied
</LimitExcept>

EOF

    # ── Performance Tuning ──
    info "Konfigurasi Performance Tuning..."
    cat > "${APACHE_DIR}/conf-available/performance.conf" << 'EOF'
# ════════════════════════════════════════
# Apache Performance Tuning
# ════════════════════════════════════════

# MPM Event Configuration
<IfModule mpm_event_module>
    StartServers            2
    MinSpareThreads         25
    MaxSpareThreads         75
    ThreadLimit             64
    ThreadsPerChild         25
    MaxRequestWorkers       150
    MaxConnectionsPerChild  1000
</IfModule>

# MPM Prefork (untuk mod_php)
<IfModule mpm_prefork_module>
    StartServers            5
    MinSpareServers         5
    MaxSpareServers         10
    MaxRequestWorkers       150
    MaxConnectionsPerChild  10000
</IfModule>

# Gzip Compression
<IfModule mod_deflate.c>
    AddOutputFilterByType DEFLATE text/plain
    AddOutputFilterByType DEFLATE text/html
    AddOutputFilterByType DEFLATE text/xml
    AddOutputFilterByType DEFLATE text/css
    AddOutputFilterByType DEFLATE text/javascript
    AddOutputFilterByType DEFLATE application/xml
    AddOutputFilterByType DEFLATE application/xhtml+xml
    AddOutputFilterByType DEFLATE application/rss+xml
    AddOutputFilterByType DEFLATE application/javascript
    AddOutputFilterByType DEFLATE application/x-javascript
    AddOutputFilterByType DEFLATE application/json
    AddOutputFilterByType DEFLATE application/ld+json
    AddOutputFilterByType DEFLATE image/svg+xml
    DeflateCompressionLevel 6
</IfModule>

# Browser Caching
<IfModule mod_expires.c>
    ExpiresActive On
    ExpiresDefault                          "access plus 1 month"
    ExpiresByType text/html                 "access plus 1 hour"
    ExpiresByType text/css                  "access plus 1 month"
    ExpiresByType text/javascript           "access plus 1 month"
    ExpiresByType application/javascript    "access plus 1 month"
    ExpiresByType image/png                 "access plus 6 months"
    ExpiresByType image/jpg                 "access plus 6 months"
    ExpiresByType image/jpeg                "access plus 6 months"
    ExpiresByType image/gif                 "access plus 6 months"
    ExpiresByType image/svg+xml             "access plus 6 months"
    ExpiresByType image/webp                "access plus 6 months"
    ExpiresByType font/woff                 "access plus 1 year"
    ExpiresByType font/woff2                "access plus 1 year"
    ExpiresByType application/font-woff     "access plus 1 year"
    ExpiresByType application/font-woff2    "access plus 1 year"
</IfModule>

EOF

    # ── ModSecurity ──
    info "Konfigurasi ModSecurity (WAF)..."
    if [[ -f /etc/modsecurity/modsecurity.conf-recommended ]]; then
        cp /etc/modsecurity/modsecurity.conf-recommended /etc/modsecurity/modsecurity.conf
        sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' /etc/modsecurity/modsecurity.conf
        sed -i 's/SecRequestBodyLimit 13107200/SecRequestBodyLimit 52428800/' /etc/modsecurity/modsecurity.conf

        # Download OWASP Core Rule Set
        if confirm "Install OWASP ModSecurity Core Rule Set (CRS)?"; then
            cd /etc/modsecurity/ || exit
            wget -q https://github.com/coreruleset/coreruleset/archive/v3.3.5.tar.gz -O crs.tar.gz
            tar -xzf crs.tar.gz
            mv coreruleset-3.3.5 crs
            cp crs/crs-setup.conf.example crs/crs-setup.conf

            cat > /etc/apache2/conf-available/modsecurity-crs.conf << 'MODSEC'
<IfModule security2_module>
    SecDataDir /tmp/modsecurity
    Include /etc/modsecurity/modsecurity.conf
    Include /etc/modsecurity/crs/crs-setup.conf
    Include /etc/modsecurity/crs/rules/*.conf
</IfModule>
MODSEC
            mkdir -p /tmp/modsecurity
            a2enconf modsecurity-crs >> "${LOG_FILE}" 2>&1
            success "OWASP CRS terinstall"
        fi
    fi

    # ── Mod Evasive (DDoS Protection) ──
    info "Konfigurasi mod_evasive..."
    cat > /etc/apache2/conf-available/mod-evasive.conf << 'EOF'
<IfModule mod_evasive20.c>
    DOSHashTableSize    3097
    DOSPageCount        5
    DOSSiteCount        50
    DOSPageInterval     1
    DOSSiteInterval     1
    DOSBlockingPeriod   600
    DOSLogDir           /var/log/mod_evasive
    DOSEmailNotify      admin@localhost
    DOSWhitelist        127.0.0.1
</IfModule>
EOF
    mkdir -p /var/log/mod_evasive
    chmod 777 /var/log/mod_evasive

    # ── Fail2Ban Apache Rules ──
    info "Konfigurasi Fail2Ban untuk Apache..."
    cat > /etc/fail2ban/jail.d/apache.conf << 'EOF'
[apache-auth]
enabled  = true
port     = http,https
logpath  = /var/log/apache2/error.log
maxretry = 5
bantime  = 3600

[apache-badbots]
enabled  = true
port     = http,https
logpath  = /var/log/apache2/access.log
maxretry = 2
bantime  = 86400

[apache-noscript]
enabled  = true
port     = http,https
logpath  = /var/log/apache2/error.log
maxretry = 6
bantime  = 3600

[apache-overflows]
enabled  = true
port     = http,https
logpath  = /var/log/apache2/error.log
maxretry = 2
bantime  = 3600

[apache-modsecurity]
enabled  = true
port     = http,https
logpath  = /var/log/apache2/error.log
maxretry = 2
bantime  = 86400
EOF

    # Enable modules yang diperlukan
    info "Enabling required Apache modules..."
    MODULES=(
        "rewrite" "headers" "ssl" "http2"
        "expires" "deflate" "proxy" "proxy_http"
        "proxy_fcgi" "proxy_wstunnel" "proxy_balancer"
        "lbmethod_byrequests" "setenvif" "mime"
        "dir" "autoindex" "env" "filter"
        "evasive" "security2"
    )
    for mod in "${MODULES[@]}"; do
        a2enmod "$mod" >> "${LOG_FILE}" 2>&1
        info "  ✓ mod_${mod} enabled"
    done

    # Enable konfigurasi
    a2enconf hardening >> "${LOG_FILE}" 2>&1
    a2enconf performance >> "${LOG_FILE}" 2>&1

    # Restart services
    systemctl restart fail2ban >> "${LOG_FILE}" 2>&1
    systemctl restart apache2 >> "${LOG_FILE}" 2>&1

    success "Hardening Apache selesai!"
    press_enter
}

# ─────────────────────────────────────────
# 3. SETTING VIRTUAL HOST
# ─────────────────────────────────────────
create_vhost() {
    header "SETTING VIRTUAL HOST"

    echo -e "${CYAN}Pilih tipe Virtual Host:${NC}"
    echo -e "  ${WHITE}1.${NC} Laravel / Symfony / Yii (PHP Framework)"
    echo -e "  ${WHITE}2.${NC} CodeIgniter (PHP Framework)"
    echo -e "  ${WHITE}3.${NC} WordPress"
    echo -e "  ${WHITE}4.${NC} Joomla"
    echo -e "  ${WHITE}5.${NC} Static Website"
    echo -e "  ${WHITE}6.${NC} Reverse Proxy (Node.js/Python/Go/etc)"
    echo -e "  ${WHITE}7.${NC} PHP-FPM Generic"
    echo -e "  ${WHITE}8.${NC} Kembali ke Menu Utama"
    echo ""
    read -rp "Pilihan: " vhost_type

    case $vhost_type in
        1) create_vhost_laravel ;;
        2) create_vhost_ci ;;
        3) create_vhost_wordpress ;;
        4) create_vhost_joomla ;;
        5) create_vhost_static ;;
        6) create_vhost_proxy ;;
        7) create_vhost_phpfpm ;;
        8) return ;;
        *) error "Pilihan tidak valid!"; create_vhost ;;
    esac
}

# ── Input Vhost Common ──
input_vhost_common() {
    echo ""
    read -rp "  Domain (contoh: example.com): " DOMAIN
    read -rp "  Server Alias (contoh: www.example.com, kosong=skip): " SERVER_ALIAS
    read -rp "  Webroot path [/var/www/${DOMAIN}]: " WEBROOT_PATH
    WEBROOT_PATH="${WEBROOT_PATH:-/var/www/${DOMAIN}}"
    read -rp "  Admin Email [admin@${DOMAIN}]: " ADMIN_EMAIL
    ADMIN_EMAIL="${ADMIN_EMAIL:-admin@${DOMAIN}}"

    confirm "Aktifkan SSL (Let's Encrypt)?" && USE_SSL=true || USE_SSL=false
    confirm "Aktifkan HTTP/2?" && USE_HTTP2=true || USE_HTTP2=false
    confirm "Aktifkan logging?" && USE_LOG=true || USE_LOG=false
}

# ── Create Directory & Permissions ──
setup_webroot() {
    local path="$1"
    local user="${2:-www-data}"
    mkdir -p "$path"
    chown -R "${user}:www-data" "$path"
    chmod -R 755 "$path"
    success "Webroot dibuat: ${path}"
}

# ── SSL Setup ──
setup_ssl() {
    local domain="$1"
    if [[ "$USE_SSL" == true ]]; then
        info "Setup SSL untuk ${domain}..."
        if ! command -v certbot &>/dev/null; then
            apt-get install -y certbot python3-certbot-apache >> "${LOG_FILE}" 2>&1
        fi
        certbot --apache -d "$domain" --non-interactive --agree-tos -m "$ADMIN_EMAIL" 2>/dev/null || \
            warning "Certbot gagal, pastikan domain sudah pointing ke server ini"
    fi
}

# ── VHost: Laravel/Symfony/Yii ──
create_vhost_laravel() {
    header "VHOST: Laravel / Symfony / Yii"
    input_vhost_common

    echo ""
    read -rp "  PHP Version [8.2]: " PHP_VER
    PHP_VER="${PHP_VER:-8.2}"
    read -rp "  Public directory [public]: " PUB_DIR
    PUB_DIR="${PUB_DIR:-public}"

    local DOCUMENT_ROOT="${WEBROOT_PATH}/${PUB_DIR}"
    setup_webroot "$DOCUMENT_ROOT"

    cat > "${VHOST_DIR}/${DOMAIN}.conf" << EOF
# ════════════════════════════════════════
# VHost: ${DOMAIN} (Laravel/Symfony/Yii)
# PHP: ${PHP_VER} | Created: $(date)
# ════════════════════════════════════════

<VirtualHost *:80>
    ServerName ${DOMAIN}
$([ -n "$SERVER_ALIAS" ] && echo "    ServerAlias ${SERVER_ALIAS}")
    ServerAdmin ${ADMIN_EMAIL}
    DocumentRoot ${DOCUMENT_ROOT}

    # PHP-FPM via Unix Socket
    <FilesMatch \.php$>
        SetHandler "proxy:unix:/run/php/php${PHP_VER}-fpm.sock|fcgi://localhost"
    </FilesMatch>

    <Directory ${DOCUMENT_ROOT}>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted

        # Laravel/Symfony Front Controller
        <IfModule mod_rewrite.c>
            RewriteEngine On
            RewriteCond %{REQUEST_FILENAME} !-d
            RewriteCond %{REQUEST_FILENAME} !-f
            RewriteRule ^ index.php [L]
        </IfModule>
    </Directory>

    # Deny access to sensitive Laravel files
    <FilesMatch "(\.env|\.env\..*|artisan|composer\.(json|lock))$">
        Require all denied
    </FilesMatch>

    # Block access to dot files
    <DirectoryMatch "/(\.git|\.svn|\.hg)">
        Require all denied
    </DirectoryMatch>

    # PHP-FPM Status (restricted)
    <Location /php-status>
        SetHandler "proxy:unix:/run/php/php${PHP_VER}-fpm.sock|fcgi://localhost"
        Require ip 127.0.0.1
    </Location>

$(if [[ "$USE_LOG" == true ]]; then
echo "    ErrorLog \${APACHE_LOG_DIR}/${DOMAIN}-error.log"
echo "    CustomLog \${APACHE_LOG_DIR}/${DOMAIN}-access.log combined"
fi)

$(if [[ "$USE_HTTP2" == true ]]; then
echo "    Protocols h2 h2c http/1.1"
fi)

$(if [[ "$USE_SSL" == true ]]; then
echo "    # Redirect HTTP to HTTPS"
echo "    RewriteEngine On"
echo "    RewriteCond %{HTTPS} off"
echo "    RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]"
fi)
</VirtualHost>

$(if [[ "$USE_SSL" == true ]]; then
cat << SSLBLOCK
<VirtualHost *:443>
    ServerName ${DOMAIN}
$([ -n "$SERVER_ALIAS" ] && echo "    ServerAlias ${SERVER_ALIAS}")
    ServerAdmin ${ADMIN_EMAIL}
    DocumentRoot ${DOCUMENT_ROOT}

    SSLEngine On
    SSLCertificateFile /etc/letsencrypt/live/${DOMAIN}/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/${DOMAIN}/privkey.pem
    SSLProtocol all -SSLv2 -SSLv3 -TLSv1 -TLSv1.1
    SSLCipherSuite ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384
    SSLHonorCipherOrder off
    SSLSessionTickets off

$([ "$USE_HTTP2" == true ] && echo "    Protocols h2 http/1.1")

    <FilesMatch \.php$>
        SetHandler "proxy:unix:/run/php/php${PHP_VER}-fpm.sock|fcgi://localhost"
    </FilesMatch>

    <Directory ${DOCUMENT_ROOT}>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
        <IfModule mod_rewrite.c>
            RewriteEngine On
            RewriteCond %{REQUEST_FILENAME} !-d
            RewriteCond %{REQUEST_FILENAME} !-f
            RewriteRule ^ index.php [L]
        </IfModule>
    </Directory>

    <FilesMatch "(\.env|\.env\..*|artisan|composer\.(json|lock))$">
        Require all denied
    </FilesMatch>

$(if [[ "$USE_LOG" == true ]]; then
echo "    ErrorLog \${APACHE_LOG_DIR}/${DOMAIN}-ssl-error.log"
echo "    CustomLog \${APACHE_LOG_DIR}/${DOMAIN}-ssl-access.log combined"
fi)
</VirtualHost>
SSLBLOCK
fi)
EOF

    a2ensite "${DOMAIN}.conf" >> "${LOG_FILE}" 2>&1
    systemctl reload apache2 >> "${LOG_FILE}" 2>&1

    # Setup PHP-FPM pool
    setup_phpfpm_pool "$DOMAIN" "$PHP_VER" "www-data"

    success "VHost Laravel/Symfony/Yii untuk ${DOMAIN} berhasil dibuat!"
    echo -e "${CYAN}File config: ${VHOST_DIR}/${DOMAIN}.conf${NC}"
    echo -e "${CYAN}Webroot    : ${DOCUMENT_ROOT}${NC}"
    press_enter
}

# ── VHost: CodeIgniter ──
create_vhost_ci() {
    header "VHOST: CodeIgniter"
    input_vhost_common

    read -rp "  PHP Version [8.1]: " PHP_VER
    PHP_VER="${PHP_VER:-8.1}"

    setup_webroot "$WEBROOT_PATH"

    cat > "${VHOST_DIR}/${DOMAIN}.conf" << EOF
# VHost: ${DOMAIN} (CodeIgniter) | PHP: ${PHP_VER}

<VirtualHost *:80>
    ServerName ${DOMAIN}
$([ -n "$SERVER_ALIAS" ] && echo "    ServerAlias ${SERVER_ALIAS}")
    ServerAdmin ${ADMIN_EMAIL}
    DocumentRoot ${WEBROOT_PATH}

    <FilesMatch \.php$>
        SetHandler "proxy:unix:/run/php/php${PHP_VER}-fpm.sock|fcgi://localhost"
    </FilesMatch>

    <Directory ${WEBROOT_PATH}>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted

        # CodeIgniter Rewrite
        <IfModule mod_rewrite.c>
            RewriteEngine On
            RewriteBase /
            RewriteCond %{REQUEST_FILENAME} !-f
            RewriteCond %{REQUEST_FILENAME} !-d
            RewriteRule ^(.*)$ index.php/\$1 [L]
        </IfModule>
    </Directory>

    # Protect CI system folder
    <DirectoryMatch "/(system|application)">
        Require all denied
    </DirectoryMatch>

$([ "$USE_LOG" == true ] && echo "    ErrorLog \${APACHE_LOG_DIR}/${DOMAIN}-error.log" && echo "    CustomLog \${APACHE_LOG_DIR}/${DOMAIN}-access.log combined")
$([ "$USE_HTTP2" == true ] && echo "    Protocols h2 h2c http/1.1")
</VirtualHost>
EOF

    a2ensite "${DOMAIN}.conf" >> "${LOG_FILE}" 2>&1
    setup_phpfpm_pool "$DOMAIN" "$PHP_VER" "www-data"
    systemctl reload apache2 >> "${LOG_FILE}" 2>&1

    success "VHost CodeIgniter untuk ${DOMAIN} berhasil dibuat!"
    press_enter
}

# ── VHost: WordPress ──
create_vhost_wordpress() {
    header "VHOST: WordPress"
    input_vhost_common

    read -rp "  PHP Version [8.2]: " PHP_VER
    PHP_VER="${PHP_VER:-8.2}"

    setup_webroot "$WEBROOT_PATH"

    # Download WordPress jika diperlukan
    if confirm "Download WordPress ke ${WEBROOT_PATH}?"; then
        info "Downloading WordPress..."
        wget -q https://wordpress.org/latest.tar.gz -O /tmp/wordpress.tar.gz
        tar -xzf /tmp/wordpress.tar.gz -C /tmp/
        cp -r /tmp/wordpress/* "$WEBROOT_PATH/"
        chown -R www-data:www-data "$WEBROOT_PATH"
        rm -f /tmp/wordpress.tar.gz
        success "WordPress berhasil didownload"
    fi

    cat > "${VHOST_DIR}/${DOMAIN}.conf" << EOF
# VHost: ${DOMAIN} (WordPress) | PHP: ${PHP_VER}

<VirtualHost *:80>
    ServerName ${DOMAIN}
$([ -n "$SERVER_ALIAS" ] && echo "    ServerAlias ${SERVER_ALIAS}")
    ServerAdmin ${ADMIN_EMAIL}
    DocumentRoot ${WEBROOT_PATH}

    <FilesMatch \.php$>
        SetHandler "proxy:unix:/run/php/php${PHP_VER}-fpm.sock|fcgi://localhost"
    </FilesMatch>

    <Directory ${WEBROOT_PATH}>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted

        # WordPress Permalink
        <IfModule mod_rewrite.c>
            RewriteEngine On
            RewriteBase /
            RewriteRule ^index\.php$ - [L]
            RewriteCond %{REQUEST_FILENAME} !-f
            RewriteCond %{REQUEST_FILENAME} !-d
            RewriteRule . /index.php [L]
        </IfModule>
    </Directory>

    # WordPress Security
    # Block WordPress config
    <Files wp-config.php>
        Require all denied
    </Files>

    # Block xmlrpc (jika tidak dibutuhkan)
    # <Files xmlrpc.php>
    #     Require all denied
    # </Files>

    # Block wp-includes dari akses langsung
    <IfModule mod_rewrite.c>
        RewriteEngine On
        RewriteBase /
        RewriteRule ^wp-admin/includes/ - [F,L]
        RewriteRule !^wp-includes/ - [S=3]
        RewriteRule ^wp-includes/[^/]+\.php$ - [F,L]
        RewriteRule ^wp-includes/js/tinymce/langs/.+\.php - [F,L]
        RewriteRule ^wp-includes/theme-compat/ - [F,L]
    </IfModule>

    # PHP Settings untuk WordPress
    <IfModule mod_php.c>
        php_value upload_max_filesize 64M
        php_value post_max_size 64M
        php_value max_execution_time 300
        php_value max_input_vars 3000
    </IfModule>

$([ "$USE_LOG" == true ] && echo "    ErrorLog \${APACHE_LOG_DIR}/${DOMAIN}-error.log" && echo "    CustomLog \${APACHE_LOG_DIR}/${DOMAIN}-access.log combined")
$([ "$USE_HTTP2" == true ] && echo "    Protocols h2 h2c http/1.1")
</VirtualHost>
EOF

    a2ensite "${DOMAIN}.conf" >> "${LOG_FILE}" 2>&1
    setup_phpfpm_pool "$DOMAIN" "$PHP_VER" "www-data"
    systemctl reload apache2 >> "${LOG_FILE}" 2>&1

    success "VHost WordPress untuk ${DOMAIN} berhasil dibuat!"
    press_enter
}

# ── VHost: Joomla ──
create_vhost_joomla() {
    header "VHOST: Joomla"
    input_vhost_common

    read -rp "  PHP Version [8.1]: " PHP_VER
    PHP_VER="${PHP_VER:-8.1}"

    setup_webroot "$WEBROOT_PATH"

    if confirm "Download Joomla ke ${WEBROOT_PATH}?"; then
        info "Downloading Joomla..."
        JOOMLA_VER="5.1.2"
        wget -q "https://downloads.joomla.org/cms/joomla5/${JOOMLA_VER}/Joomla_${JOOMLA_VER}-Stable-Full_Package.tar.gz" \
            -O /tmp/joomla.tar.gz 2>/dev/null || \
        wget -q "https://github.com/joomla/joomla-cms/releases/download/${JOOMLA_VER}/Joomla_${JOOMLA_VER}-Stable-Full_Package.tar.bz2" \
            -O /tmp/joomla.tar.bz2
        tar -xzf /tmp/joomla.tar.gz -C "$WEBROOT_PATH/" 2>/dev/null || \
        tar -xjf /tmp/joomla.tar.bz2 -C "$WEBROOT_PATH/" 2>/dev/null
        chown -R www-data:www-data "$WEBROOT_PATH"
        success "Joomla berhasil didownload"
    fi

    cat > "${VHOST_DIR}/${DOMAIN}.conf" << EOF
# VHost: ${DOMAIN} (Joomla) | PHP: ${PHP_VER}

<VirtualHost *:80>
    ServerName ${DOMAIN}
$([ -n "$SERVER_ALIAS" ] && echo "    ServerAlias ${SERVER_ALIAS}")
    ServerAdmin ${ADMIN_EMAIL}
    DocumentRoot ${WEBROOT_PATH}

    <FilesMatch \.php$>
        SetHandler "proxy:unix:/run/php/php${PHP_VER}-fpm.sock|fcgi://localhost"
    </FilesMatch>

    <Directory ${WEBROOT_PATH}>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
        <IfModule mod_rewrite.c>
            RewriteEngine On
            RewriteBase /
            RewriteCond %{REQUEST_FILENAME} !-f
            RewriteCond %{REQUEST_FILENAME} !-d
            RewriteRule ^(.*)$ index.php [L]
        </IfModule>
    </Directory>

    # Protect Joomla config
    <Files configuration.php>
        Require all denied
    </Files>

    <FilesMatch "\.(bak|config|sql|fla|psd|ini|log|sh|inc|swp|dist)$">
        Require all denied
    </FilesMatch>

$([ "$USE_LOG" == true ] && echo "    ErrorLog \${APACHE_LOG_DIR}/${DOMAIN}-error.log" && echo "    CustomLog \${APACHE_LOG_DIR}/${DOMAIN}-access.log combined")
</VirtualHost>
EOF

    a2ensite "${DOMAIN}.conf" >> "${LOG_FILE}" 2>&1
    setup_phpfpm_pool "$DOMAIN" "$PHP_VER" "www-data"
    systemctl reload apache2 >> "${LOG_FILE}" 2>&1

    success "VHost Joomla untuk ${DOMAIN} berhasil dibuat!"
    press_enter
}

# ── VHost: Static ──
create_vhost_static() {
    header "VHOST: Static Website"
    input_vhost_common

    setup_webroot "$WEBROOT_PATH"

    # Buat index.html contoh
    cat > "${WEBROOT_PATH}/index.html" << EOF
<!DOCTYPE html>
<html><head><title>Welcome to ${DOMAIN}</title></head>
<body><h1>${DOMAIN} is working!</h1></body></html>
EOF

    cat > "${VHOST_DIR}/${DOMAIN}.conf" << EOF
# VHost: ${DOMAIN} (Static)

<VirtualHost *:80>
    ServerName ${DOMAIN}
$([ -n "$SERVER_ALIAS" ] && echo "    ServerAlias ${SERVER_ALIAS}")
    ServerAdmin ${ADMIN_EMAIL}
    DocumentRoot ${WEBROOT_PATH}

    <Directory ${WEBROOT_PATH}>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

$([ "$USE_LOG" == true ] && echo "    ErrorLog \${APACHE_LOG_DIR}/${DOMAIN}-error.log" && echo "    CustomLog \${APACHE_LOG_DIR}/${DOMAIN}-access.log combined")
$([ "$USE_HTTP2" == true ] && echo "    Protocols h2 h2c http/1.1")
</VirtualHost>
EOF

    a2ensite "${DOMAIN}.conf" >> "${LOG_FILE}" 2>&1
    systemctl reload apache2 >> "${LOG_FILE}" 2>&1

    success "VHost Static untuk ${DOMAIN} berhasil dibuat!"
    press_enter
}

# ── VHost: Reverse Proxy ──
create_vhost_proxy() {
    header "VHOST: Reverse Proxy"
    input_vhost_common

    echo ""
    echo -e "${CYAN}Pilih tipe backend:${NC}"
    echo "  1. Node.js"
    echo "  2. Python (Flask/Django/FastAPI)"
    echo "  3. Go"
    echo "  4. Custom Port"
    echo "  5. WebSocket Support"
    read -rp "Pilihan: " proxy_type

    read -rp "  Backend host [127.0.0.1]: " BACKEND_HOST
    BACKEND_HOST="${BACKEND_HOST:-127.0.0.1}"
    read -rp "  Backend port: " BACKEND_PORT

    local BACKEND_URL="http://${BACKEND_HOST}:${BACKEND_PORT}"
    local WS_SUPPORT=""

    if [[ "$proxy_type" == "5" ]] || confirm "Tambahkan WebSocket support?"; then
        WS_SUPPORT="true"
    fi

    # Setup sebagai systemd service untuk app
    if confirm "Buat systemd service untuk aplikasi backend?"; then
        read -rp "  Nama service: " SVC_NAME
        read -rp "  User service [www-data]: " SVC_USER
        SVC_USER="${SVC_USER:-www-data}"
        read -rp "  Working directory [${WEBROOT_PATH}]: " SVC_DIR
        SVC_DIR="${SVC_DIR:-${WEBROOT_PATH}}"
        read -rp "  Command untuk menjalankan app: " SVC_CMD

        cat > "/etc/systemd/system/${SVC_NAME}.service" << EOF
[Unit]
Description=${SVC_NAME} Application
After=network.target

[Service]
Type=simple
User=${SVC_USER}
WorkingDirectory=${SVC_DIR}
ExecStart=${SVC_CMD}
Restart=on-failure
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=${SVC_NAME}
Environment=NODE_ENV=production
Environment=PORT=${BACKEND_PORT}

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload >> "${LOG_FILE}" 2>&1
        systemctl enable "${SVC_NAME}" >> "${LOG_FILE}" 2>&1
        success "Service ${SVC_NAME} dibuat dan diaktifkan"
    fi

    cat > "${VHOST_DIR}/${DOMAIN}.conf" << EOF
# VHost: ${DOMAIN} (Reverse Proxy → ${BACKEND_URL})

<VirtualHost *:80>
    ServerName ${DOMAIN}
$([ -n "$SERVER_ALIAS" ] && echo "    ServerAlias ${SERVER_ALIAS}")
    ServerAdmin ${ADMIN_EMAIL}

    # Proxy Configuration
    ProxyPreserveHost On
    ProxyRequests Off
    ProxyPass / ${BACKEND_URL}/
    ProxyPassReverse / ${BACKEND_URL}/

    # Timeout settings
    ProxyTimeout 300

$(if [[ "$WS_SUPPORT" == "true" ]]; then
cat << WSEOF
    # WebSocket Support
    RewriteEngine On
    RewriteCond %{HTTP:Upgrade} websocket [NC]
    RewriteCond %{HTTP:Connection} upgrade [NC]
    RewriteRule ^/?(.*) "ws://${BACKEND_HOST}:${BACKEND_PORT}/\$1" [P,L]

    # WebSocket Proxy
    ProxyPass /ws/ ws://${BACKEND_HOST}:${BACKEND_PORT}/ws/
    ProxyPassReverse /ws/ ws://${BACKEND_HOST}:${BACKEND_PORT}/ws/
WSEOF
fi)

    # Headers untuk proxy
    RequestHeader set X-Forwarded-Proto "http"
    RequestHeader set X-Forwarded-Host "%{HTTP_HOST}e"
    RequestHeader set X-Real-IP "%{REMOTE_ADDR}s"

    # Rate Limiting (opsional)
    # <IfModule mod_ratelimit.c>
    #     SetOutputFilter RATE_LIMIT
    #     SetEnv rate-limit 400
    # </IfModule>

$([ "$USE_LOG" == true ] && echo "    ErrorLog \${APACHE_LOG_DIR}/${DOMAIN}-error.log" && echo "    CustomLog \${APACHE_LOG_DIR}/${DOMAIN}-access.log combined")
$([ "$USE_HTTP2" == true ] && echo "    Protocols h2 h2c http/1.1")
</VirtualHost>

$(if [[ "$USE_SSL" == true ]]; then
cat << SSLEOF
<VirtualHost *:443>
    ServerName ${DOMAIN}
$([ -n "$SERVER_ALIAS" ] && echo "    ServerAlias ${SERVER_ALIAS}")
    ServerAdmin ${ADMIN_EMAIL}

    SSLEngine On
    SSLCertificateFile /etc/letsencrypt/live/${DOMAIN}/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/${DOMAIN}/privkey.pem
    SSLProtocol all -SSLv2 -SSLv3 -TLSv1 -TLSv1.1
    SSLCipherSuite ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384

$([ "$USE_HTTP2" == true ] && echo "    Protocols h2 http/1.1")

    ProxyPreserveHost On
    ProxyRequests Off
    ProxyPass / ${BACKEND_URL}/
    ProxyPassReverse / ${BACKEND_URL}/

    RequestHeader set X-Forwarded-Proto "https"
    RequestHeader set X-Forwarded-Host "%{HTTP_HOST}e"
    RequestHeader set X-Real-IP "%{REMOTE_ADDR}s"

$(if [[ "$WS_SUPPORT" == "true" ]]; then
echo "    RewriteEngine On"
echo "    RewriteCond %{HTTP:Upgrade} websocket [NC]"
echo "    RewriteCond %{HTTP:Connection} upgrade [NC]"
echo "    RewriteRule ^/?(.*) \"wss://${BACKEND_HOST}:${BACKEND_PORT}/\$1\" [P,L]"
fi)

$([ "$USE_LOG" == true ] && echo "    ErrorLog \${APACHE_LOG_DIR}/${DOMAIN}-ssl-error.log" && echo "    CustomLog \${APACHE_LOG_DIR}/${DOMAIN}-ssl-access.log combined")
</VirtualHost>
SSLEOF
fi)
EOF

    a2ensite "${DOMAIN}.conf" >> "${LOG_FILE}" 2>&1
    systemctl reload apache2 >> "${LOG_FILE}" 2>&1

    success "VHost Reverse Proxy untuk ${DOMAIN} berhasil dibuat!"
    echo -e "${CYAN}Backend : ${BACKEND_URL}${NC}"
    press_enter
}

# ── VHost: PHP-FPM Generic ──
create_vhost_phpfpm() {
    header "VHOST: PHP-FPM Generic"
    input_vhost_common

    read -rp "  PHP Version [8.2]: " PHP_VER
    PHP_VER="${PHP_VER:-8.2}"

    setup_webroot "$WEBROOT_PATH"

    cat > "${VHOST_DIR}/${DOMAIN}.conf" << EOF
# VHost: ${DOMAIN} (PHP-FPM) | PHP: ${PHP_VER}

<VirtualHost *:80>
    ServerName ${DOMAIN}
$([ -n "$SERVER_ALIAS" ] && echo "    ServerAlias ${SERVER_ALIAS}")
    ServerAdmin ${ADMIN_EMAIL}
    DocumentRoot ${WEBROOT_PATH}

    <FilesMatch \.php$>
        SetHandler "proxy:unix:/run/php/php${PHP_VER}-fpm.sock|fcgi://localhost"
    </FilesMatch>

    <Directory ${WEBROOT_PATH}>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

$([ "$USE_LOG" == true ] && echo "    ErrorLog \${APACHE_LOG_DIR}/${DOMAIN}-error.log" && echo "    CustomLog \${APACHE_LOG_DIR}/${DOMAIN}-access.log combined")
$([ "$USE_HTTP2" == true ] && echo "    Protocols h2 h2c http/1.1")
</VirtualHost>
EOF

    a2ensite "${DOMAIN}.conf" >> "${LOG_FILE}" 2>&1
    setup_phpfpm_pool "$DOMAIN" "$PHP_VER" "www-data"
    systemctl reload apache2 >> "${LOG_FILE}" 2>&1

    success "VHost PHP-FPM untuk ${DOMAIN} berhasil dibuat!"
    press_enter
}

# ── Setup PHP-FPM Pool ──
setup_phpfpm_pool() {
    local domain="$1"
    local php_ver="$2"
    local user="${3:-www-data}"
    local pool_name="${domain//./_}"

    cat > "/etc/php/${php_ver}/fpm/pool.d/${pool_name}.conf" << EOF
; PHP-FPM Pool: ${domain}
[${pool_name}]
user = ${user}
group = www-data
listen = /run/php/php${php_ver}-fpm-${pool_name}.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660

pm = dynamic
pm.max_children = 10
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
pm.max_requests = 500

; Logging
php_flag[display_errors] = off
php_admin_value[error_log] = /var/log/php/${domain}-fpm-error.log
php_admin_flag[log_errors] = on

; Security
php_admin_value[disable_functions] = exec,passthru,shell_exec,system,proc_open,popen
php_admin_value[open_basedir] = ${WEBROOT_PATH}:/tmp

; Performance
php_admin_value[memory_limit] = 256M
php_value[session.save_handler] = files
php_value[session.save_path] = /tmp/session_${pool_name}
EOF

    mkdir -p "/tmp/session_${pool_name}" "/var/log/php"
    chown -R "$user:www-data" "/tmp/session_${pool_name}"

    # Update vhost untuk menggunakan socket pool baru
    sed -i "s|php${php_ver}-fpm.sock|php${php_ver}-fpm-${pool_name}.sock|g" \
        "${VHOST_DIR}/${domain}.conf" 2>/dev/null

    systemctl restart "php${php_ver}-fpm" >> "${LOG_FILE}" 2>&1
}

# ─────────────────────────────────────────
# 5. FITUR SWITCH PHP
# ─────────────────────────────────────────
switch_php() {
    header "SWITCH PHP VERSION"

    echo -e "${CYAN}PHP Versions yang terinstall:${NC}"
    for ver in "${PHP_VERSIONS[@]}"; do
        if command -v "php${ver}" &>/dev/null; then
            local status="${GREEN}✓ Installed${NC}"
        else
            local status="${RED}✗ Not Installed${NC}"
        fi
        echo -e "  PHP ${ver}: ${status}"
    done

    echo ""
    echo -e "${CYAN}Pilih aksi:${NC}"
    echo "  1. Switch PHP CLI Global"
    echo "  2. Switch PHP untuk VHost"
    echo "  3. Install PHP Version"
    echo "  4. Konfigurasi PHP-FPM Pool"
    echo "  5. Lihat PHP info"
    echo "  6. Kembali"
    read -rp "Pilihan: " php_action

    case $php_action in
        1) switch_php_cli ;;
        2) switch_php_vhost ;;
        3) install_php_version ;;
        4) configure_phpfpm ;;
        5) show_php_info ;;
        6) return ;;
        *) error "Pilihan tidak valid!"; switch_php ;;
    esac
}

switch_php_cli() {
    header "SWITCH PHP CLI"

    echo -e "${CYAN}Pilih PHP version untuk CLI:${NC}"
    select VER in "${PHP_VERSIONS[@]}" "Kembali"; do
        if [[ "$VER" == "Kembali" ]]; then
            return
        fi

        if command -v "php${VER}" &>/dev/null; then
            update-alternatives --set php "/usr/bin/php${VER}" >> "${LOG_FILE}" 2>&1

            # Update alternatives untuk tools lain
            for tool in php php-config phpize; do
                update-alternatives --set "$tool" "/usr/bin/${tool}${VER}" 2>/dev/null >> "${LOG_FILE}" 2>&1
            done

            success "PHP CLI berhasil di-switch ke versi ${VER}"
            echo -e "${CYAN}Verifikasi: $(php -v | head -1)${NC}"
        else
            error "PHP ${VER} belum terinstall!"
            if confirm "Install PHP ${VER} sekarang?"; then
                install_php_single_version "$VER"
            fi
        fi
        break
    done
    press_enter
}

switch_php_vhost() {
    header "SWITCH PHP UNTUK VHOST"

    echo -e "${CYAN}VHost yang tersedia:${NC}"
    local sites=()
    for f in "${VHOST_DIR}"/*.conf; do
        local site
        site=$(basename "$f" .conf)
        [[ "$site" != "000-default" && "$site" != "default-ssl" ]] && sites+=("$site")
        echo "  - $site"
    done

    read -rp "Masukkan nama domain vhost: " TARGET_DOMAIN
    read -rp "PHP version baru: " NEW_PHP_VER

    if [[ ! -f "${VHOST_DIR}/${TARGET_DOMAIN}.conf" ]]; then
        error "VHost ${TARGET_DOMAIN} tidak ditemukan!"
        press_enter
        return
    fi

    if ! command -v "php${NEW_PHP_VER}" &>/dev/null; then
        error "PHP ${NEW_PHP_VER} belum terinstall!"
        press_enter
        return
    fi

    # Backup config lama
    cp "${VHOST_DIR}/${TARGET_DOMAIN}.conf" "${VHOST_DIR}/${TARGET_DOMAIN}.conf.bak"

    # Detect PHP version saat ini dari config
    local CURRENT_PHP
    CURRENT_PHP=$(grep -oP 'php\K[0-9]+\.[0-9]+(?=-fpm)' "${VHOST_DIR}/${TARGET_DOMAIN}.conf" | head -1)

    if [[ -n "$CURRENT_PHP" ]]; then
        sed -i "s/php${CURRENT_PHP}-fpm/php${NEW_PHP_VER}-fpm/g" "${VHOST_DIR}/${TARGET_DOMAIN}.conf"
        success "PHP di ${TARGET_DOMAIN} diganti dari ${CURRENT_PHP} ke ${NEW_PHP_VER}"
    else
        # Tambahkan handler PHP-FPM
        sed -i "/<Directory/i\\    <FilesMatch \\.php\$>\n        SetHandler \"proxy:unix:/run/php/php${NEW_PHP_VER}-fpm.sock|fcgi://localhost\"\n    </FilesMatch>\n" \
            "${VHOST_DIR}/${TARGET_DOMAIN}.conf"
        success "PHP handler ditambahkan untuk ${TARGET_DOMAIN} dengan PHP ${NEW_PHP_VER}"
    fi

    # Update pool jika ada
    local pool_name="${TARGET_DOMAIN//./_}"
    if [[ -f "/etc/php/${CURRENT_PHP}/fpm/pool.d/${pool_name}.conf" ]]; then
        cp "/etc/php/${CURRENT_PHP}/fpm/pool.d/${pool_name}.conf" \
           "/etc/php/${NEW_PHP_VER}/fpm/pool.d/${pool_name}.conf"
        sed -i "s|php${CURRENT_PHP}|php${NEW_PHP_VER}|g" \
           "/etc/php/${NEW_PHP_VER}/fpm/pool.d/${pool_name}.conf"
        rm "/etc/php/${CURRENT_PHP}/fpm/pool.d/${pool_name}.conf" 2>/dev/null

        systemctl restart "php${CURRENT_PHP}-fpm" 2>/dev/null >> "${LOG_FILE}" 2>&1
        systemctl restart "php${NEW_PHP_VER}-fpm" >> "${LOG_FILE}" 2>&1
    fi

    apache2ctl configtest >> "${LOG_FILE}" 2>&1 && systemctl reload apache2

    success "VHost ${TARGET_DOMAIN} sekarang menggunakan PHP ${NEW_PHP_VER}"
    press_enter
}

install_php_version() {
    echo -e "${CYAN}Pilih PHP version yang akan diinstall:${NC}"
    select VER in "${PHP_VERSIONS[@]}" "Custom" "Kembali"; do
        case "$VER" in
            "Kembali") return ;;
            "Custom")
                read -rp "Masukkan versi PHP: " VER
                ;;
        esac
        install_php_single_version "$VER"
        break
    done
}

install_php_single_version() {
    local ver="$1"
    info "Installing PHP ${ver}..."
    apt-get install -y \
        "php${ver}" "php${ver}-fpm" "php${ver}-cli" "php${ver}-common" \
        "php${ver}-mysql" "php${ver}-pgsql" "php${ver}-sqlite3" \
        "php${ver}-curl" "php${ver}-gd" "php${ver}-mbstring" \
        "php${ver}-xml" "php${ver}-zip" "php${ver}-bcmath" \
        "php${ver}-intl" "php${ver}-opcache" "php${ver}-redis" \
        "php${ver}-imagick" >> "${LOG_FILE}" 2>&1

    systemctl enable "php${ver}-fpm" >> "${LOG_FILE}" 2>&1
    systemctl start "php${ver}-fpm" >> "${LOG_FILE}" 2>&1

    success "PHP ${ver} berhasil diinstall!"
}

configure_phpfpm() {
    header "KONFIGURASI PHP-FPM"

    read -rp "PHP Version [8.2]: " PHP_VER
    PHP_VER="${PHP_VER:-8.2}"

    local FPM_CONF="/etc/php/${PHP_VER}/fpm/php.ini"
    if [[ ! -f "$FPM_CONF" ]]; then
        error "PHP ${PHP_VER} tidak ditemukan!"
        press_enter
        return
    fi

    echo -e "${CYAN}Konfigurasi php.ini untuk PHP ${PHP_VER}:${NC}"
    read -rp "  memory_limit [256M]: " MEM_LIMIT; MEM_LIMIT="${MEM_LIMIT:-256M}"
    read -rp "  upload_max_filesize [64M]: " UPLOAD_MAX; UPLOAD_MAX="${UPLOAD_MAX:-64M}"
    read -rp "  post_max_size [64M]: " POST_MAX; POST_MAX="${POST_MAX:-64M}"
    read -rp "  max_execution_time [300]: " EXEC_TIME; EXEC_TIME="${EXEC_TIME:-300}"
    read -rp "  max_input_vars [3000]: " INPUT_VARS; INPUT_VARS="${INPUT_VARS:-3000}"

    cp "$FPM_CONF" "${FPM_CONF}.bak.$(date +%Y%m%d)"

    sed -i "s/memory_limit = .*/memory_limit = ${MEM_LIMIT}/" "$FPM_CONF"
    sed -i "s/upload_max_filesize = .*/upload_max_filesize = ${UPLOAD_MAX}/" "$FPM_CONF"
    sed -i "s/post_max_size = .*/post_max_size = ${POST_MAX}/" "$FPM_CONF"
    sed -i "s/max_execution_time = .*/max_execution_time = ${EXEC_TIME}/" "$FPM_CONF"
    sed -i "s/;max_input_vars = .*/max_input_vars = ${INPUT_VARS}/" "$FPM_CONF"
    sed -i "s/max_input_vars = .*/max_input_vars = ${INPUT_VARS}/" "$FPM_CONF"

    # OPcache optimization
    cat >> "$FPM_CONF" << EOF

; OPcache Optimization
opcache.enable=1
opcache.enable_cli=1
opcache.memory_consumption=256
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=10000
opcache.revalidate_freq=60
opcache.fast_shutdown=1
EOF

    systemctl restart "php${PHP_VER}-fpm" >> "${LOG_FILE}" 2>&1
    success "Konfigurasi PHP ${PHP_VER} berhasil diupdate!"
    press_enter
}

show_php_info() {
    header "PHP INFO"

    echo -e "${CYAN}PHP Versions Terinstall:${NC}"
    for ver in "${PHP_VERSIONS[@]}"; do
        if command -v "php${ver}" &>/dev/null; then
            echo -e "  ${GREEN}PHP ${ver}${NC}: $(php${ver} -v 2>/dev/null | head -1)"
            # Check FPM status
            if systemctl is-active --quiet "php${ver}-fpm"; then
                echo -e "    FPM: ${GREEN}Running${NC}"
            else
                echo -e "    FPM: ${RED}Stopped${NC}"
            fi
        fi
    done

    echo ""
    echo -e "${CYAN}PHP CLI Default:${NC}"
    php -v 2>/dev/null | head -1

    press_enter
}

# ─────────────────────────────────────────
# 6. FITUR ENABLED/DISABLED MOD
# ─────────────────────────────────────────
manage_modules() {
    header "MANAGE APACHE MODULES"

    echo -e "${CYAN}Pilih aksi:${NC}"
    echo "  1. Lihat semua modul (enabled)"
    echo "  2. Lihat semua modul (available)"
    echo "  3. Enable modul"
    echo "  4. Disable modul"
    echo "  5. Enable/Disable preset"
    echo "  6. Enable conf"
    echo "  7. Disable conf"
    echo "  8. Kembali"
    read -rp "Pilihan: " mod_action

    case $mod_action in
        1) show_enabled_modules ;;
        2) show_available_modules ;;
        3) enable_module ;;
        4) disable_module ;;
        5) preset_modules ;;
        6) enable_conf ;;
        7) disable_conf ;;
        8) return ;;
        *) error "Pilihan tidak valid!"; manage_modules ;;
    esac
}

show_enabled_modules() {
    header "MODUL YANG AKTIF"
    echo -e "${GREEN}"
    apache2ctl -M 2>/dev/null | sort
    echo -e "${NC}"
    press_enter
    manage_modules
}

show_available_modules() {
    header "MODUL YANG TERSEDIA"
    echo -e "${CYAN}"
    ls /usr/lib/apache2/modules/ 2>/dev/null | sed 's/mod_//' | sed 's/\.so//'
    echo -e "${NC}"
    press_enter
    manage_modules
}

enable_module() {
    header "ENABLE MODUL"

    echo -e "${CYAN}Modul populer:${NC}"
    echo -e "  rewrite, headers, ssl, http2, deflate, expires"
    echo -e "  proxy, proxy_http, proxy_fcgi, proxy_wstunnel"
    echo -e "  security2, evasive, ratelimit, status, userdir"
    echo -e "  auth_basic, authn_file, authz_host"
    echo ""

    read -rp "Nama modul (bisa multiple, pisah spasi): " MODULES_INPUT

    for mod in $MODULES_INPUT; do
        info "Enabling mod_${mod}..."
        if a2enmod "$mod" >> "${LOG_FILE}" 2>&1; then
            success "mod_${mod} berhasil diaktifkan"
        else
            error "Gagal mengaktifkan mod_${mod}"
        fi
    done

    apache2ctl configtest >> "${LOG_FILE}" 2>&1 && systemctl reload apache2
    press_enter
    manage_modules
}

disable_module() {
    header "DISABLE MODUL"

    echo -e "${YELLOW}PERHATIAN: Beberapa modul kritis jangan di-disable!${NC}"
    echo -e "${YELLOW}Kritikal: authz_core, authn_core, dir, mime, setenvif${NC}\n"

    read -rp "Nama modul yang akan di-disable (bisa multiple, pisah spasi): " MODULES_INPUT

    # List modul kritis
    local CRITICAL_MODS=("authz_core" "authn_core" "dir" "mime" "setenvif" "alias")

    for mod in $MODULES_INPUT; do
        # Cek apakah modul kritis
        local is_critical=false
        for crit in "${CRITICAL_MODS[@]}"; do
            [[ "$mod" == "$crit" ]] && is_critical=true && break
        done

        if [[ "$is_critical" == true ]]; then
            warning "mod_${mod} adalah modul kritis, skip!"
            continue
        fi

        info "Disabling mod_${mod}..."
        if a2dismod "$mod" >> "${LOG_FILE}" 2>&1; then
            success "mod_${mod} berhasil dinonaktifkan"
        else
            error "Gagal menonaktifkan mod_${mod}"
        fi
    done

    apache2ctl configtest >> "${LOG_FILE}" 2>&1 && systemctl reload apache2
    press_enter
    manage_modules
}

preset_modules() {
    header "PRESET MODULES"

    echo -e "${CYAN}Pilih preset:${NC}"
    echo "  1. Preset: Laravel/PHP Framework (optimal)"
    echo "  2. Preset: Reverse Proxy"
    echo "  3. Preset: Security Maximum"
    echo "  4. Preset: Performance Maximum"
    echo "  5. Preset: WordPress"
    echo "  6. Kembali"
    read -rp "Pilihan: " preset

    case $preset in
        1)
            info "Menerapkan preset Laravel/PHP Framework..."
            ENABLE_MODS="rewrite headers ssl deflate expires proxy proxy_fcgi setenvif http2 env filter"
            DISABLE_MODS="autoindex status"
            ;;
        2)
            info "Menerapkan preset Reverse Proxy..."
            ENABLE_MODS="proxy proxy_http proxy_wstunnel proxy_balancer lbmethod_byrequests headers rewrite ssl http2"
            DISABLE_MODS="php8.2 autoindex"
            ;;
        3)
            info "Menerapkan preset Security Maximum..."
            ENABLE_MODS="headers rewrite ssl security2 evasive"
            DISABLE_MODS="autoindex status userdir"
            ;;
        4)
            info "Menerapkan preset Performance Maximum..."
            ENABLE_MODS="deflate expires http2 filter cache cache_disk proxy_fcgi"
            DISABLE_MODS="status autoindex"
            ;;
        5)
            info "Menerapkan preset WordPress..."
            ENABLE_MODS="rewrite headers ssl deflate expires proxy proxy_fcgi http2"
            DISABLE_MODS="autoindex"
            ;;
        6) manage_modules; return ;;
        *) error "Pilihan tidak valid!"; manage_modules; return ;;
    esac

    for mod in $ENABLE_MODS; do
        a2enmod "$mod" >> "${LOG_FILE}" 2>&1
        info "  ✓ Enabled: mod_${mod}"
    done

    for mod in $DISABLE_MODS; do
        a2dismod "$mod" >> "${LOG_FILE}" 2>&1
        info "  ✗ Disabled: mod_${mod}"
    done

    apache2ctl configtest >> "${LOG_FILE}" 2>&1 && systemctl reload apache2
    success "Preset berhasil diterapkan!"
    press_enter
    manage_modules
}

enable_conf() {
    echo ""
    echo -e "${CYAN}Conf available:${NC}"
    ls "${APACHE_DIR}/conf-available/"
    read -rp "Nama conf yang akan diaktifkan: " CONF_NAME
    a2enconf "$CONF_NAME" >> "${LOG_FILE}" 2>&1 && success "Conf ${CONF_NAME} diaktifkan" || error "Gagal!"
    systemctl reload apache2
    press_enter
    manage_modules
}

disable_conf() {
    echo ""
    echo -e "${CYAN}Conf enabled:${NC}"
    ls "${APACHE_DIR}/conf-enabled/"
    read -rp "Nama conf yang akan dinonaktifkan: " CONF_NAME
    a2disconf "$CONF_NAME" >> "${LOG_FILE}" 2>&1 && success "Conf ${CONF_NAME} dinonaktifkan" || error "Gagal!"
    systemctl reload apache2
    press_enter
    manage_modules
}

# ─────────────────────────────────────────
# TAMBAHAN: MANAGE VHOST
# ─────────────────────────────────────────
manage_vhost() {
    header "MANAGE VIRTUAL HOST"

    echo -e "${CYAN}Pilih aksi:${NC}"
    echo "  1. List semua VHost"
    echo "  2. Enable VHost"
    echo "  3. Disable VHost"
    echo "  4. Delete VHost"
    echo "  5. Lihat isi VHost config"
    echo "  6. Edit VHost config"
    echo "  7. Kembali"
    read -rp "Pilihan: " vhost_action

    case $vhost_action in
        1)
            header "LIST VHOST"
            echo -e "${GREEN}=== Sites Available ===${NC}"
            ls "${VHOST_DIR}/"
            echo -e "\n${CYAN}=== Sites Enabled ===${NC}"
            ls "${APACHE_DIR}/sites-enabled/"
            press_enter; manage_vhost
            ;;
        2)
            read -rp "Nama domain vhost: " DOMAIN
            a2ensite "${DOMAIN}.conf" && systemctl reload apache2 && success "VHost ${DOMAIN} diaktifkan"
            press_enter; manage_vhost
            ;;
        3)
            read -rp "Nama domain vhost: " DOMAIN
            a2dissite "${DOMAIN}.conf" && systemctl reload apache2 && success "VHost ${DOMAIN} dinonaktifkan"
            press_enter; manage_vhost
            ;;
        4)
            read -rp "Nama domain vhost yang akan dihapus: " DOMAIN
            if confirm "YAKIN ingin menghapus VHost ${DOMAIN}? (file config akan dihapus)"; then
                a2dissite "${DOMAIN}.conf" 2>/dev/null
                rm -f "${VHOST_DIR}/${DOMAIN}.conf"
                systemctl reload apache2
                warning "VHost ${DOMAIN} dihapus. Webroot TIDAK dihapus otomatis."
                if confirm "Hapus webroot juga?"; then
                    read -rp "Webroot path: " WR_PATH
                    rm -rf "$WR_PATH"
                    success "Webroot dihapus"
                fi
            fi
            press_enter; manage_vhost
            ;;
        5)
            echo -e "${CYAN}VHost yang tersedia:${NC}"
            ls "${VHOST_DIR}/"
            read -rp "Nama domain: " DOMAIN
            cat "${VHOST_DIR}/${DOMAIN}.conf"
            press_enter; manage_vhost
            ;;
        6)
            echo -e "${CYAN}VHost yang tersedia:${NC}"
            ls "${VHOST_DIR}/"
            read -rp "Nama domain: " DOMAIN
            ${EDITOR:-nano} "${VHOST_DIR}/${DOMAIN}.conf"
            apache2ctl configtest && systemctl reload apache2
            press_enter; manage_vhost
            ;;
        7) return ;;
        *) error "Pilihan tidak valid!"; manage_vhost ;;
    esac
}

# ─────────────────────────────────────────
# STATUS & MONITORING
# ─────────────────────────────────────────
show_status() {
    header "STATUS APACHE & SERVICES"

    echo -e "${CYAN}=== Apache Status ===${NC}"
    systemctl status apache2 --no-pager -l | head -20

    echo -e "\n${CYAN}=== PHP-FPM Status ===${NC}"
    for ver in "${PHP_VERSIONS[@]}"; do
        if systemctl is-enabled "php${ver}-fpm" &>/dev/null; then
            local fpm_status
            if systemctl is-active --quiet "php${ver}-fpm"; then
                fpm_status="${GREEN}Running${NC}"
            else
                fpm_status="${RED}Stopped${NC}"
            fi
            echo -e "  PHP ${ver}-FPM: ${fpm_status}"
        fi
    done

    echo -e "\n${CYAN}=== Fail2Ban Status ===${NC}"
    fail2ban-client status 2>/dev/null | head -10

    echo -e "\n${CYAN}=== Listening Ports ===${NC}"
    ss -tlnp | grep -E ":(80|443|8080|3000|5000|8000)" 2>/dev/null

    echo -e "\n${CYAN}=== VHost Enabled ===${NC}"
    ls "${APACHE_DIR}/sites-enabled/"

    echo -e "\n${CYAN}=== Disk Usage Webroot ===${NC}"
    du -sh "${WEBROOT}"/* 2>/dev/null

    press_enter
}

# ─────────────────────────────────────────
# MAIN MENU
# ─────────────────────────────────────────
show_banner() {
    clear
    echo -e "${BLUE}${BOLD}"
    cat << 'BANNER'
  ╔═══════════════════════════════════════════════════╗
  ║       APACHE WEB SERVER MANAGEMENT TOOL           ║
  ║       Support: PHP/Laravel/WP/Proxy/NodeJS        ║
  ╚═══════════════════════════════════════════════════╝
BANNER
    echo -e "${NC}"
    echo -e "  ${WHITE}Server:${NC} $(hostname) | ${WHITE}IP:${NC} $(hostname -I | awk '{print $1}') | ${WHITE}OS:${NC} $(lsb_release -ds 2>/dev/null)"
    echo -e "  ${WHITE}Apache:${NC} $(apache2 -v 2>/dev/null | grep version | awk '{print $3}') | ${WHITE}PHP CLI:${NC} $(php -v 2>/dev/null | head -1 | awk '{print $2}')"
    echo ""
}

main_menu() {
    show_banner

    echo -e "${CYAN}${BOLD}  MENU UTAMA:${NC}"
    echo -e "  ${WHITE}[1]${NC} Install Apache & Dependencies"
    echo -e "  ${WHITE}[2]${NC} Tweaking & Hardening Apache"
    echo -e "  ${WHITE}[3]${NC} Buat Virtual Host"
    echo -e "  ${WHITE}[4]${NC} Manage Virtual Host"
    echo -e "  ${WHITE}[5]${NC} Switch PHP Version"
    echo -e "  ${WHITE}[6]${NC} Manage Apache Modules"
    echo -e "  ${WHITE}[7]${NC} Status & Monitoring"
    echo -e "  ${WHITE}[8]${NC} Restart/Reload Apache"
    echo -e "  ${WHITE}[9]${NC} Lihat Log Apache"
    echo -e "  ${WHITE}[0]${NC} Keluar"
    echo ""
    read -rp "  Pilihan: " choice

    case $choice in
        1) install_apache ;;
        2) harden_apache ;;
        3) create_vhost ;;
        4) manage_vhost ;;
        5) switch_php ;;
        6) manage_modules ;;
        7) show_status ;;
        8)
            echo -e "${CYAN}1. Restart  2. Reload  3. Stop  4. Start${NC}"
            read -rp "Pilihan: " restart_choice
            case $restart_choice in
                1) systemctl restart apache2 && success "Apache restarted" ;;
                2) systemctl reload apache2 && success "Apache reloaded" ;;
                3) systemctl stop apache2 && success "Apache stopped" ;;
                4) systemctl start apache2 && success "Apache started" ;;
            esac
            press_enter
            ;;
        9)
            echo -e "${CYAN}1. Error Log  2. Access Log  3. Custom VHost Log${NC}"
            read -rp "Pilihan: " log_choice
            case $log_choice in
                1) tail -100f /var/log/apache2/error.log ;;
                2) tail -100f /var/log/apache2/access.log ;;
                3)
                    read -rp "Nama domain: " LOG_DOMAIN
                    tail -100f "/var/log/apache2/${LOG_DOMAIN}-error.log" 2>/dev/null || \
                    error "Log file tidak ditemukan"
                    ;;
            esac
            ;;
        0)
            echo -e "${GREEN}Terima kasih! Sampai jumpa!${NC}"
            exit 0
            ;;
        *)
            error "Pilihan tidak valid!"
            sleep 1
            ;;
    esac

    main_menu
}

# ─────────────────────────────────────────
# ENTRY POINT
# ─────────────────────────────────────────
check_root
check_os
mkdir -p "$(dirname ${LOG_FILE})"
touch "${LOG_FILE}"
main_menu