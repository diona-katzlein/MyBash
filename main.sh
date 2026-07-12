#!/bin/bash

# ============================================================
# MyBash - Main Launcher & Remote Script Aggregator
# Author  : IsekaiID (https://github.com/diona-katzlein)
# Base URL: https://github.com/diona-katzlein/MyBash
# Version : 1.0.8 - Mondstadt
# License : MIT
# ============================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Git Config Details
RAW_BASE_URL="https://raw.githubusercontent.com/diona-katzlein/MyBash/main"

# Check root privilege
# Detect OS Family
OS_FAMILY="Unknown OS"
if [[ -f /etc/debian_version ]] || [[ -f /etc/ubuntu_release ]] || grep -qi "debian\|ubuntu" /etc/os-release 2>/dev/null; then
    OS_FAMILY="Debian/Ubuntu"
elif [[ -f /etc/redhat-release ]] || [[ -f /etc/system-release ]] || grep -qi "rhel\|fedora\|centos\|alma\|rocky" /etc/os-release 2>/dev/null; then
    OS_FAMILY="RHEL/Alma/Rocky/Fedora"
fi

# Check root privilege
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[ERROR] Script ini harus dijalankan sebagai root atau dengan sudo!${NC}"
        exit 1
    fi
}

# Banner
show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "  __  __       ____                 _      "
    echo " |  \/  |_   _| __ )  __ _ ___  ___| |__   "
    echo " | |\/| | | | |  _ \ / _\` / __|/ _ \ '_ \  "
    echo " | |  | | |_| | |_) | (_| \__ \  __/ | | | "
    echo " |_|  |_|\__, |____/ \__,_|___/\___|_| |_| "
    echo "         |___/                             "
    echo -e "${NC}"
    echo -e "${BLUE}======================================================${NC}"
    echo -e "  ${BOLD}MyBash: Hardening & Application Auto-Installer${NC}"
    echo -e "  Author    : IsekaiID (https://github.com/diona-katzlein)"
    echo -e "  Version   : 1.0.8 - Mondstadt (MIT License)"
    echo -e "  System OS : ${GREEN}${OS_FAMILY}${NC}"
    echo -e "${BLUE}======================================================${NC}\n"
}

# Run script wrapper
run_script() {
    local category="$1"
    local version="$2"
    local script_name="$3"
    
    local local_path
    local remote_url
    if [[ -n "$version" ]]; then
        local_path="./${category}/${version}/${script_name}"
        remote_url="${RAW_BASE_URL}/${category}/${version}/${script_name}"
        echo -e "${YELLOW}[INFO] Menyiapkan script: ${category} (${version}) -> ${script_name}...${NC}"
    else
        local_path="./${category}/${script_name}"
        remote_url="${RAW_BASE_URL}/${category}/${script_name}"
        echo -e "${YELLOW}[INFO] Menyiapkan script: ${category} -> ${script_name}...${NC}"
    fi
    
    if [[ -f "$local_path" ]]; then
        echo -e "${GREEN}[OK] Menggunakan script lokal: ${local_path}${NC}"
        chmod +x "$local_path"
        bash "$local_path"
    else
        echo -e "${YELLOW}[INFO] Script lokal tidak ditemukan, mencoba mengunduh dari remote...${NC}"
        echo -e "${CYAN}URL: ${remote_url}${NC}"
        
        # Temporary storage
        local temp_script
        temp_script=$(mktemp)
        
        if curl -fsSL "$remote_url" -o "$temp_script"; then
            echo -e "${GREEN}[SUCCESS] Berhasil mengunduh script.${NC}"
            chmod +x "$temp_script"
            bash "$temp_script"
            rm -f "$temp_script"
        elif wget -qO "$temp_script" "$remote_url"; then
            echo -e "${GREEN}[SUCCESS] Berhasil mengunduh script via wget.${NC}"
            chmod +x "$temp_script"
            bash "$temp_script"
            rm -f "$temp_script"
        else
            echo -e "${RED}[ERROR] Gagal mengunduh script! Periksa koneksi internet atau URL.${NC}"
            rm -f "$temp_script"
            read -r -p "Tekan [Enter] untuk kembali..."
        fi
    fi
}

main_menu() {
    while true; do
        show_banner
        echo -e "${BOLD}Pilih Kategori Aplikasi:${NC}"
        echo -e " [1] APACHE Web Server (Install & Management)"
        echo -e " [2] NGINX Web Server (Install & Hardening)"
        echo -e " [3] PHP Manager (Install, Config & Switching)"
        echo -e " [4] SSH Server (Hardening & Security Config)"
        echo -e " [0] Keluar / Exit"
        echo
        read -r -p "Pilihan Anda [0-4]: " main_choice
        
        case "$main_choice" in
            1)
                apache_menu
                ;;
            2)
                nginx_menu
                ;;
            3)
                php_menu
                ;;
            4)
                ssh_menu
                ;;
            0)
                echo -e "\n${GREEN}Terima kasih telah menggunakan MyBash! Sampai jumpa.${NC}"
                exit 0
                ;;
            *)
                echo -e "\n${RED}[ERROR] Pilihan tidak valid!${NC}"
                sleep 1
                ;;
        esac
    done
}

apache_menu() {
    while true; do
        show_banner
        echo -e "${BOLD}APACHE Web Server Installer Menu:${NC}"
        echo -e " [1] Apache v1-A (Fitur Lengkap: Setup & Management, VirtualHost, PHP Switch)"
        echo -e " [2] Apache v1-B (Fitur Simple: Install, Hardening & Basic Tools)"
        echo -e " [0] Kembali ke Menu Utama"
        echo
        read -r -p "Pilihan Anda [0-2]: " choice
        
        case "$choice" in
            1)
                run_script "APACHE" "v1-A" "install.sh"
                break
                ;;
            2)
                run_script "APACHE" "v1-B" "install.sh"
                break
                ;;
            0)
                break
                ;;
            *)
                echo -e "\n${RED}[ERROR] Pilihan tidak valid!${NC}"
                sleep 1
                ;;
        esac
    done
}

nginx_menu() {
    while true; do
        show_banner
        echo -e "${BOLD}NGINX Web Server Installer Menu:${NC}"
        echo -e " [1] Nginx v1-A (Install, Hardening, VHost Creator, SSL config)"
        echo -e " [2] Nginx v1-B (PHP-Installer/Nginx setup & VHost simple config)"
        echo -e " [3] Nginx v1-A VHost Configurator (vhost.sh)"
        echo -e " [4] Nginx v1-B VHost Configurator (vhost.sh)"
        echo -e " [0] Kembali ke Menu Utama"
        echo
        read -r -p "Pilihan Anda [0-4]: " choice
        
        case "$choice" in
            1)
                run_script "NGINX" "v1-A" "nginx-installer.sh"
                break
                ;;
            2)
                run_script "NGINX" "v1-B" "php-installer.sh"
                break
                ;;
            3)
                run_script "NGINX" "v1-A" "vhost.sh"
                break
                ;;
            4)
                run_script "NGINX" "v1-B" "vhost.sh"
                break
                ;;
            0)
                break
                ;;
            *)
                echo -e "\n${RED}[ERROR] Pilihan tidak valid!${NC}"
                sleep 1
                ;;
        esac
    done
}

php_menu() {
    while true; do
        show_banner
        echo -e "${BOLD}PHP Manager Installer Menu:${NC}"
        echo -e " [1] PHP v1-A (PHP Manager - Install & Switch PHP 7.4 - 8.3)"
        echo -e " [2] PHP v1-B (PHP FPM Simple Auto-Installer & Switcher)"
        echo -e " [0] Kembali ke Menu Utama"
        echo
        read -r -p "Pilihan Anda [0-2]: " choice
        
        case "$choice" in
            1)
                run_script "PHP" "v1-A" "php-installer.sh"
                break
                ;;
            2)
                run_script "PHP" "v1-B" "php-installer.sh"
                break
                ;;
            0)
                break
                ;;
            *)
                echo -e "\n${RED}[ERROR] Pilihan tidak valid!${NC}"
                sleep 1
                ;;
        esac
    done
}

ssh_menu() {
    while true; do
        show_banner
        echo -e "${BOLD}SSH Server Hardening Menu:${NC}"
        echo -e " [1] SSH Hardening v1-A (Fitur Lengkap: Port, Crypto, Password/Key Auth, Fail2Ban)"
        echo -e " [2] SSH Hardening v1-B (Fitur Simple: Non-interaktif, Auto-Hardening)"
        echo -e " [0] Kembali ke Menu Utama"
        echo
        read -r -p "Pilihan Anda [0-2]: " choice
        
        case "$choice" in
            1)
                run_script "SSH" "" "ssh-v1-a.sh"
                break
                ;;
            2)
                run_script "SSH" "" "ssh-v1-b.sh"
                break
                ;;
            0)
                break
                ;;
            *)
                echo -e "\n${RED}[ERROR] Pilihan tidak valid!${NC}"
                sleep 1
                ;;
        esac
    done
}

# Run the script
check_root
main_menu
