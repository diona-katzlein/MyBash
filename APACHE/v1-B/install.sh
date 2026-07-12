#!/bin/bash

# ==========================================
# Apache Manager & Automation Script
# Untuk Ubuntu/Debian
# ==========================================

# Warna Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Cek Root Privileges
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Script ini harus dijalankan sebagai root atau dengan sudo.${NC}"
    exit 1
fi

clear
echo -e "${CYAN}"
echo "======================================================"
echo "       APACHE MANAGER & AUTOMATION SCRIPT             "
echo "======================================================"
echo -e "${NC}"

# ==========================================
# FUNGSI 1: Install Apache
# ==========================================
install_apache() {
    echo -e "${YELLOW}[INFO] Mengupdate repository dan menginstall Apache...${NC}"
    apt update -y
    apt install apache2 ufw -y
    
    # Enable modul dasar yang sering dibutuhkan
    a2enmod rewrite
    a2enmod headers
    a2enmod proxy
    a2enmod proxy_http
    
    # Start & Enable Apache
    systemctl enable apache2
    systemctl start apache2
    
    # Konfigurasi UFW
    ufw allow 'Apache Full'
    
    echo -e "${GREEN}[SUCCES] Apache berhasil diinstall dan dijalankan.${NC}"
    echo -e "${GREEN}[SUCCES] Modul rewrite, headers, dan proxy telah diaktifkan.${NC}"
    read -p "Tekan Enter untuk kembali ke menu..."
}

# ==========================================
# FUNGSI 2: Hardening & Tweaking
# ==========================================
harden_apache() {
    echo -e "${YELLOW}[INFO] Melakukan Hardening dan Tweaking Apache...${NC}"
    
    # 1. Security Configuration
    cat > /etc/apache2/conf-available/security-hardened.conf <<EOF
# Hide Apache Version
ServerTokens Prod
ServerSignature Off

# Disable Trace
TraceEnable Off

# Security Headers
<IfModule mod_headers.c>
    Header always set X-Content-Type-Options nosniff
    Header always set X-Frame-Options SAMEORIGIN
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
</IfModule>

# Disable Directory Listing globally
<Directory />
    Options -Indexes
    AllowOverride None
    Require all denied
</Directory>
EOF
    a2enconf security-hardened

    # 2. MPM Event Tweaking (Untuk performa tinggi)
    cat > /etc/apache2/mods-available/mpm_event.conf <<EOF
<IfModule mpm_event_module>
    StartServers             4
    MinSpareWorkers         50
    MaxSpareWorkers        100
    ThreadLimit             64
    ThreadsPerChild         50
    MaxRequestWorkers      300
    MaxConnectionsPerChild   0
</IfModule>
EOF

    # 3. Timeout Tweaking
    sed -i 's/Timeout 300/Timeout 60/' /etc/apache2/apache2.conf

    systemctl restart apache2
    echo -e "${GREEN}[SUCCES] Hardening dan Tweaking berhasil diterapkan.${NC}"
    read -p "Tekan Enter untuk kembali ke menu..."
}

# ==========================================
# FUNGSI 3: Setting VHost (PHP Framework/CMS)
# ==========================================
create_vhost_php() {
    echo -e "${YELLOW}[INFO] Membuat Virtual Host untuk PHP/CMS/Framework...${NC}"
    read -p "Masukkan Domain (contoh: example.com): " DOMAIN
    read -p "Jenis Aplikasi? (1: Laravel/Symfony [/public], 2: WP/Joomla/CI/Yii [root]): " APP_TYPE
    
    if [ "$APP_TYPE" == "1" ]; then
        DOC_ROOT="/var/www/$DOMAIN/public"
        ROOT_DIR="/var/www/$DOMAIN"
    else
        DOC_ROOT="/var/www/$DOMAIN"
        ROOT_DIR="/var/www/$DOMAIN"
    fi

    # Buat Direktori
    mkdir -p $ROOT_DIR
    if [ "$APP_TYPE" == "1" ]; then
        mkdir -p $DOC_ROOT
        echo "<?php phpinfo(); ?>" > $DOC_ROOT/index.php # Placeholder
    else
        echo "<?php phpinfo(); ?>" > $DOC_ROOT/index.php # Placeholder
    fi

    # Generate VHost Config
    cat > /etc/apache2/sites-available/$DOMAIN.conf <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN
    ServerAlias www.$DOMAIN
    DocumentRoot $DOC_ROOT

    <Directory $DOC_ROOT>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/$DOMAIN-error.log
    CustomLog \${APACHE_LOG_DIR}/$DOMAIN-access.log combined
</VirtualHost>
EOF

    # Set Permissions
    chown -R www-data:www-data $ROOT_DIR
    find $ROOT_DIR -type d -exec chmod 755 {} \;
    find $ROOT_DIR -type f -exec chmod 644 {} \;

    # Enable Site
    a2ensite $DOMAIN.conf
    systemctl reload apache2

    echo -e "${GREEN}[SUCCES] VHost untuk $DOMAIN berhasil dibuat di $DOC_ROOT${NC}"
    echo -e "${YELLOW}[INFO] Jangan lupa arahkan DNS A Record ke IP server ini.${NC}"
    read -p "Tekan Enter untuk kembali ke menu..."
}

# ==========================================
# FUNGSI 4: Reverse Proxy (Node/Python/Go)
# ==========================================
create_vhost_proxy() {
    echo -e "${YELLOW}[INFO] Membuat Virtual Host Reverse Proxy...${NC}"
    read -p "Masukkan Domain (contoh: api.example.com): " DOMAIN
    read -p "Masukkan Port Backend (contoh: 3000 untuk Node, 8000 untuk Python): " PORT
    
    BACKEND_URL="http://127.0.0.1:$PORT"

    # Generate VHost Config
    cat > /etc/apache2/sites-available/$DOMAIN.conf <<EOF
<VirtualHost *:80>
    ServerName $DOMAIN
    
    ProxyPreserveHost On
    ProxyPass / $BACKEND_URL/
    ProxyPassReverse / $BACKEND_URL/

    # WebSocket Support (Opsional tapi berguna untuk Node/Go)
    RewriteEngine on
    RewriteCond %{HTTP:Upgrade} =websocket [NC]
    RewriteRule /(.*)           $BACKEND_URL/\$1 [P,L]
    
    ErrorLog \${APACHE_LOG_DIR}/$DOMAIN-proxy-error.log
    CustomLog \${APACHE_LOG_DIR}/$DOMAIN-proxy-access.log combined
</VirtualHost>
EOF

    a2ensite $DOMAIN.conf
    a2enmod proxy_wstunnel
    systemctl reload apache2

    echo -e "${GREEN}[SUCCES] Reverse Proxy untuk $DOMAIN ke $BACKEND_URL berhasil dibuat.${NC}"
    read -p "Tekan Enter untuk kembali ke menu..."
}

# ==========================================
# FUNGSI 5: Switch PHP Version
# ==========================================
switch_php() {
    echo -e "${YELLOW}[INFO] Fitur Switch PHP Version...${NC}"
    
    # Pastikan PPA Ondrej ada
    if ! grep -q "ondrej/php" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
        echo -e "${YELLOW}[INFO] Menambahkan repository Ondrej PHP...${NC}"
        apt install software-properties-common -y
        add-apt-repository ppa:ondrej/php -y
        apt update -y
    fi

    echo "Versi PHP yang tersedia untuk diinstall:"
    echo "1) PHP 7.4"
    echo "2) PHP 8.0"
    echo "3) PHP 8.1"
    echo "4) PHP 8.2"
    echo "5) PHP 8.3"
    read -p "Pilih versi PHP yang diinginkan (1-5): " PHP_CHOICE

    case $PHP_CHOICE in
        1) PHP_VER="7.4" ;;
        2) PHP_VER="8.0" ;;
        3) PHP_VER="8.1" ;;
        4) PHP_VER="8.2" ;;
        5) PHP_VER="8.3" ;;
        *) echo -e "${RED}Pilihan tidak valid!${NC}"; read -p "Tekan Enter..."; return ;;
    esac

    echo -e "${YELLOW}[INFO] Menginstall PHP $PHP_VER dan modul Apache...${NC}"
    apt install php$PHP_VER php$PHP_VER-common php$PHP_VER-mysql php$PHP_VER-xml php$PHP_VER-curl php$PHP_VER-mbstring php$PHP_VER-zip libapache2-mod-php$PHP_VER -y

    # Disable semua mod-php yang aktif
    for ver in 7.4 8.0 8.1 8.2 8.3; do
        a2dismod php$ver 2>/dev/null
    done

    # Enable PHP versi baru
    a2enmod php$PHP_VER
    
    systemctl restart apache2
    echo -e "${GREEN}[SUCCES] Apache sekarang menggunakan PHP $PHP_VER${NC}"
    php -v
    read -p "Tekan Enter untuk kembali ke menu..."
}

# ==========================================
# FUNGSI 6: Enable/Disable Modul
# ==========================================
manage_modules() {
    echo -e "${YELLOW}[INFO] Manajemen Modul Apache...${NC}"
    echo "Daftar Modul yang sedang Aktif:"
    apache2ctl -M | grep -v "Loaded Modules" | sort
    echo "---------------------------------------------------"
    echo "1) Enable Modul"
    echo "2) Disable Modul"
    echo "3) Kembali"
    read -p "Pilihan: " MOD_CHOICE

    if [ "$MOD_CHOICE" == "1" ]; then
        read -p "Masukkan nama modul (contoh: ssl, expires): " MOD_NAME
        a2enmod $MOD_NAME
        systemctl reload apache2
        echo -e "${GREEN}[SUCCES] Modul $MOD_NAME diaktifkan.${NC}"
    elif [ "$MOD_CHOICE" == "2" ]; then
        read -p "Masukkan nama modul (contoh: status, autoindex): " MOD_NAME
        a2dismod $MOD_NAME
        systemctl reload apache2
        echo -e "${GREEN}[SUCCES] Modul $MOD_NAME dinonaktifkan.${NC}"
    fi
    read -p "Tekan Enter untuk kembali ke menu..."
}

# ==========================================
# MENU UTAMA
# ==========================================
show_menu() {
    clear
    echo -e "${CYAN}======================================================"
    echo "               APACHE MANAGER MENU                    "
    echo "======================================================${NC}"
    echo " 1. Install Apache & Basic Setup"
    echo " 2. Hardening & Tweaking Apache"
    echo " 3. Buat VHost (Laravel/CI/Symfony/WP/Joomla/dll)"
    echo " 4. Buat VHost Reverse Proxy (Node/Python/Go)"
    echo " 5. Switch PHP Version"
    echo " 6. Enable / Disable Apache Modules"
    echo " 7. Keluar"
    echo -e "${CYAN}======================================================${NC}"
    read -p "Pilih Menu [1-7]: " MENU_CHOICE
}

# Loop Menu
while true; do
    show_menu
    case $MENU_CHOICE in
        1) install_apache ;;
        2) harden_apache ;;
        3) create_vhost_php ;;
        4) create_vhost_proxy ;;
        5) switch_php ;;
        6) manage_modules ;;
        7) echo -e "${GREEN}Terima kasih! Exiting...${NC}"; exit 0 ;;
        *) echo -e "${RED}Pilihan tidak valid! Silakan coba lagi.${NC}"; sleep 2 ;;
    esac
done