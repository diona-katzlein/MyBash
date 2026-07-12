#!/bin/bash

# ============================================================
# CLOUDFLARE DNS & TUNNEL MANAGER (Simple v1-B)
# Author: IsekaiID (https://github.com/diona-katzlein)
# Description: Script sederhana untuk mengelola Cloudflare DNS & Tunnel
# ============================================================

# ==========================================
# KONFIGURASI (ISI DENGAN DATA ANDA)
# ==========================================
CF_API_TOKEN="YOUR_CLOUDFLARE_API_TOKEN"
CF_ACCOUNT_ID="YOUR_ACCOUNT_ID"
CF_ZONE_ID="YOUR_ZONE_ID"

# Warna untuk output terminal
GREEN='\033[0;32m'
RED='\033[0;31'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Cek dependency
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: 'jq' belum terinstal. Silakan install terlebih dahulu (apt install jq / yum install jq).${NC}"
    exit 1
fi

# ==========================================
# FUNGSI 1: BUAT DNS RECORD
# ==========================================
create_dns() {
    echo -e "\n${YELLOW}=== BUAT DNS RECORD (SUBDOMAIN) ===${NC}"
    local subdomain
    read -r -p "Masukkan Nama Subdomain (contoh: app.domain.com): " subdomain
    local target_ip
    read -r -p "Masukkan IP Public / Target: " target_ip
    
    echo "Pilih Mode DNS:"
    echo "1) Proxied (Orange Cloud - Dengan CDN & Security)"
    echo "2) DNS Only (Grey Cloud - Langsung ke IP)"
    local dns_mode
    read -r -p "Pilihan (1/2): " dns_mode

    local proxied
    local ttl
    if [ "$dns_mode" == "1" ]; then
        proxied="true"
        ttl=1 # TTL harus 1 (Auto) jika proxied
    else
        proxied="false"
        ttl=1 # Bisa diubah ke angka (120-86400) jika DNS Only, tapi 1 (Auto) lebih aman
    fi

    echo -e "\n${YELLOW}Membuat DNS Record...${NC}"
    
    local response
    response=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{
            \"type\": \"A\",
            \"name\": \"$subdomain\",
            \"content\": \"$target_ip\",
            \"ttl\": $ttl,
            \"proxied\": $proxied
        }")

    local success
    success=$(echo "$response" | jq -r '.success')

    if [ "$success" == "true" ]; then
        echo -e "${GREEN}Sukses! DNS Record untuk $subdomain telah dibuat.${NC}"
    else
        echo -e "${RED}Gagal membuat DNS Record.${NC}"
        echo -e "${RED}Error: $(echo "$response" | jq -r '.errors[0].message')${NC}"
    fi
}

# ==========================================
# FUNGSI 2: TAMBAH APLIKASI KE TUNNEL
# ==========================================
add_tunnel_app() {
    echo -e "\n${YELLOW}=== TAMBAH APLIKASI KE ZERO TRUST TUNNEL ===${NC}"
    local tunnel_id
    read -r -p "Masukkan Tunnel ID: " tunnel_id
    local hostname
    read -r -p "Masukkan Hostname (Harus sama dengan subdomain DNS): " hostname
    
    echo "Pilih Jenis Service:"
    echo "1) http   (Untuk Web HTTP biasa)"
    echo "2) https  (Untuk Web HTTPS / SSL di backend)"
    echo "3) tcp    (Untuk database, SSH, RDP, dll)"
    echo "4) ssh    (Khusus SSH)"
    local svc_choice
    read -r -p "Pilihan (1-4): " svc_choice

    local svc_type
    case $svc_choice in
        1) svc_type="http" ;;
        2) svc_type="https" ;;
        3) svc_type="tcp" ;;
        4) svc_type="ssh" ;;
        *) echo -e "${RED}Pilihan tidak valid!${NC}"; return ;;
    esac

    local svc_url
    read -r -p "Masukkan URL Service (contoh: localhost:8080 atau 192.168.1.10:3306): " svc_url
    local full_service_url="${svc_type}://${svc_url}"

    echo -e "\n${YELLOW}Mengambil konfigurasi Tunnel saat ini...${NC}"
    
    # 1. Ambil konfigurasi tunnel yang sedang berjalan
    local current_config
    current_config=$(curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/cfd_tunnel/$tunnel_id/configurations" \
        -H "Authorization: Bearer $CF_API_TOKEN")

    # Cek apakah tunnel ada
    if [ "$(echo "$current_config" | jq -r '.success')" != "true" ]; then
        echo -e "${RED}Gagal mengambil konfigurasi. Pastikan Tunnel ID benar.${NC}"
        return
    fi

    # 2. Modifikasi JSON menggunakan jq
    # Aturan Cloudflare: Rule terakhir HARUS berupa catch-all (http_status:404)
    local new_config
    new_config=$(echo "$current_config" | jq --arg host "$hostname" --arg svc "$full_service_url" '
        .result.config.ingress |= (
            map(select(.service != "http_status:404")) + 
            [{"hostname": $host, "service": $svc, "originRequest": {"noTLSVerify": true}}] + 
            [{"service": "http_status:404"}]
        )
    ')

    echo -e "${YELLOW}Mengupdate konfigurasi Tunnel...${NC}"

    # 3. Push konfigurasi baru ke Cloudflare
    local update_response
    update_response=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/cfd_tunnel/$tunnel_id/configurations" \
        -H "Authorization: Bearer $CF_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "$new_config")

    local success
    success=$(echo "$update_response" | jq -r '.success')

    if [ "$success" == "true" ]; then
        echo -e "${GREEN}Sukses! Aplikasi $hostname telah ditambahkan ke Tunnel.${NC}"
        echo -e "${YELLOW}Catatan: cloudflared akan otomatis menarik konfigurasi baru ini dalam beberapa detik.${NC}"
    else
        echo -e "${RED}Gagal mengupdate konfigurasi Tunnel.${NC}"
        echo -e "${RED}Error: $(echo "$update_response" | jq -r '.errors[0].message')${NC}"
    fi
}

# ==========================================
# MENU UTAMA
# ==========================================
clear
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN} CLOUDFLARE DNS & TUNNEL MANAGER ${NC}"
echo -e "${GREEN}======================================${NC}"
echo "1) Buat Subdomain DNS (A Record)"
echo "2) Tambah Aplikasi ke Zero Trust Tunnel"
echo "3) Keluar"
echo ""
read -r -p "Pilih Menu (1-3): " menu_choice

case $menu_choice in
    1) create_dns ;;
    2) add_tunnel_app ;;
    3) exit 0 ;;
    *) echo -e "${RED}Pilihan tidak valid!${NC}" ;;
esac
