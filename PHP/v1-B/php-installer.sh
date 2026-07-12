#!/bin/bash

# ==========================================
# PHP Multi-Version Installer & CLI Switcher
# Untuk Ubuntu / Debian
# ==========================================

# Warna untuk output terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Cek apakah script dijalankan sebagai root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Script ini harus dijalankan dengan hak akses root (sudo).${NC}"
    exit 1
fi

# Daftar ekstensi PHP yang umum digunakan
EXTENSIONS=(common mysql xml mbstring zip curl gd intl bcmath redis imagick)

# ==========================================
# FUNGSI 1: Setup Repository
# ==========================================
setup_repository() {
    echo -e "${BLUE}[1/4] Menyiapkan repository Ondrej PHP...${NC}"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y software-properties-common curl apt-transport-https lsb-release ca-certificates
    
    # Tambahkan PPA Ondrej (untuk Ubuntu) atau repo (untuk Debian)
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "$ID" == "ubuntu" ]]; then
            add-apt-repository -y ppa:ondrej/php
        elif [[ "$ID" == "debian" ]]; then
            curl -sSL https://packages.sury.org/php/README.txt | bash
        else
            echo -e "${RED}Sistem operasi tidak didukung. Script ini hanya untuk Ubuntu/Debian.${NC}"
            exit 1
        fi
    fi
    apt-get update -y
    echo -e "${GREEN}Repository berhasil disiapkan.${NC}\n"
}

# ==========================================
# FUNGSI 2: Menu & Instalasi PHP
# ==========================================
install_php() {
    echo -e "${BLUE}[2/4] Pilih Versi PHP yang ingin diinstal:${NC}"
    echo "  1) PHP 7.4"
    echo "  2) PHP 8.0"
    echo "  3) PHP 8.1"
    echo "  4) PHP 8.2"
    echo "  5) PHP 8.3"
    echo -e "${YELLOW}Tips: Anda bisa memilih lebih dari satu dengan format koma (contoh: 2,4,5)${NC}"
    read -p "Pilihan Anda: " choices

    # Parsing input
    IFS=',' read -r -a selected_nums <<< "$choices"
    
    declare -A version_map=(
        ["1"]="7.4"
        ["2"]="8.0"
        ["3"]="8.1"
        ["4"]="8.2"
        ["5"]="8.3"
    )

    selected_versions=()
    for num in "${selected_nums[@]}"; do
        num=$(echo "$num" | tr -d ' ') # Hapus spasi
        if [[ -n "${version_map[$num]}" ]]; then
            selected_versions+=("${version_map[$num]}")
        else
            echo -e "${RED}Pilihan '$num' tidak valid, dilewati.${NC}"
        fi
    done

    if [ ${#selected_versions[@]} -eq 0 ]; then
        echo -e "${RED}Tidak ada versi valid yang dipilih. Keluar.${NC}"
        exit 1
    fi

    echo -e "\n${BLUE}[3/4] Menginstal PHP ${selected_versions[*]} beserta FPM dan Ekstensi...${NC}"
    
    for ver in "${selected_versions[@]}"; do
        echo -e "${YELLOW}>> Menginstal PHP $ver...${NC}"
        
        # Bangun string paket
        packages="php$ver-fpm php$ver-cli"
        for ext in "${EXTENSIONS[@]}"; do
            packages="$packages php$ver-$ext"
        done

        # Eksekusi instalasi
        apt-get install -y $packages
        
        # Aktifkan dan start FPM service
        systemctl enable php$ver-fpm
        systemctl restart php$ver-fpm
        echo -e "${GREEN}>> PHP $ver berhasil diinstal dan FPM dijalankan.${NC}\n"
    done
    
    echo -e "${GREEN}[Selesai] Semua versi PHP yang dipilih berhasil diinstal.${NC}\n"
}

# ==========================================
# FUNGSI 3: Ganti PHP CLI Aktif
# ==========================================
switch_php_cli() {
    echo -e "${BLUE}=== Mengganti Versi PHP CLI Aktif ===${NC}"
    
    # Cari semua binary php yang terinstal
    mapfile -t installed_phps < <(find /usr/bin -maxdepth 1 -name "php[0-9]*.[0-9]*" | sed 's|.*/||' | sort -V)
    
    if [ ${#installed_phps[@]} -eq 0 ]; then
        echo -e "${RED}Tidak ada PHP CLI yang terinstal di sistem ini.${NC}"
        return 1
    fi

    echo "Pilih versi PHP CLI yang ingin dijadikan default:"
    for i in "${!installed_phps[@]}"; do
        ver="${installed_phps[$i]}"
        # Cek apakah ini yang sedang aktif
        current_link=$(readlink -f /usr/bin/php)
        current_bin=$(basename "$current_link")
        
        if [[ "$ver" == "$current_bin" ]]; then
            echo -e "  $((i+1))) ${GREEN}$ver (Aktif Saat Ini)${NC}"
        else
            echo "  $((i+1))) $ver"
        fi
    done

    read -p "Masukkan nomor pilihan: " choice_idx
    
    # Validasi input
    if ! [[ "$choice_idx" =~ ^[0-9]+$ ]] || [ "$choice_idx" -lt 1 ] || [ "$choice_idx" -gt ${#installed_phps[@]} ]; then
        echo -e "${RED}Pilihan tidak valid.${NC}"
        return 1
    fi

    selected_bin="${installed_phps[$((choice_idx-1))]}"
    selected_path="/usr/bin/$selected_bin"

    echo -e "${YELLOW}Mengatur $selected_path sebagai PHP CLI default...${NC}"
    
    # Daftarkan ke update-alternatives (jika belum) dan set
    update-alternatives --install /usr/bin/php php "$selected_path" 100
    update-alternatives --set php "$selected_path"
    
    # Set juga untuk phar (jika ada)
    if [ -f "/usr/bin/phar${selected_bin#php}" ]; then
        phar_path="/usr/bin/phar${selected_bin#php}"
        update-alternatives --install /usr/bin/phar phar "$phar_path" 100
        update-alternatives --set phar "$phar_path"
    fi

    echo -e "${GREEN}Berhasil! PHP CLI default sekarang adalah:${NC}"
    php -v | head -n 1
}

# ==========================================
# MAIN EXECUTION
# ==========================================
main() {
    clear
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN} PHP Multi-Version Installer & Switcher ${NC}"
    echo -e "${GREEN}========================================${NC}\n"

    setup_repository
    install_php
    
    echo -e "${YELLOW}Apakah Anda ingin mengganti versi PHP CLI default sekarang? (y/n)${NC}"
    read -p "Jawab: " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo ""
        switch_php_cli
    fi

    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}           Proses Selesai!              ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "Untuk mengganti versi PHP CLI di masa depan, Anda bisa menjalankan fungsi ini atau menggunakan perintah manual:"
    echo -e "${YELLOW}sudo update-alternatives --config php${NC}"
}

main