#!/bin/bash

# ============================================================
# SSH Hardening Script
# Author: IsekaiID (https://github.com/diona-katzlein)
# Description: Script untuk mengamankan konfigurasi SSH
# ============================================================

# Warna untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# File konfigurasi
SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP_DIR="/root/ssh_backup"
LOG_FILE="/var/log/ssh_hardening.log"

# ============================================================
# FUNGSI UTILITY
# ============================================================

log() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Cek apakah script dijalankan sebagai root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Script ini harus dijalankan sebagai root!"
        exit 1
    fi
}

# Konfirmasi dari user
confirm() {
    read -r -p "$(echo -e ${YELLOW}"$1 [y/N]: "${NC})" -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

# ============================================================
# FUNGSI BACKUP
# ============================================================

backup_config() {
    header "BACKUP KONFIGURASI"
    
    mkdir -p "$BACKUP_DIR"
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_FILE="$BACKUP_DIR/sshd_config.backup.$TIMESTAMP"
    
    if cp "$SSHD_CONFIG" "$BACKUP_FILE"; then
        log "Backup berhasil: $BACKUP_FILE"
    else
        error "Gagal membuat backup!"
        exit 1
    fi
}

# ============================================================
# FUNGSI SET KONFIGURASI
# ============================================================

set_config() {
    local key="$1"
    local value="$2"
    
    # Hapus baris yang ada (termasuk yang dikomentari)
    sed -i "s/^#\?${key}.*/${key} ${value}/" "$SSHD_CONFIG"
    
    # Jika tidak ada, tambahkan
    if ! grep -q "^${key} " "$SSHD_CONFIG"; then
        echo "${key} ${value}" >> "$SSHD_CONFIG"
    fi
    
    log "Set: ${key} = ${value}"
}

# ============================================================
# FUNGSI HARDENING
# ============================================================

# 1. Ubah Port SSH
change_ssh_port() {
    header "UBAH PORT SSH"
    
    echo -e "${YELLOW}Port default SSH adalah 22${NC}"
    read -r -p "Masukkan port SSH baru (1024-65535) [default: 2222]: " NEW_PORT
    NEW_PORT=${NEW_PORT:-2222}
    
    # Validasi port
    if ! [[ "$NEW_PORT" =~ ^[0-9]+$ ]] || [ "$NEW_PORT" -lt 1024 ] || [ "$NEW_PORT" -gt 65535 ]; then
        warn "Port tidak valid, menggunakan port 2222"
        NEW_PORT=2222
    fi
    
    set_config "Port" "$NEW_PORT"
    log "Port SSH diubah ke: $NEW_PORT"
    
    # Update firewall jika menggunakan UFW
    if command -v ufw &>/dev/null; then
        ufw allow "$NEW_PORT/tcp" &>/dev/null
        ufw delete allow 22/tcp &>/dev/null 2>&1
        log "UFW: Port $NEW_PORT dibuka, port 22 ditutup"
    fi
    
    # Update firewall jika menggunakan firewalld
    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-port="$NEW_PORT/tcp" &>/dev/null
        firewall-cmd --permanent --remove-service=ssh &>/dev/null 2>&1
        firewall-cmd --reload &>/dev/null
        log "Firewalld: Port $NEW_PORT dibuka"
    fi
}

# 2. Nonaktifkan Root Login
disable_root_login() {
    header "NONAKTIFKAN ROOT LOGIN"
    
    set_config "PermitRootLogin" "no"
    log "Root login dinonaktifkan"
}

# 3. Nonaktifkan Password Authentication
disable_password_auth() {
    header "NONAKTIFKAN PASSWORD AUTHENTICATION"
    
    warn "Pastikan Anda sudah mengkonfigurasi SSH Key sebelum menonaktifkan password auth!"
    
    if confirm "Nonaktifkan password authentication?"; then
        set_config "PasswordAuthentication" "no"
        set_config "ChallengeResponseAuthentication" "no"
        set_config "UsePAM" "no"
        log "Password authentication dinonaktifkan"
    else
        set_config "PasswordAuthentication" "yes"
        warn "Password authentication tetap aktif"
    fi
}

# 4. Konfigurasi SSH Protocol dan Enkripsi
configure_crypto() {
    header "KONFIGURASI PROTOKOL DAN ENKRIPSI"
    
    # Hanya gunakan SSH Protocol 2
    set_config "Protocol" "2"
    
    # Algoritma kriptografi yang kuat
    set_config "KexAlgorithms" "curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group14-sha256,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512"
    set_config "Ciphers" "chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr"
    set_config "MACs" "hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com"
    set_config "HostKeyAlgorithms" "ssh-ed25519,ssh-ed25519-cert-v01@openssh.com,rsa-sha2-512,rsa-sha2-256"
    
    log "Konfigurasi enkripsi berhasil diterapkan"
}

# 5. Konfigurasi Timeout dan Session
configure_session() {
    header "KONFIGURASI SESSION DAN TIMEOUT"
    
    set_config "ClientAliveInterval" "300"
    set_config "ClientAliveCountMax" "2"
    set_config "LoginGraceTime" "30"
    set_config "MaxAuthTries" "3"
    set_config "MaxSessions" "3"
    set_config "MaxStartups" "10:30:60"
    
    log "Konfigurasi session dan timeout diterapkan"
}

# 6. Nonaktifkan Fitur yang Tidak Diperlukan
disable_unused_features() {
    header "NONAKTIFKAN FITUR TIDAK DIPERLUKAN"
    
    set_config "X11Forwarding" "no"
    set_config "AllowTcpForwarding" "no"
    set_config "AllowAgentForwarding" "no"
    set_config "GatewayPorts" "no"
    set_config "PermitTunnel" "no"
    set_config "PrintMotd" "no"
    set_config "TCPKeepAlive" "no"
    set_config "Compression" "no"
    set_config "PermitEmptyPasswords" "no"
    set_config "HostbasedAuthentication" "no"
    set_config "IgnoreRhosts" "yes"
    set_config "RhostsRSAAuthentication" "no"
    
    log "Fitur tidak diperlukan dinonaktifkan"
}

# 7. Aktifkan Logging
configure_logging() {
    header "KONFIGURASI LOGGING"
    
    set_config "SyslogFacility" "AUTH"
    set_config "LogLevel" "VERBOSE"
    
    log "Konfigurasi logging diterapkan"
}

# 8. Batasi Akses User
configure_user_access() {
    header "BATASI AKSES USER"
    
    echo -e "${YELLOW}Masukkan username yang diizinkan menggunakan SSH${NC}"
    echo -e "${YELLOW}(pisahkan dengan spasi, kosongkan untuk skip)${NC}"
    read -r -p "AllowUsers: " ALLOW_USERS
    
    if [[ -n "$ALLOW_USERS" ]]; then
        set_config "AllowUsers" "$ALLOW_USERS"
        log "AllowUsers: $ALLOW_USERS"
    fi
    
    echo -e "${YELLOW}Masukkan grup yang diizinkan (kosongkan untuk skip)${NC}"
    read -r -p "AllowGroups: " ALLOW_GROUPS
    
    if [[ -n "$ALLOW_GROUPS" ]]; then
        set_config "AllowGroups" "$ALLOW_GROUPS"
        log "AllowGroups: $ALLOW_GROUPS"
    fi
    
    # Nonaktifkan akses untuk user tertentu
    set_config "DenyUsers" "nobody"
}

# 9. Konfigurasi Banner
configure_banner() {
    header "KONFIGURASI BANNER"
    
    BANNER_FILE="/etc/ssh/banner"
    
    cat > "$BANNER_FILE" << 'EOF'
#############################################################
#                   WARNING / PERINGATAN                     #
#############################################################
#                                                           #
#  Sistem ini hanya untuk pengguna yang BERWENANG.          #
#  Semua aktivitas dipantau dan dicatat.                    #
#  Akses tidak sah akan dilaporkan ke pihak berwajib.       #
#                                                           #
#  This system is for AUTHORIZED users only.                #
#  All activities are monitored and recorded.               #
#  Unauthorized access will be prosecuted.                  #
#                                                           #
#############################################################
EOF
    
    set_config "Banner" "$BANNER_FILE"
    log "Banner dikonfigurasi: $BANNER_FILE"
}

# 10. Setup Fail2Ban
setup_fail2ban() {
    header "SETUP FAIL2BAN"
    
    if ! command -v fail2ban-server &>/dev/null; then
        if confirm "Fail2Ban tidak ditemukan. Install sekarang?"; then
            if command -v apt-get &>/dev/null; then
                apt-get install -y fail2ban &>/dev/null
            elif command -v yum &>/dev/null; then
                yum install -y fail2ban &>/dev/null
            elif command -v dnf &>/dev/null; then
                dnf install -y fail2ban &>/dev/null
            fi
        else
            warn "Fail2Ban tidak diinstall, lewati"
            return
        fi
    fi
    
    # Konfigurasi Fail2Ban untuk SSH
    cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime  = 3600
findtime  = 600
maxretry = 3
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled  = true
port     = $NEW_PORT
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 3
bantime  = 86400
EOF
    
    systemctl enable fail2ban &>/dev/null
    systemctl restart fail2ban &>/dev/null
    log "Fail2Ban dikonfigurasi dan dijalankan"
}

# 11. Generate SSH Host Keys Baru
regenerate_host_keys() {
    header "REGENERATE SSH HOST KEYS"
    
    if confirm "Generate ulang SSH host keys? (Ini akan memutus koneksi existing)"; then
        # Hapus host keys lama
        rm -f /etc/ssh/ssh_host_*
        
        # Generate host keys baru
        ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N "" &>/dev/null
        ssh-keygen -t rsa -b 4096 -f /etc/ssh/ssh_host_rsa_key -N "" &>/dev/null
        
        # Konfigurasi hanya gunakan keys yang kuat
        set_config "HostKey" "/etc/ssh/ssh_host_ed25519_key"
        echo "HostKey /etc/ssh/ssh_host_rsa_key" >> "$SSHD_CONFIG"
        
        log "SSH host keys berhasil digenerate ulang"
    fi
}

# 12. Konfigurasi SSH Key untuk User
setup_ssh_key() {
    header "SETUP SSH KEY AUTHENTICATION"
    
    set_config "PubkeyAuthentication" "yes"
    set_config "AuthorizedKeysFile" ".ssh/authorized_keys"
    
    echo -e "${YELLOW}Apakah Anda ingin membuat SSH key pair baru?${NC}"
    if confirm "Generate SSH key pair baru?"; then
        read -r -p "Masukkan username untuk SSH key: " SSH_USER
        
        if id "$SSH_USER" &>/dev/null; then
            USER_HOME=$(eval echo ~"$SSH_USER")
            SSH_DIR="$USER_HOME/.ssh"
            
            mkdir -p "$SSH_DIR"
            
            # Generate key pair
            sudo -u "$SSH_USER" ssh-keygen -t ed25519 -f "$SSH_DIR/id_ed25519" -N "" -C "$SSH_USER@$(hostname)"
            
            # Set permission yang benar
            chmod 700 "$SSH_DIR"
            chmod 600 "$SSH_DIR/id_ed25519"
            chmod 644 "$SSH_DIR/id_ed25519.pub"
            chown -R "$SSH_USER:$SSH_USER" "$SSH_DIR"
            
            log "SSH key pair dibuat untuk user: $SSH_USER"
            echo -e "${GREEN}Public key:${NC}"
            cat "$SSH_DIR/id_ed25519.pub"
        else
            error "User $SSH_USER tidak ditemukan!"
        fi
    fi
}

# ============================================================
# VALIDASI KONFIGURASI
# ============================================================

validate_config() {
    header "VALIDASI KONFIGURASI"
    
    if sshd -t 2>/dev/null; then
        log "Konfigurasi SSH valid!"
        return 0
    else
        error "Konfigurasi SSH tidak valid!"
        sshd -t
        return 1
    fi
}

# ============================================================
# RESTART SSH SERVICE
# ============================================================

restart_ssh() {
    header "RESTART SSH SERVICE"
    
    warn "PERHATIAN: Jangan tutup sesi ini sampai Anda memverifikasi koneksi SSH baru!"
    
    if confirm "Restart SSH service sekarang?"; then
        if systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null; then
            log "SSH service berhasil direstart"
            
            systemctl is-active --quiet sshd 2>/dev/null || systemctl is-active --quiet ssh 2>/dev/null
            if [ $? -eq 0 ]; then
                log "SSH service berjalan dengan normal"
            else
                error "SSH service gagal berjalan!"
            fi
        else
            error "Gagal merestart SSH service!"
        fi
    fi
}

# ============================================================
# TAMPILKAN RINGKASAN
# ============================================================

show_summary() {
    header "RINGKASAN HARDENING"
    
    echo -e "\n${GREEN}=== Konfigurasi yang diterapkan ===${NC}"
    echo -e "${BLUE}Port SSH:${NC} $NEW_PORT"
    echo -e "${BLUE}Konfigurasi:${NC} $SSHD_CONFIG"
    echo -e "${BLUE}Backup:${NC} $BACKUP_DIR"
    echo -e "${BLUE}Log:${NC} $LOG_FILE"
    
    echo -e "\n${GREEN}=== Setting Aktif ===${NC}"
    grep -E "^(Port|PermitRootLogin|PasswordAuthentication|PubkeyAuthentication|X11Forwarding|MaxAuthTries|Protocol)" "$SSHD_CONFIG" 2>/dev/null
    
    echo -e "\n${YELLOW}=== PERINGATAN PENTING ===${NC}"
    echo -e "1. Test koneksi SSH dengan port baru: ${GREEN}ssh -p $NEW_PORT user@server${NC}"
    echo -e "2. Jangan tutup sesi ini sebelum memverifikasi koneksi baru"
    echo -e "3. Backup konfigurasi tersimpan di: ${GREEN}$BACKUP_DIR${NC}"
    echo -e "4. Log tersimpan di: ${GREEN}$LOG_FILE${NC}"
}

# ============================================================
# MENU UTAMA
# ============================================================

show_menu() {
    clear
    echo -e "${BLUE}"
    echo "  ███████╗███████╗██╗  ██╗    ██╗  ██╗ █████╗ ██████╗ ██████╗ ███████╗███╗   ██╗"
    echo "  ██╔════╝██╔════╝██║  ██║    ██║  ██║██╔══██╗██╔══██╗██╔══██╗██╔════╝████╗  ██║"
    echo "  ███████╗███████╗███████║    ███████║███████║██████╔╝██║  ██║█████╗  ██╔██╗ ██║"
    echo "  ╚════██║╚════██║██╔══██║    ██╔══██║██╔══██║██╔══██╗██║  ██║██╔══╝  ██║╚██╗██║"
    echo "  ███████║███████║██║  ██║    ██║  ██║██║  ██║██║  ██║██████╔╝███████╗██║ ╚████║"
    echo "  ╚══════╝╚══════╝╚═╝  ╚═╝    ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚══════╝╚═╝  ╚═══╝"
    echo -e "${NC}"
    echo -e "${GREEN}SSH Hardening Script${NC}"
    echo -e "======================================"
    echo "1. Hardening Penuh (Semua Opsi)"
    echo "2. Ubah Port SSH"
    echo "3. Nonaktifkan Root Login"
    echo "4. Konfigurasi Password/Key Auth"
    echo "5. Konfigurasi Enkripsi"
    echo "6. Konfigurasi Session & Timeout"
    echo "7. Nonaktifkan Fitur Tidak Diperlukan"
    echo "8. Konfigurasi Logging"
    echo "9. Batasi Akses User"
    echo "10. Setup Banner"
    echo "11. Setup Fail2Ban"
    echo "12. Regenerate Host Keys"
    echo "13. Setup SSH Key Auth"
    echo "14. Validasi Konfigurasi"
    echo "15. Restart SSH Service"
    echo "0. Keluar"
    echo "======================================"
    read -r -p "Pilih opsi [0-15]: " CHOICE
}

# Hardening penuh
full_hardening() {
    backup_config
    change_ssh_port
    disable_root_login
    disable_password_auth
    configure_crypto
    configure_session
    disable_unused_features
    configure_logging
    configure_user_access
    configure_banner
    setup_fail2ban
    regenerate_host_keys
    setup_ssh_key
    
    if validate_config; then
        restart_ssh
        show_summary
    else
        error "Konfigurasi tidak valid! Mengembalikan backup..."
        local LATEST_BACKUP
        LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/sshd_config.backup.* 2>/dev/null | head -1)
        if [[ -n "$LATEST_BACKUP" ]]; then
            cp "$LATEST_BACKUP" "$SSHD_CONFIG"
            log "Backup dikembalikan: $LATEST_BACKUP"
        fi
    fi
}

# ============================================================
# MAIN
# ============================================================

main() {
    check_root
    
    # Inisialisasi log
    echo "=== SSH Hardening Log - $(date) ===" > "$LOG_FILE"
    
    if [[ "$1" == "--auto" ]]; then
        # Mode otomatis tanpa menu
        NEW_PORT=2222
        full_hardening
    else
        # Mode interaktif
        while true; do
            show_menu
            case $CHOICE in
                1)  backup_config; full_hardening ;;
                2)  backup_config; change_ssh_port ;;
                3)  backup_config; disable_root_login ;;
                4)  backup_config; disable_password_auth ;;
                5)  backup_config; configure_crypto ;;
                6)  backup_config; configure_session ;;
                7)  backup_config; disable_unused_features ;;
                8)  backup_config; configure_logging ;;
                9)  backup_config; configure_user_access ;;
                10) backup_config; configure_banner ;;
                11) setup_fail2ban ;;
                12) backup_config; regenerate_host_keys ;;
                13) setup_ssh_key ;;
                14) validate_config ;;
                15) restart_ssh ;;
                0)  
                    log "Script selesai"
                    echo -e "${GREEN}Terima kasih!${NC}"
                    exit 0 
                    ;;
                *)  
                    error "Pilihan tidak valid!" 
                    ;;
            esac
            
            echo ""
            read -r -p "Tekan Enter untuk melanjutkan..."
        done
    fi
}

# Jalankan script
main "$@"
