#!/bin/bash

# ============================================================
# Script Hardening SSH untuk Linux (Simple v1-B)
# Author: IsekaiID (https://github.com/diona-katzlein)
# Description: Script untuk melakukan hardening konfigurasi SSH
# ============================================================

# Warna output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Cek apakah script dijalankan sebagai root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: Script ini harus dijalankan sebagai root (gunakan sudo).${NC}"
    exit 1
fi

SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP_FILE="${SSHD_CONFIG}.bak.$(date +%F_%T)"

echo -e "${YELLOW}[*] Memulai proses Hardening SSH...${NC}"

# 1. Backup konfigurasi asli
echo -e "${GREEN}[+] Membuat backup konfigurasi SSH di ${BACKUP_FILE}${NC}"
cp "$SSHD_CONFIG" "$BACKUP_FILE"

# Fungsi untuk mengubah atau menambahkan parameter di sshd_config
set_ssh_option() {
    local option=$1
    local value=$2
    
    # Cek apakah opsi sudah ada (baik dikomentari maupun tidak)
    if grep -qE "^\s*#?\s*${option}\s" "$SSHD_CONFIG"; then
        # Jika ada, ganti nilainya
        sed -i "s|^\s*#?\s*${option}\s.*|${option} ${value}|" "$SSHD_CONFIG"
    else
        # Jika tidak ada, tambahkan di baris paling bawah
        echo "${option} ${value}" >> "$SSHD_CONFIG"
    fi
}

# 2. Menerapkan Konfigurasi Hardening
echo -e "${GREEN}[+] Menerapkan parameter keamanan SSH...${NC}"

# Nonaktifkan Root Login
set_ssh_option "PermitRootLogin" "no"

# Nonaktifkan Autentikasi Password (Wajib pakai SSH Key)
set_ssh_option "PasswordAuthentication" "no"
set_ssh_option "PermitEmptyPasswords" "no"
set_ssh_option "ChallengeResponseAuthentication" "no"
set_ssh_option "KbdInteractiveAuthentication" "no" # Untuk OpenSSH versi baru

# Aktifkan Autentikasi Public Key
set_ssh_option "PubkeyAuthentication" "yes"

# Batasi percobaan login dan waktu grace
set_ssh_option "MaxAuthTries" "3"
set_ssh_option "LoginGraceTime" "60"

# Nonaktifkan forwarding yang tidak perlu (mencegah pivot jika server diretas)
set_ssh_option "X11Forwarding" "no"
set_ssh_option "AllowTcpForwarding" "no"
set_ssh_option "AllowAgentForwarding" "no"
set_ssh_option "PermitTunnel" "no"

# Setting Timeout koneksi (Idle)
set_ssh_option "ClientAliveInterval" "300"
set_ssh_option "ClientAliveCountMax" "2"

# Logging dan DNS
set_ssh_option "LogLevel" "VERBOSE"
set_ssh_option "UseDNS" "no"

# Menggunakan Cipher, MAC, dan Key Exchange yang kuat (Modern Cryptography)
set_ssh_option "Ciphers" "chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr"
set_ssh_option "MACs" "hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com,hmac-sha2-512,hmac-sha2-256"
set_ssh_option "KexAlgorithms" "curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group14-sha256"

# 3. Validasi Konfigurasi
echo -e "${GREEN}[+] Memvalidasi konfigurasi SSH...${NC}"
if sshd -t -f "$SSHD_CONFIG"; then
    echo -e "${GREEN}[+] Konfigurasi SSH valid!${NC}"
else
    echo -e "${RED}[!] Error: Konfigurasi SSH tidak valid. Mengembalikan backup...${NC}"
    cp "$BACKUP_FILE" "$SSHD_CONFIG"
    exit 1
fi

# 4. Restart Service SSH
echo -e "${GREEN}[+] Merestart service SSH...${NC}"
# Mendeteksi nama service (Ubuntu/Debian biasanya 'ssh', RHEL/CentOS biasanya 'sshd')
if systemctl is-active --quiet ssh; then
    systemctl restart ssh
elif systemctl is-active --quiet sshd; then
    systemctl restart sshd
else
    echo -e "${YELLOW}[!] Tidak dapat menemukan service SSH. Silakan restart secara manual.${NC}"
fi

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}[✓] Hardening SSH Berhasil Diterapkan!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo -e "${YELLOW}[!] PENTING: Jangan tutup terminal ini. Buka terminal baru dan coba login untuk memastikan Anda tidak terkunci.${NC}"
