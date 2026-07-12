#!/bin/bash

# ============================================
# PHP Manager - Install & Switch PHP Version
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# PHP Versions Available
PHP_VERSIONS=("7.4" "8.0" "8.1" "8.2" "8.3")

# PHP Extensions
PHP_EXTENSIONS=(
    "bcmath"
    "cli"
    "common"
    "curl"
    "fpm"
    "gd"
    "gmp"
    "imagick"
    "imap"
    "intl"
    "ldap"
    "mbstring"
    "memcached"
    "mongodb"
    "mysql"
    "opcache"
    "pdo"
    "pgsql"
    "readline"
    "redis"
    "soap"
    "sqlite3"
    "ssh2"
    "tidy"
    "tokenizer"
    "xdebug"
    "xml"
    "xmlrpc"
    "xsl"
    "yaml"
    "zip"
)

# ============================================
# HELPER FUNCTIONS
# ============================================

print_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║              PHP FPM/CLI Manager v1.0                   ║"
    echo "║         Install, Manage & Switch PHP Versions            ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_success() {
    echo -e "${GREEN}[✓] $1${NC}"
}

print_error() {
    echo -e "${RED}[✗] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[!] $1${NC}"
}

print_info() {
    echo -e "${BLUE}[i] $1${NC}"
}

print_separator() {
    echo -e "${CYAN}──────────────────────────────────────────────────────────${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Script harus dijalankan sebagai root!"
        echo -e "Gunakan: ${YELLOW}sudo $0${NC}"
        exit 1
    fi
}

check_os() {
    if [[ ! -f /etc/debian_version ]] && [[ ! -f /etc/lsb-release ]]; then
        print_error "Script ini hanya untuk Ubuntu/Debian!"
        exit 1
    fi
}

press_enter() {
    echo ""
    echo -e "${YELLOW}Tekan [ENTER] untuk melanjutkan...${NC}"
    read -r
}

# ============================================
# SETUP REPOSITORY
# ============================================

setup_repository() {
    print_info "Menambahkan repository Ondrej PHP..."

    # Install dependencies
    apt-get install -y software-properties-common apt-transport-https ca-certificates curl &>/dev/null

    # Add Ondrej PHP repository
    if ! grep -q "ondrej/php" /etc/apt/sources.list.d/*.list 2>/dev/null; then
        add-apt-repository -y ppa:ondrej/php &>/dev/null
        print_success "Repository berhasil ditambahkan"
    else
        print_info "Repository sudah ada"
    fi

    # Update package list
    print_info "Mengupdate package list..."
    apt-get update &>/dev/null
    print_success "Package list berhasil diupdate"
}

# ============================================
# GET INSTALLED PHP VERSIONS
# ============================================

get_installed_versions() {
    local installed=()
    for ver in "${PHP_VERSIONS[@]}"; do
        if dpkg -l "php${ver}-cli" 2>/dev/null | grep -q "^ii"; then
            installed+=("$ver")
        fi
    done
    echo "${installed[@]}"
}

get_active_cli() {
    if command -v php &>/dev/null; then
        php -r "echo PHP_VERSION;" 2>/dev/null | grep -oE '^[0-9]+\.[0-9]+'
    else
        echo "none"
    fi
}

get_active_cli_full() {
    if command -v php &>/dev/null; then
        php --version 2>/dev/null | head -1
    else
        echo "Tidak ada PHP CLI aktif"
    fi
}

# ============================================
# SELECT PHP VERSIONS
# ============================================

select_php_versions() {
    local mode=$1  # "single" or "multiple"
    local selected=()

    print_banner
    print_separator
    echo -e "${WHITE}  PILIH VERSI PHP YANG AKAN DIINSTALL${NC}"
    print_separator
    echo ""

    # Show available versions with installed status
    echo -e "${WHITE}  Versi PHP Tersedia:${NC}"
    echo ""

    local installed_versions
    read -r -a installed_versions < <(get_installed_versions)

    for i in "${!PHP_VERSIONS[@]}"; do
        local ver="${PHP_VERSIONS[$i]}"
        local status=""
        local color="${WHITE}"

        # Check if installed
        for iv in "${installed_versions[@]}"; do
            if [[ "$iv" == "$ver" ]]; then
                status="${GREEN}[INSTALLED]${NC}"
                color="${GREEN}"
                break
            fi
        done

        printf "  ${CYAN}[%d]${NC} ${color}PHP %s${NC} %b\n" "$((i+1))" "$ver" "$status"
    done

    echo ""

    if [[ "$mode" == "multiple" ]]; then
        echo -e "${YELLOW}  Pilih beberapa versi (contoh: 1 3 5 atau 1,3,5 atau 1-3):${NC}"
        echo -e "${YELLOW}  Ketik 'all' untuk install semua versi${NC}"
    else
        echo -e "${YELLOW}  Pilih satu versi (contoh: 1):${NC}"
    fi

    echo ""
    read -rp "  Pilihan Anda: " input
    echo ""

    # Process input
    if [[ "$mode" == "multiple" ]]; then
        if [[ "$input" == "all" ]]; then
            selected=("${PHP_VERSIONS[@]}")
        else
            # Handle comma-separated
            input="${input//,/ }"

            # Handle range (e.g., 1-3)
            if [[ "$input" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                local start="${BASH_REMATCH[1]}"
                local end="${BASH_REMATCH[2]}"
                for ((j=start; j<=end; j++)); do
                    if [[ $j -ge 1 && $j -le ${#PHP_VERSIONS[@]} ]]; then
                        selected+=("${PHP_VERSIONS[$((j-1))]}")
                    fi
                done
            else
                for num in $input; do
                    if [[ "$num" =~ ^[0-9]+$ ]] && [[ $num -ge 1 ]] && [[ $num -le ${#PHP_VERSIONS[@]} ]]; then
                        selected+=("${PHP_VERSIONS[$((num-1))]}")
                    fi
                done
            fi
        fi
    else
        if [[ "$input" =~ ^[0-9]+$ ]] && [[ $input -ge 1 ]] && [[ $input -le ${#PHP_VERSIONS[@]} ]]; then
            selected+=("${PHP_VERSIONS[$((input-1))]}")
        fi
    fi

    # Validate selection
    if [[ ${#selected[@]} -eq 0 ]]; then
        print_error "Tidak ada versi yang valid dipilih!"
        press_enter
        return 1
    fi

    # Show selected versions
    echo -e "${WHITE}  Versi yang akan diinstall:${NC}"
    for ver in "${selected[@]}"; do
        echo -e "  ${GREEN}→ PHP $ver${NC}"
    done
    echo ""

    read -rp "  Lanjutkan? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_warning "Instalasi dibatalkan"
        press_enter
        return 1
    fi

    SELECTED_VERSIONS=("${selected[@]}")
    return 0
}

# ============================================
# SELECT EXTENSIONS
# ============================================

select_extensions() {
    print_banner
    print_separator
    echo -e "${WHITE}  PILIH EKSTENSI PHP YANG AKAN DIINSTALL${NC}"
    print_separator
    echo ""

    # Default extensions (always recommended)
    local default_selected=("cli" "fpm" "common" "mysql" "curl" "gd" "mbstring" "xml" "zip" "bcmath" "intl" "opcache" "readline")

    echo -e "${WHITE}  Ekstensi Tersedia:${NC}"
    echo ""

    local cols=3
    local count=0

    for i in "${!PHP_EXTENSIONS[@]}"; do
        local ext="${PHP_EXTENSIONS[$i]}"
        local is_default=false

        # Check if default
        for def in "${default_selected[@]}"; do
            if [[ "$def" == "$ext" ]]; then
                is_default=true
                break
            fi
        done

        local marker=""
        if $is_default; then
            marker="${GREEN}*${NC}"
        fi

        printf "  ${CYAN}[%2d]${NC} %-15s %b" "$((i+1))" "$ext" "$marker"

        count=$((count + 1))
        if [[ $((count % cols)) -eq 0 ]]; then
            echo ""
        fi
    done
    echo ""
    echo ""
    echo -e "  ${GREEN}[*]${NC} = Ekstensi yang direkomendasikan (default)"
    echo ""

    echo -e "${YELLOW}  Pilihan:${NC}"
    echo -e "  ${CYAN}[d]${NC} Gunakan ekstensi default yang direkomendasikan"
    echo -e "  ${CYAN}[a]${NC} Install semua ekstensi"
    echo -e "  ${CYAN}[m]${NC} Pilih manual (contoh: 1 2 5 atau 1,2,5)"
    echo ""

    read -rp "  Pilihan Anda: " ext_choice
    echo ""

    case "$ext_choice" in
        d|D)
            SELECTED_EXTENSIONS=("${default_selected[@]}")
            print_info "Menggunakan ekstensi default"
            ;;
        a|A)
            SELECTED_EXTENSIONS=("${PHP_EXTENSIONS[@]}")
            print_info "Semua ekstensi akan diinstall"
            ;;
        m|M)
            echo -e "${YELLOW}  Masukkan nomor ekstensi (contoh: 1 2 5 atau 1,2,5):${NC}"
            read -rp "  Pilihan: " manual_input
            manual_input="${manual_input//,/ }"

            SELECTED_EXTENSIONS=()
            for num in $manual_input; do
                if [[ "$num" =~ ^[0-9]+$ ]] && [[ $num -ge 1 ]] && [[ $num -le ${#PHP_EXTENSIONS[@]} ]]; then
                    SELECTED_EXTENSIONS+=("${PHP_EXTENSIONS[$((num-1))]}")
                fi
            done

            if [[ ${#SELECTED_EXTENSIONS[@]} -eq 0 ]]; then
                print_warning "Tidak ada ekstensi valid, menggunakan default"
                SELECTED_EXTENSIONS=("${default_selected[@]}")
            fi
            ;;
        *)
            SELECTED_EXTENSIONS=("${default_selected[@]}")
            print_info "Menggunakan ekstensi default"
            ;;
    esac

    echo ""
    echo -e "${WHITE}  Ekstensi yang akan diinstall:${NC}"
    for ext in "${SELECTED_EXTENSIONS[@]}"; do
        printf "  ${GREEN}→ %s${NC}\n" "$ext"
    done
    echo ""

    read -rp "  Lanjutkan? (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        print_warning "Instalasi dibatalkan"
        press_enter
        return 1
    fi

    return 0
}

# ============================================
# INSTALL PHP
# ============================================

install_php() {
    local versions=("$@")

    print_banner
    print_separator
    echo -e "${WHITE}  PROSES INSTALASI PHP${NC}"
    print_separator
    echo ""

    # Setup repository first
    setup_repository

    local total=${#versions[@]}
    local current=0

    for ver in "${versions[@]}"; do
        current=$((current + 1))
        echo ""
        print_separator
        echo -e "${WHITE}  Installing PHP $ver ($current/$total)${NC}"
        print_separator
        echo ""

        local packages_to_install=()
        local failed_packages=()

        # Build package list
        for ext in "${SELECTED_EXTENSIONS[@]}"; do
            packages_to_install+=("php${ver}-${ext}")
        done

        # Install packages
        local total_pkg=${#packages_to_install[@]}
        local pkg_count=0

        for pkg in "${packages_to_install[@]}"; do
            pkg_count=$((pkg_count + 1))

            # Check if package exists
            if apt-cache show "$pkg" &>/dev/null; then
                echo -ne "  ${CYAN}[$pkg_count/$total_pkg]${NC} Installing ${WHITE}$pkg${NC}..."

                if apt-get install -y "$pkg" &>/dev/null; then
                    echo -e " ${GREEN}✓${NC}"
                else
                    echo -e " ${RED}✗${NC}"
                    failed_packages+=("$pkg")
                fi
            else
                echo -e "  ${YELLOW}[SKIP]${NC} $pkg - tidak tersedia"
            fi
        done

        # Enable and start FPM service
        if dpkg -l "php${ver}-fpm" 2>/dev/null | grep -q "^ii"; then
            echo ""
            print_info "Mengaktifkan PHP $ver FPM service..."
            systemctl enable "php${ver}-fpm" &>/dev/null
            systemctl start "php${ver}-fpm" &>/dev/null

            if systemctl is-active --quiet "php${ver}-fpm"; then
                print_success "PHP $ver FPM service berjalan"
            else
                print_warning "PHP $ver FPM service gagal distart"
            fi
        fi

        # Show failed packages
        if [[ ${#failed_packages[@]} -gt 0 ]]; then
            echo ""
            print_warning "Package yang gagal diinstall:"
            for fp in "${failed_packages[@]}"; do
                echo -e "  ${RED}✗ $fp${NC}"
            done
        fi

        echo ""
        print_success "PHP $ver selesai diinstall!"
    done

    echo ""
    print_separator
    print_success "Semua PHP berhasil diinstall!"
    print_separator
    echo ""

    # Ask to set default CLI
    read -rp "  Atur salah satu sebagai PHP CLI default? (y/n): " set_default
    if [[ "$set_default" == "y" || "$set_default" == "Y" ]]; then
        switch_php_cli_menu
    fi

    press_enter
}

# ============================================
# SWITCH PHP CLI
# ============================================

switch_php_cli_menu() {
    print_banner
    print_separator
    echo -e "${WHITE}  GANTI PHP CLI AKTIF${NC}"
    print_separator
    echo ""

    local installed_versions
    read -r -a installed_versions < <(get_installed_versions)
    local active_ver
    active_ver=$(get_active_cli)

    if [[ ${#installed_versions[@]} -eq 0 ]]; then
        print_error "Tidak ada PHP yang terinstall!"
        press_enter
        return
    fi

    echo -e "${WHITE}  PHP CLI yang tersedia:${NC}"
    echo ""

    for i in "${!installed_versions[@]}"; do
        local ver="${installed_versions[$i]}"
        local active_marker=""

        if [[ "$ver" == "$active_ver" ]]; then
            active_marker="${GREEN} ◄ AKTIF${NC}"
        fi

        printf "  ${CYAN}[%d]${NC} PHP %-5s %b\n" "$((i+1))" "$ver" "$active_marker"
    done

    echo ""
    echo -e "  ${CYAN}[0]${NC} Kembali ke menu utama"
    echo ""
    echo -e "  PHP CLI aktif saat ini: ${GREEN}$(get_active_cli_full)${NC}"
    echo ""

    read -rp "  Pilih versi PHP CLI: " choice

    if [[ "$choice" == "0" ]]; then
        return
    fi

    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#installed_versions[@]} ]]; then
        local selected_ver="${installed_versions[$((choice-1))]}"
        switch_php_cli "$selected_ver"
    else
        print_error "Pilihan tidak valid!"
        press_enter
    fi
}

switch_php_cli() {
    local version=$1

    print_info "Mengganti PHP CLI ke versi $version..."
    echo ""

    # Check if php-cli is installed for this version
    if ! dpkg -l "php${version}-cli" 2>/dev/null | grep -q "^ii"; then
        print_error "PHP $version CLI belum terinstall!"
        press_enter
        return
    fi

    # Switch using update-alternatives
    if update-alternatives --set php "/usr/bin/php${version}" &>/dev/null; then
        print_success "PHP CLI berhasil diganti ke PHP $version"
    else
        # Try to install alternatives
        update-alternatives --install /usr/bin/php php "/usr/bin/php${version}" 1 &>/dev/null
        update-alternatives --set php "/usr/bin/php${version}" &>/dev/null
        print_success "PHP CLI berhasil diganti ke PHP $version"
    fi

    # Also switch phar, phpize if available
    for tool in phar phpize php-config; do
        if [[ -f "/usr/bin/${tool}${version}" ]]; then
            update-alternatives --install "/usr/bin/${tool}" "${tool}" "/usr/bin/${tool}${version}" 1 &>/dev/null
            update-alternatives --set "${tool}" "/usr/bin/${tool}${version}" &>/dev/null
        fi
    done

    echo ""
    echo -e "${WHITE}  Verifikasi:${NC}"
    echo -e "  ${GREEN}$(php --version | head -1)${NC}"
    echo ""

    print_success "Pergantian PHP CLI selesai!"
    press_enter
}

# ============================================
# SHOW PHP STATUS
# ============================================

show_status() {
    print_banner
    print_separator
    echo -e "${WHITE}  STATUS PHP YANG TERINSTALL${NC}"
    print_separator
    echo ""

    local installed_versions
    read -r -a installed_versions < <(get_installed_versions)
    local active_ver
    active_ver=$(get_active_cli)

    if [[ ${#installed_versions[@]} -eq 0 ]]; then
        print_warning "Tidak ada PHP yang terinstall"
        press_enter
        return
    fi

    echo -e "${WHITE}  PHP CLI Aktif:${NC}"
    echo -e "  ${GREEN}$(get_active_cli_full)${NC}"
    echo ""

    print_separator
    echo -e "${WHITE}  Detail PHP Terinstall:${NC}"
    print_separator
    echo ""

    for ver in "${installed_versions[@]}"; do
        local active_marker=""
        if [[ "$ver" == "$active_ver" ]]; then
            active_marker="${GREEN}[AKTIF]${NC}"
        fi

        echo -e "  ${CYAN}PHP $ver${NC} $active_marker"

        # Check CLI
        if dpkg -l "php${ver}-cli" 2>/dev/null | grep -q "^ii"; then
            echo -e "    ${GREEN}✓${NC} CLI"
        fi

        # Check FPM
        if dpkg -l "php${ver}-fpm" 2>/dev/null | grep -q "^ii"; then
            local fpm_status
            if systemctl is-active --quiet "php${ver}-fpm" 2>/dev/null; then
                fpm_status="${GREEN}running${NC}"
            else
                fpm_status="${RED}stopped${NC}"
            fi
            echo -e "    ${GREEN}✓${NC} FPM - Status: $fpm_status"
        fi

        # Show installed extensions
        echo -e "    ${BLUE}Extensions:${NC}"
        local exts
        exts=$(php${ver} -m 2>/dev/null | grep -v "\[" | tr '\n' ' ')
        echo -e "    ${WHITE}$exts${NC}" | fold -s -w 70
        echo ""
    done

    press_enter
}

# ============================================
# MANAGE FPM SERVICE
# ============================================

manage_fpm_service() {
    print_banner
    print_separator
    echo -e "${WHITE}  KELOLA PHP FPM SERVICE${NC}"
    print_separator
    echo ""

    local installed_versions
    read -r -a installed_versions < <(get_installed_versions)

    if [[ ${#installed_versions[@]} -eq 0 ]]; then
        print_error "Tidak ada PHP yang terinstall!"
        press_enter
        return
    fi

    # Show FPM status
    echo -e "${WHITE}  Status PHP FPM:${NC}"
    echo ""

    for ver in "${installed_versions[@]}"; do
        if dpkg -l "php${ver}-fpm" 2>/dev/null | grep -q "^ii"; then
            local status
            if systemctl is-active --quiet "php${ver}-fpm" 2>/dev/null; then
                status="${GREEN}● running${NC}"
            else
                status="${RED}● stopped${NC}"
            fi
            echo -e "  PHP $ver FPM: $status"
        fi
    done

    echo ""
    print_separator
    echo -e "${WHITE}  Aksi:${NC}"
    echo ""
    echo -e "  ${CYAN}[1]${NC} Start semua FPM"
    echo -e "  ${CYAN}[2]${NC} Stop semua FPM"
    echo -e "  ${CYAN}[3]${NC} Restart semua FPM"
    echo -e "  ${CYAN}[4]${NC} Start FPM spesifik"
    echo -e "  ${CYAN}[5]${NC} Stop FPM spesifik"
    echo -e "  ${CYAN}[6]${NC} Restart FPM spesifik"
    echo -e "  ${CYAN}[0]${NC} Kembali"
    echo ""

    read -rp "  Pilihan: " choice
    echo ""

    case "$choice" in
        1)
            for ver in "${installed_versions[@]}"; do
                if dpkg -l "php${ver}-fpm" 2>/dev/null | grep -q "^ii"; then
                    systemctl start "php${ver}-fpm" && print_success "PHP $ver FPM started" || print_error "PHP $ver FPM gagal start"
                fi
            done
            ;;
        2)
            for ver in "${installed_versions[@]}"; do
                if dpkg -l "php${ver}-fpm" 2>/dev/null | grep -q "^ii"; then
                    systemctl stop "php${ver}-fpm" && print_success "PHP $ver FPM stopped" || print_error "PHP $ver FPM gagal stop"
                fi
            done
            ;;
        3)
            for ver in "${installed_versions[@]}"; do
                if dpkg -l "php${ver}-fpm" 2>/dev/null | grep -q "^ii"; then
                    systemctl restart "php${ver}-fpm" && print_success "PHP $ver FPM restarted" || print_error "PHP $ver FPM gagal restart"
                fi
            done
            ;;
        4|5|6)
            echo -e "${WHITE}  Pilih versi PHP FPM:${NC}"
            for i in "${!installed_versions[@]}"; do
                if dpkg -l "php${installed_versions[$i]}-fpm" 2>/dev/null | grep -q "^ii"; then
                    echo -e "  ${CYAN}[$((i+1))]${NC} PHP ${installed_versions[$i]}"
                fi
            done
            echo ""
            read -rp "  Pilihan: " ver_choice

            if [[ "$ver_choice" =~ ^[0-9]+$ ]] && [[ $ver_choice -ge 1 ]] && [[ $ver_choice -le ${#installed_versions[@]} ]]; then
                local sel_ver="${installed_versions[$((ver_choice-1))]}"
                case "$choice" in
                    4) systemctl start "php${sel_ver}-fpm" && print_success "PHP $sel_ver FPM started" ;;
                    5) systemctl stop "php${sel_ver}-fpm" && print_success "PHP $sel_ver FPM stopped" ;;
                    6) systemctl restart "php${sel_ver}-fpm" && print_success "PHP $sel_ver FPM restarted" ;;
                esac
            fi
            ;;
        0) return ;;
    esac

    press_enter
}

# ============================================
# UNINSTALL PHP
# ============================================

uninstall_php() {
    print_banner
    print_separator
    echo -e "${WHITE}  UNINSTALL PHP${NC}"
    print_separator
    echo ""

    local installed_versions
    read -r -a installed_versions < <(get_installed_versions)

    if [[ ${#installed_versions[@]} -eq 0 ]]; then
        print_error "Tidak ada PHP yang terinstall!"
        press_enter
        return
    fi

    echo -e "${WHITE}  PHP Terinstall:${NC}"
    echo ""

    for i in "${!installed_versions[@]}"; do
        echo -e "  ${CYAN}[$((i+1))]${NC} PHP ${installed_versions[$i]}"
    done

    echo -e "  ${CYAN}[a]${NC} Uninstall semua"
    echo -e "  ${CYAN}[0]${NC} Kembali"
    echo ""

    read -rp "  Pilihan: " choice
    echo ""

    local to_uninstall=()

    if [[ "$choice" == "a" || "$choice" == "A" ]]; then
        to_uninstall=("${installed_versions[@]}")
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#installed_versions[@]} ]]; then
        to_uninstall=("${installed_versions[$((choice-1))]}")
    elif [[ "$choice" == "0" ]]; then
        return
    else
        print_error "Pilihan tidak valid!"
        press_enter
        return
    fi

    echo -e "${RED}  PERINGATAN: PHP berikut akan diuninstall:${NC}"
    for ver in "${to_uninstall[@]}"; do
        echo -e "  ${RED}→ PHP $ver${NC}"
    done
    echo ""

    read -rp "  Yakin ingin uninstall? (ketik 'yes' untuk konfirmasi): " confirm
    if [[ "$confirm" != "yes" ]]; then
        print_warning "Uninstall dibatalkan"
        press_enter
        return
    fi

    for ver in "${to_uninstall[@]}"; do
        print_info "Menguninstall PHP $ver..."

        # Stop FPM service first
        systemctl stop "php${ver}-fpm" 2>/dev/null
        systemctl disable "php${ver}-fpm" 2>/dev/null

        # Remove all PHP packages for this version
        apt-get remove --purge -y "php${ver}*" &>/dev/null
        print_success "PHP $ver berhasil diuninstall"
    done

    # Clean up
    apt-get autoremove -y &>/dev/null
    apt-get autoclean &>/dev/null

    print_success "Uninstall selesai!"
    press_enter
}

# ============================================
# INSTALL ADDITIONAL EXTENSIONS
# ============================================

install_additional_extensions() {
    print_banner
    print_separator
    echo -e "${WHITE}  INSTALL EKSTENSI TAMBAHAN${NC}"
    print_separator
    echo ""

    local installed_versions
    read -r -a installed_versions < <(get_installed_versions)

    if [[ ${#installed_versions[@]} -eq 0 ]]; then
        print_error "Tidak ada PHP yang terinstall!"
        press_enter
        return
    fi

    # Select PHP version
    echo -e "${WHITE}  Pilih versi PHP:${NC}"
    echo ""

    for i in "${!installed_versions[@]}"; do
        echo -e "  ${CYAN}[$((i+1))]${NC} PHP ${installed_versions[$i]}"
    done

    echo -e "  ${CYAN}[a]${NC} Install ke semua versi"
    echo ""

    read -rp "  Pilihan: " ver_choice
    echo ""

    local target_versions=()

    if [[ "$ver_choice" == "a" || "$ver_choice" == "A" ]]; then
        target_versions=("${installed_versions[@]}")
    elif [[ "$ver_choice" =~ ^[0-9]+$ ]] && [[ $ver_choice -ge 1 ]] && [[ $ver_choice -le ${#installed_versions[@]} ]]; then
        target_versions=("${installed_versions[$((ver_choice-1))]}")
    else
        print_error "Pilihan tidak valid!"
        press_enter
        return
    fi

    # Select extensions
    if ! select_extensions; then
        return
    fi

    # Install extensions
    for ver in "${target_versions[@]}"; do
        print_info "Installing ekstensi untuk PHP $ver..."
        echo ""

        local pkg_count=0
        local total_pkg=${#SELECTED_EXTENSIONS[@]}

        for ext in "${SELECTED_EXTENSIONS[@]}"; do
            pkg_count=$((pkg_count + 1))
            local pkg="php${ver}-${ext}"

            if apt-cache show "$pkg" &>/dev/null; then
                echo -ne "  ${CYAN}[$pkg_count/$total_pkg]${NC} Installing ${WHITE}$pkg${NC}..."

                if apt-get install -y "$pkg" &>/dev/null; then
                    echo -e " ${GREEN}✓${NC}"
                else
                    echo -e " ${RED}✗${NC}"
                fi
            else
                echo -e "  ${YELLOW}[SKIP]${NC} $pkg - tidak tersedia"
            fi
        done

        echo ""
        print_success "Ekstensi PHP $ver selesai diinstall"
    done

    press_enter
}

# ============================================
# MAIN MENU
# ============================================

main_menu() {
    while true; do
        print_banner

        local active_ver
        active_ver=$(get_active_cli)
        local installed_versions
        read -r -a installed_versions < <(get_installed_versions)

        print_separator
        echo -e "  ${WHITE}PHP CLI Aktif  :${NC} ${GREEN}PHP $active_ver${NC}"
        echo -e "  ${WHITE}PHP Terinstall :${NC} ${CYAN}${installed_versions[*]:-'Belum ada'}${NC}"
        print_separator
        echo ""
        echo -e "${WHITE}  MENU UTAMA${NC}"
        echo ""
        echo -e "  ${CYAN}[1]${NC} Install 1 versi PHP"
        echo -e "  ${CYAN}[2]${NC} Install beberapa versi PHP"
        echo -e "  ${CYAN}[3]${NC} Ganti PHP CLI aktif"
        echo -e "  ${CYAN}[4]${NC} Kelola PHP FPM Service"
        echo -e "  ${CYAN}[5]${NC} Install ekstensi tambahan"
        echo -e "  ${CYAN}[6]${NC} Lihat status PHP"
        echo -e "  ${CYAN}[7]${NC} Uninstall PHP"
        echo -e "  ${CYAN}[0]${NC} Keluar"
        echo ""
        print_separator
        echo ""

        read -rp "  Pilihan Anda: " choice
        echo ""

        case "$choice" in
            1)
                if select_php_versions "single"; then
                    if select_extensions; then
                        install_php "${SELECTED_VERSIONS[@]}"
                    fi
                fi
                ;;
            2)
                if select_php_versions "multiple"; then
                    if select_extensions; then
                        install_php "${SELECTED_VERSIONS[@]}"
                    fi
                fi
                ;;
            3)
                switch_php_cli_menu
                ;;
            4)
                manage_fpm_service
                ;;
            5)
                install_additional_extensions
                ;;
            6)
                show_status
                ;;
            7)
                uninstall_php
                ;;
            0)
                echo -e "${GREEN}  Terima kasih! Sampai jumpa!${NC}"
                echo ""
                exit 0
                ;;
            *)
                print_error "Pilihan tidak valid!"
                press_enter
                ;;
        esac
    done
}

# ============================================
# MAIN ENTRY POINT
# ============================================

# Global variables
SELECTED_VERSIONS=()
SELECTED_EXTENSIONS=()

# Run checks
check_root
check_os

# Start main menu
main_menu