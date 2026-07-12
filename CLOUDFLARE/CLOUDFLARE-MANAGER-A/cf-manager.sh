#!/bin/bash
# ============================================================
# Cloudflare DNS & Zero Trust Tunnel Manager
# Author  : IsekaiID (https://github.com/diona-katzlein)
# Version : 2.0
# ============================================================

set -euo pipefail

# ─────────────────────────────────────────────
# Load Config
# ─────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"

if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
else
    echo "❌ File config.env tidak ditemukan!"
    exit 1
fi

# ─────────────────────────────────────────────
# Warna & Format
# ─────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# ─────────────────────────────────────────────
# Helper Functions
# ─────────────────────────────────────────────
log_info()    { echo -e "${GREEN}[✔]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[⚠]${NC} $1"; }
log_error()   { echo -e "${RED}[✘]${NC} $1"; }
log_step()    { echo -e "${CYAN}[➤]${NC} $1"; }
log_title()   { echo -e "\n${BOLD}${PURPLE}═══ $1 ═══${NC}\n"; }

separator() {
    echo -e "${BLUE}────────────────────────────────────────────────────${NC}"
}

pause() {
    echo ""
    read -r -p "Tekan [Enter] untuk melanjutkan..."
}

# ─────────────────────────────────────────────
# API Functions
# ─────────────────────────────────────────────
cf_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"
    local response

    if [[ -n "$data" ]]; then
        response=$(curl -s -X "$method" \
            "https://api.cloudflare.com/client/v4${endpoint}" \
            -H "Authorization: Bearer ${CF_API_TOKEN}" \
            -H "Content-Type: application/json" \
            --data "$data")
    else
        response=$(curl -s -X "$method" \
            "https://api.cloudflare.com/client/v4${endpoint}" \
            -H "Authorization: Bearer ${CF_API_TOKEN}" \
            -H "Content-Type: application/json")
    fi

    echo "$response"
}

check_success() {
    local response="$1"
    local success
    success=$(echo "$response" | grep -o '"success":true' || true)
    if [[ -n "$success" ]]; then
        return 0
    else
        return 1
    fi
}

# ─────────────────────────────────────────────
# Validasi Konfigurasi
# ─────────────────────────────────────────────
validate_config() {
    local errors=0

    [[ -z "${CF_API_TOKEN:-}" ]] && { log_error "CF_API_TOKEN belum diset"; ((errors++)); }
    [[ -z "${CF_ZONE_ID:-}" ]]   && { log_error "CF_ZONE_ID belum diset"; ((errors++)); }
    [[ -z "${CF_ACCOUNT_ID:-}" ]] && { log_error "CF_ACCOUNT_ID belum diset"; ((errors++)); }
    [[ -z "${CF_DOMAIN:-}" ]]    && { log_error "CF_DOMAIN belum diset"; ((errors++)); }

    if [[ $errors -gt 0 ]]; then
        log_error "Silakan lengkapi config.env terlebih dahulu"
        exit 1
    fi
}

# ─────────────────────────────────────────────
# Cek Dependencies
# ─────────────────────────────────────────────
check_deps() {
    local deps=("curl" "jq" "grep" "awk")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Dependencies tidak ditemukan: ${missing[*]}"
        log_step "Install dengan: apt install ${missing[*]} -y"
        exit 1
    fi
}

# ═══════════════════════════════════════════════
# MODUL 1: DNS MANAGEMENT
# ═══════════════════════════════════════════════

# ─────────────────────────────────────────────
# Tambah DNS Record
# ─────────────────────────────────────────────
add_dns_record() {
    log_title "TAMBAH DNS RECORD"

    # Input subdomain
    local subdomain
    read -r -p "$(echo -e "${CYAN}Masukkan subdomain ${WHITE}[contoh: app, www, api]${CYAN}: ${NC}")" subdomain
    if [[ -z "$subdomain" ]]; then
        log_error "Subdomain tidak boleh kosong!"
        return 1
    fi

    # Full hostname
    local full_hostname="${subdomain}.${CF_DOMAIN}"

    # Pilih tipe record
    echo ""
    echo -e "${WHITE}Pilih Tipe Record:${NC}"
    echo -e "  ${GREEN}1)${NC} A     - IPv4 Address"
    echo -e "  ${GREEN}2)${NC} AAAA  - IPv6 Address"
    echo -e "  ${GREEN}3)${NC} CNAME - Alias"
    echo -e "  ${GREEN}4)${NC} MX    - Mail Exchange"
    echo -e "  ${GREEN}5)${NC} TXT   - Text Record"
    echo -e "  ${GREEN}6)${NC} SRV   - Service Record"
    separator

    local type_choice
    read -r -p "Pilihan [1-6]: " type_choice

    local record_type
    case "$type_choice" in
        1) record_type="A" ;;
        2) record_type="AAAA" ;;
        3) record_type="CNAME" ;;
        4) record_type="MX" ;;
        5) record_type="TXT" ;;
        6) record_type="SRV" ;;
        *) log_error "Pilihan tidak valid!"; return 1 ;;
    esac

    # Input berdasarkan tipe
    local record_content=""
    local priority=""
    local ttl=1
    local proxied=false
    local proxy_choice

    # SRV Specifics
    local srv_service=""
    local srv_proto=""
    local srv_priority=""
    local srv_weight=""
    local srv_port=""

    case "$record_type" in
        A|AAAA)
            read -r -p "$(echo -e "${CYAN}Masukkan IP Address: ${NC}")" record_content
            if [[ -z "$record_content" ]]; then
                log_error "IP Address tidak boleh kosong!"
                return 1
            fi

            # Validasi format IP sederhana
            if [[ "$record_type" == "A" ]]; then
                if ! echo "$record_content" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
                    log_warn "Format IP mungkin tidak valid, tetap melanjutkan..."
                fi
            fi

            # Mode Proxy
            echo ""
            echo -e "${WHITE}Mode DNS:${NC}"
            echo -e "  ${GREEN}1)${NC} 🟠 Proxied  (melalui Cloudflare - CDN + Protection)"
            echo -e "  ${GREEN}2)${NC} ⚫ DNS Only  (langsung ke IP - tanpa proxy)"
            read -r -p "Pilihan [1/2]: " proxy_choice
            [[ "$proxy_choice" == "1" ]] && proxied=true || proxied=false
            ;;

        CNAME)
            read -r -p "$(echo -e "${CYAN}Masukkan Target ${WHITE}[contoh: example.com]${CYAN}: ${NC}")" record_content
            echo ""
            echo -e "${WHITE}Mode DNS:${NC}"
            echo -e "  ${GREEN}1)${NC} 🟠 Proxied"
            echo -e "  ${GREEN}2)${NC} ⚫ DNS Only"
            read -r -p "Pilihan [1/2]: " proxy_choice
            [[ "$proxy_choice" == "1" ]] && proxied=true || proxied=false
            ;;

        MX)
            read -r -p "$(echo -e "${CYAN}Masukkan Mail Server ${WHITE}[contoh: mail.example.com]${CYAN}: ${NC}")" record_content
            read -r -p "$(echo -e "${CYAN}Masukkan Priority ${WHITE}[default: 10]${CYAN}: ${NC}")" priority
            [[ -z "$priority" ]] && priority=10
            proxied=false
            ;;

        TXT)
            read -r -p "$(echo -e "${CYAN}Masukkan Content TXT: ${NC}")" record_content
            proxied=false
            ;;

        SRV)
            log_warn "SRV Record membutuhkan format khusus"
            read -r -p "$(echo -e "${CYAN}Service ${WHITE}[contoh: _sip]${CYAN}: ${NC}")" srv_service
            read -r -p "$(echo -e "${CYAN}Protocol ${WHITE}[_tcp/_udp]${CYAN}: ${NC}")" srv_proto
            read -r -p "$(echo -e "${CYAN}Priority ${WHITE}[default: 1]${CYAN}: ${NC}")" srv_priority
            read -r -p "$(echo -e "${CYAN}Weight ${WHITE}[default: 1]${CYAN}: ${NC}")" srv_weight
            read -r -p "$(echo -e "${CYAN}Port: ${NC}")" srv_port
            read -r -p "$(echo -e "${CYAN}Target ${WHITE}[contoh: server.example.com]${CYAN}: ${NC}")" record_content

            [[ -z "$srv_priority" ]] && srv_priority=1
            [[ -z "$srv_weight" ]] && srv_weight=1
            ;;
    esac

    # TTL
    echo ""
    echo -e "${WHITE}TTL:${NC}"
    echo -e "  ${GREEN}1)${NC} Auto (Recommended)"
    echo -e "  ${GREEN}2)${NC} 60   detik"
    echo -e "  ${GREEN}3)${NC} 300  detik (5 menit)"
    echo -e "  ${GREEN}4)${NC} 3600 detik (1 jam)"
    local ttl_choice
    read -r -p "Pilihan [1-4]: " ttl_choice

    case "$ttl_choice" in
        1) ttl=1 ;;
        2) ttl=60 ;;
        3) ttl=300 ;;
        4) ttl=3600 ;;
        *) ttl=1 ;;
    esac

    # Konfirmasi
    separator
    echo -e "${WHITE}Konfirmasi DNS Record:${NC}"
    echo -e "  ${CYAN}Hostname  :${NC} ${full_hostname}"
    echo -e "  ${CYAN}Tipe      :${NC} ${record_type}"
    echo -e "  ${CYAN}Content   :${NC} ${record_content}"
    [[ -n "$priority" ]] && echo -e "  ${CYAN}Priority  :${NC} ${priority}"
    echo -e "  ${CYAN}TTL       :${NC} ${ttl}"
    echo -e "  ${CYAN}Proxied   :${NC} ${proxied}"
    separator

    local confirm
    read -r -p "Lanjutkan? [y/N]: " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && { log_warn "Dibatalkan"; return 0; }

    # Build JSON payload
    local payload
    if [[ "$record_type" == "MX" ]]; then
        payload=$(jq -n \
            --arg type "$record_type" \
            --arg name "$full_hostname" \
            --arg content "$record_content" \
            --argjson priority "${priority}" \
            --argjson ttl "$ttl" \
            '{type: $type, name: $name, content: $content, priority: $priority, ttl: $ttl}')

    elif [[ "$record_type" == "SRV" ]]; then
        payload=$(jq -n \
            --arg type "$record_type" \
            --arg service "$srv_service" \
            --arg proto "$srv_proto" \
            --arg name "$subdomain" \
            --argjson priority "${srv_priority}" \
            --argjson weight "${srv_weight}" \
            --argjson port "${srv_port}" \
            --arg target "$record_content" \
            --argjson ttl "$ttl" \
            '{
                type: $type,
                data: {
                    service: $service,
                    proto: $proto,
                    name: $name,
                    priority: $priority,
                    weight: $weight,
                    port: $port,
                    target: $target
                },
                ttl: $ttl
            }')
    else
        payload=$(jq -n \
            --arg type "$record_type" \
            --arg name "$full_hostname" \
            --arg content "$record_content" \
            --argjson proxied "$proxied" \
            --argjson ttl "$ttl" \
            '{type: $type, name: $name, content: $content, proxied: $proxied, ttl: $ttl}')
    fi

    # Kirim request
    log_step "Membuat DNS record..."
    local response
    response=$(cf_api "POST" "/zones/${CF_ZONE_ID}/dns_records" "$payload")

    if check_success "$response"; then
        local record_id
        record_id=$(echo "$response" | jq -r '.result.id')
        log_info "DNS Record berhasil dibuat!"
        log_info "Record ID: ${record_id}"
        log_info "Hostname : ${full_hostname}"
        log_info "Mode     : $([ "$proxied" == "true" ] && echo "🟠 Proxied" || echo "⚫ DNS Only")"
    else
        local error_msg
        error_msg=$(echo "$response" | jq -r '.errors[0].message // "Unknown error"')
        log_error "Gagal membuat DNS record: ${error_msg}"
        echo "$response" | jq '.errors' 2>/dev/null || true
    fi
}

# ─────────────────────────────────────────────
# List DNS Records
# ─────────────────────────────────────────────
list_dns_records() {
    log_title "DAFTAR DNS RECORDS"

    log_step "Mengambil data DNS records..."
    local response
    response=$(cf_api "GET" "/zones/${CF_ZONE_ID}/dns_records?per_page=100")

    if ! check_success "$response"; then
        log_error "Gagal mengambil data DNS records"
        return 1
    fi

    local total
    total=$(echo "$response" | jq '.result | length')
    log_info "Total Records: ${total}"
    separator

    # Header tabel
    printf "${BOLD}${WHITE}%-36s %-8s %-35s %-20s %-8s${NC}\n" \
        "ID" "TIPE" "NAMA" "CONTENT" "PROXY"
    separator

    echo "$response" | jq -r '.result[] | [.id, .type, .name, .content, .proxied] | @tsv' | \
    while IFS=$'\t' read -r id type name content proxied; do
        local proxy_icon="⚫"
        [[ "$proxied" == "true" ]] && proxy_icon="🟠"

        # Truncate panjang string
        [[ ${#name} -gt 35 ]] && name="${name:0:32}..."
        [[ ${#content} -gt 20 ]] && content="${content:0:17}..."

        printf "%-36s ${CYAN}%-8s${NC} %-35s ${GREEN}%-20s${NC} %s\n" \
            "$id" "$type" "$name" "$content" "$proxy_icon"
    done
}

# ─────────────────────────────────────────────
# Hapus DNS Record
# ─────────────────────────────────────────────
delete_dns_record() {
    log_title "HAPUS DNS RECORD"

    # Tampilkan list dulu
    list_dns_records
    separator

    local record_id
    read -r -p "$(echo -e "${CYAN}Masukkan Record ID yang akan dihapus: ${NC}")" record_id
    if [[ -z "$record_id" ]]; then
        log_error "Record ID tidak boleh kosong!"
        return 1
    fi

    local confirm
    read -r -p "$(echo -e "${RED}Yakin hapus record ini? ${WHITE}[y/N]${RED}: ${NC}")" confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && { log_warn "Dibatalkan"; return 0; }

    log_step "Menghapus DNS record..."
    local response
    response=$(cf_api "DELETE" "/zones/${CF_ZONE_ID}/dns_records/${record_id}")

    if check_success "$response"; then
        log_info "DNS Record berhasil dihapus!"
    else
        local error_msg
        error_msg=$(echo "$response" | jq -r '.errors[0].message // "Unknown error"')
        log_error "Gagal menghapus: ${error_msg}"
    fi
}

# ─────────────────────────────────────────────
# Update Mode Proxy DNS
# ─────────────────────────────────────────────
toggle_proxy_dns() {
    log_title "TOGGLE PROXY DNS RECORD"

    list_dns_records
    separator

    local record_id
    read -r -p "$(echo -e "${CYAN}Masukkan Record ID: ${NC}")" record_id
    if [[ -z "$record_id" ]]; then
        log_error "Record ID tidak boleh kosong!"
        return 1
    fi

    echo ""
    echo -e "${WHITE}Ubah mode menjadi:${NC}"
    echo -e "  ${GREEN}1)${NC} 🟠 Proxied (melalui Cloudflare)"
    echo -e "  ${GREEN}2)${NC} ⚫ DNS Only (langsung ke origin)"
    local proxy_choice
    read -r -p "Pilihan [1/2]: " proxy_choice

    local proxied
    [[ "$proxy_choice" == "1" ]] && proxied=true || proxied=false

    local payload
    payload=$(jq -n --argjson proxied "$proxied" '{proxied: $proxied}')

    log_step "Mengupdate mode proxy..."
    local response
    response=$(cf_api "PATCH" "/zones/${CF_ZONE_ID}/dns_records/${record_id}" "$payload")

    if check_success "$response"; then
        log_info "Mode proxy berhasil diupdate!"
        log_info "Mode: $([ "$proxied" == "true" ] && echo "🟠 Proxied" || echo "⚫ DNS Only")"
    else
        local error_msg
        error_msg=$(echo "$response" | jq -r '.errors[0].message // "Unknown error"')
        log_error "Gagal update: ${error_msg}"
    fi
}

# ═══════════════════════════════════════════════
# MODUL 2: ZERO TRUST TUNNEL MANAGEMENT
# ═══════════════════════════════════════════════

# ─────────────────────────────────────────────
# List Tunnels
# ─────────────────────────────────────────────
list_tunnels() {
    log_title "DAFTAR CLOUDFLARE TUNNELS"

    log_step "Mengambil data tunnels..."
    local response
    response=$(cf_api "GET" "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel?is_deleted=false")

    if ! check_success "$response"; then
        log_error "Gagal mengambil data tunnels"
        return 1
    fi

    local total
    total=$(echo "$response" | jq '.result | length')
    log_info "Total Tunnels: ${total}"
    separator

    printf "${BOLD}${WHITE}%-36s %-25s %-12s %-20s${NC}\n" \
        "ID" "NAMA" "STATUS" "CREATED"
    separator

    echo "$response" | jq -r '.result[] | [.id, .name, .status, .created_at] | @tsv' | \
    while IFS=$'\t' read -r id name status created; do
        local status_icon="⚫"
        local status_color="${RED}"
        [[ "$status" == "healthy" ]] && { status_icon="🟢"; status_color="${GREEN}"; }
        [[ "$status" == "degraded" ]] && { status_icon="🟡"; status_color="${YELLOW}"; }

        created=$(echo "$created" | cut -d'T' -f1)

        printf "%-36s ${CYAN}%-25s${NC} ${status_color}%-12s${NC} %-20s\n" \
            "$id" "$name" "${status_icon} ${status}" "$created"
    done
}

# ─────────────────────────────────────────────
# Tambah Aplikasi ke Tunnel
# ─────────────────────────────────────────────
add_tunnel_app() {
    log_title "TAMBAH APLIKASI KE TUNNEL"

    # Cek tunnel ID
    if [[ -z "${CF_TUNNEL_ID:-}" ]]; then
        list_tunnels
        separator
        read -r -p "$(echo -e "${CYAN}Masukkan Tunnel ID: ${NC}")" CF_TUNNEL_ID
        if [[ -z "$CF_TUNNEL_ID" ]]; then
            log_error "Tunnel ID tidak boleh kosong!"
            return 1
        fi
    fi

    log_info "Tunnel ID: ${CF_TUNNEL_ID}"

    # Pilih jenis aplikasi
    echo ""
    echo -e "${WHITE}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${WHITE}║        JENIS APLIKASI / SERVICE              ║${NC}"
    echo -e "${WHITE}╠══════════════════════════════════════════════╣${NC}"
    echo -e "${WHITE}║  ${GREEN}Web Services:${NC}                               ${WHITE}║${NC}"
    echo -e "${WHITE}║  ${GREEN} 1)${NC} HTTP  - Web App (port 80)              ${WHITE}║${NC}"
    echo -e "${WHITE}║  ${GREEN} 2)${NC} HTTPS - Web App Secure (port 443)      ${WHITE}║${NC}"
    echo -e "${WHITE}║                                              ║${NC}"
    echo -e "${WHITE}║  ${CYAN}Remote Access:${NC}                              ${WHITE}║${NC}"
    echo -e "${WHITE}║  ${CYAN} 3)${NC} SSH   - Secure Shell (port 22)         ${WHITE}║${NC}"
    echo -e "${WHITE}║  ${CYAN} 4)${NC} RDP   - Remote Desktop (port 3389)     ${WHITE}║${NC}"
    echo -e "${WHITE}║  ${CYAN} 5)${NC} VNC   - Virtual Network Computing       ${WHITE}║${NC}"
    echo -e "${WHITE}║                                              ║${NC}"
    echo -e "${WHITE}║  ${YELLOW}Database:${NC}                                   ${WHITE}║${NC}"
    echo -e "${WHITE}║  ${YELLOW} 6)${NC} MySQL/MariaDB (port 3306)             ${WHITE}║${NC}"
    echo -e "${WHITE}║  ${YELLOW} 7)${NC} PostgreSQL    (port 5432)             ${WHITE}║${NC}"
    echo -e "${WHITE}║  ${YELLOW} 8)${NC} MongoDB       (port 27017)            ${WHITE}║${NC}"
    echo -e "${WHITE}║  ${YELLOW} 9)${NC} Redis         (port 6379)             ${WHITE}║${NC}"
    echo -e "${WHITE}║                                              ║${NC}"
    echo -e "${WHITE}║  ${PURPLE}Monitoring & Tools:${NC}                         ${WHITE}║${NC}"
    echo -e "${WHITE}║  ${PURPLE}10)${NC} Grafana       (port 3000)             ${WHITE}║${NC}"
    echo -e "${WHITE}║  ${PURPLE}11)${NC} Prometheus    (port 9090)             ${WHITE}║${NC}"
    echo -e "${WHITE}║  ${PURPLE}12)${NC} Portainer     (port 9000)             ${WHITE}║${NC}"
    echo -e "${WHITE}║  ${PURPLE}13)${NC} Uptime Kuma   (port 3001)             ${WHITE}║${NC}"
    echo -e "${WHITE}║                                              ║${NC}"
    echo -e "${WHITE}║  ${RED}Custom:${NC}                                     ${WHITE}║${NC}"
    echo -e "${WHITE}║  ${RED}14)${NC} TCP   - Custom TCP Service              ${WHITE}║${NC}"
    echo -e "${WHITE}║  ${RED}15)${NC} UDP   - Custom UDP Service              ${WHITE}║${NC}"
    echo -e "${WHITE}║  ${RED}16)${NC} Custom (HTTP/HTTPS dengan port custom)  ${WHITE}║${NC}"
    echo -e "${WHITE}╚══════════════════════════════════════════════╝${NC}"
    separator

    local app_choice
    read -r -p "Pilihan [1-16]: " app_choice

    # Set default values berdasarkan pilihan
    local service_type
    local default_port
    local app_name

    case "$app_choice" in
        1)  service_type="http";  default_port=80;    app_name="Web HTTP" ;;
        2)  service_type="https"; default_port=443;   app_name="Web HTTPS" ;;
        3)  service_type="ssh";   default_port=22;    app_name="SSH" ;;
        4)  service_type="rdp";   default_port=3389;  app_name="RDP" ;;
        5)  service_type="vnc";   default_port=5900;  app_name="VNC" ;;
        6)  service_type="tcp";   default_port=3306;  app_name="MySQL" ;;
        7)  service_type="tcp";   default_port=5432;  app_name="PostgreSQL" ;;
        8)  service_type="tcp";   default_port=27017; app_name="MongoDB" ;;
        9)  service_type="tcp";   default_port=6379;  app_name="Redis" ;;
        10) service_type="http";  default_port=3000;  app_name="Grafana" ;;
        11) service_type="http";  default_port=9090;  app_name="Prometheus" ;;
        12) service_type="https"; default_port=9000;  app_name="Portainer" ;;
        13) service_type="http";  default_port=3001;  app_name="Uptime Kuma" ;;
        14) service_type="tcp";   default_port="";    app_name="TCP Custom" ;;
        15) service_type="udp";   default_port="";    app_name="UDP Custom" ;;
        16) service_type="http";  default_port=80;    app_name="Custom HTTP" ;;
        *)  log_error "Pilihan tidak valid!"; return 1 ;;
    esac

    echo ""
    log_info "Jenis Aplikasi: ${app_name}"

    # Input hostname (subdomain)
    local subdomain
    read -r -p "$(echo -e "${CYAN}Masukkan Subdomain ${WHITE}[contoh: app, ssh, db]${CYAN}: ${NC}")" subdomain
    if [[ -z "$subdomain" ]]; then
        log_error "Subdomain tidak boleh kosong!"
        return 1
    fi
    local full_hostname="${subdomain}.${CF_DOMAIN}"

    # Input origin service
    local origin_host
    read -r -p "$(echo -e "${CYAN}Masukkan Origin Host ${WHITE}[default: localhost]${CYAN}: ${NC}")" origin_host
    [[ -z "$origin_host" ]] && origin_host="localhost"

    # Input port
    local origin_port
    if [[ -n "$default_port" ]]; then
        read -r -p "$(echo -e "${CYAN}Masukkan Port ${WHITE}[default: ${default_port}]${CYAN}: ${NC}")" origin_port
        [[ -z "$origin_port" ]] && origin_port="$default_port"
    else
        read -r -p "$(echo -e "${CYAN}Masukkan Port: ${NC}")" origin_port
        if [[ -z "$origin_port" ]]; then
            log_error "Port tidak boleh kosong untuk custom service!"
            return 1
        fi
    fi

    # Build service URL
    local service_url=""
    case "$service_type" in
        http)  service_url="http://${origin_host}:${origin_port}" ;;
        https) service_url="https://${origin_host}:${origin_port}" ;;
        ssh)   service_url="ssh://${origin_host}:${origin_port}" ;;
        rdp)   service_url="rdp://${origin_host}:${origin_port}" ;;
        vnc)   service_url="vnc://${origin_host}:${origin_port}" ;;
        tcp)   service_url="tcp://${origin_host}:${origin_port}" ;;
        udp)   service_url="udp://${origin_host}:${origin_port}" ;;
    esac

    # Opsi tambahan untuk HTTPS
    local no_tls_verify=false
    local skip_tls
    if [[ "$service_type" == "https" ]]; then
        echo ""
        read -r -p "$(echo -e "${YELLOW}Skip TLS verify untuk origin? ${WHITE}[y/N]${YELLOW}: ${NC}")" skip_tls
        [[ "$skip_tls" == "y" || "$skip_tls" == "Y" ]] && no_tls_verify=true
    fi

    # Ambil config tunnel yang ada
    log_step "Mengambil konfigurasi tunnel saat ini..."
    local tunnel_config
    tunnel_config=$(cf_api "GET" "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${CF_TUNNEL_ID}/configurations")

    # Parse ingress rules yang ada
    local existing_ingress
    existing_ingress=$(echo "$tunnel_config" | jq '.result.config.ingress // []')

    # Hapus catch-all rule jika ada
    local filtered_ingress
    filtered_ingress=$(echo "$existing_ingress" | jq '[.[] | select(.service != "http_status:404")]')

    # Build ingress rule baru
    local new_rule
    if [[ "$no_tls_verify" == "true" ]]; then
        new_rule=$(jq -n \
            --arg hostname "$full_hostname" \
            --arg service "$service_url" \
            '{
                hostname: $hostname,
                service: $service,
                originRequest: {
                    noTLSVerify: true
                }
            }')
    else
        # Tambahan opsi spesifik per tipe
        case "$service_type" in
            ssh)
                new_rule=$(jq -n \
                    --arg hostname "$full_hostname" \
                    --arg service "$service_url" \
                    '{
                        hostname: $hostname,
                        service: $service,
                        originRequest: {
                            connectTimeout: 30
                        }
                    }')
                ;;
            tcp|udp)
                new_rule=$(jq -n \
                    --arg hostname "$full_hostname" \
                    --arg service "$service_url" \
                    '{
                        hostname: $hostname,
                        service: $service,
                        originRequest: {
                            proxyType: "socks"
                        }
                    }')
                ;;
            *)
                new_rule=$(jq -n \
                    --arg hostname "$full_hostname" \
                    --arg service "$service_url" \
                    '{hostname: $hostname, service: $service}')
                ;;
        esac
    fi

    # Gabungkan rules + catch-all
    local catch_all='{"service": "http_status:404"}'
    local new_ingress
    new_ingress=$(echo "$filtered_ingress" | jq --argjson rule "$new_rule" '. + [$rule]')
    new_ingress=$(echo "$new_ingress" | jq --argjson catchall "$catch_all" '. + [$catchall]')

    # Build final payload
    local final_payload
    final_payload=$(jq -n \
        --argjson ingress "$new_ingress" \
        '{"config": {"ingress": $ingress}}')

    # Konfirmasi
    separator
    echo -e "${WHITE}Konfirmasi Tunnel Route:${NC}"
    echo -e "  ${CYAN}Hostname  :${NC} ${full_hostname}"
    echo -e "  ${CYAN}Service   :${NC} ${service_url}"
    echo -e "  ${CYAN}App Type  :${NC} ${app_name}"
    echo -e "  ${CYAN}Tunnel ID :${NC} ${CF_TUNNEL_ID}"
    separator

    local confirm
    read -r -p "Lanjutkan? [y/N]: " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && { log_warn "Dibatalkan"; return 0; }

    # Update tunnel config
    log_step "Mengupdate konfigurasi tunnel..."
    local response
    response=$(cf_api "PUT" \
        "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${CF_TUNNEL_ID}/configurations" \
        "$final_payload")

    if check_success "$response"; then
        log_info "Aplikasi berhasil ditambahkan ke tunnel!"
        log_info "Route: ${full_hostname} → ${service_url}"

        # Otomatis buat DNS record CNAME
        echo ""
        local auto_dns
        read -r -p "$(echo -e "${CYAN}Otomatis buat DNS CNAME record? ${WHITE}[Y/n]${CYAN}: ${NC}")" auto_dns
        if [[ "$auto_dns" != "n" && "$auto_dns" != "N" ]]; then
            create_tunnel_dns "$subdomain" "$CF_TUNNEL_ID"
        fi
    else
        local error_msg
        error_msg=$(echo "$response" | jq -r '.errors[0].message // "Unknown error"')
        log_error "Gagal update tunnel: ${error_msg}"
        echo "$response" | jq '.errors' 2>/dev/null || true
    fi
}

# ─────────────────────────────────────────────
# Buat DNS CNAME untuk Tunnel
# ─────────────────────────────────────────────
create_tunnel_dns() {
    local subdomain="${1:-}"
    local tunnel_id="${2:-$CF_TUNNEL_ID}"

    if [[ -z "$subdomain" ]]; then
        read -r -p "$(echo -e "${CYAN}Masukkan subdomain: ${NC}")" subdomain
    fi

    local full_hostname="${subdomain}.${CF_DOMAIN}"
    local cname_target="${tunnel_id}.cfargotunnel.com"

    log_step "Membuat DNS CNAME record untuk tunnel..."

    local payload
    payload=$(jq -n \
        --arg name "$full_hostname" \
        --arg content "$cname_target" \
        '{
            type: "CNAME",
            name: $name,
            content: $content,
            proxied: true,
            ttl: 1
        }')

    local response
    response=$(cf_api "POST" "/zones/${CF_ZONE_ID}/dns_records" "$payload")

    if check_success "$response"; then
        log_info "DNS CNAME berhasil dibuat!"
        log_info "${full_hostname} → ${cname_target}"
        log_info "Mode: 🟠 Proxied (Required untuk Tunnel)"
    else
        local error_msg
        error_msg=$(echo "$response" | jq -r '.errors[0].message // "Unknown error"')
        log_warn "DNS mungkin sudah ada atau gagal: ${error_msg}"
    fi
}

# ─────────────────────────────────────────────
# List Tunnel Routes / Ingress
# ─────────────────────────────────────────────
list_tunnel_routes() {
    log_title "DAFTAR TUNNEL ROUTES"

    if [[ -z "${CF_TUNNEL_ID:-}" ]]; then
        list_tunnels
        separator
        read -r -p "$(echo -e "${CYAN}Masukkan Tunnel ID: ${NC}")" CF_TUNNEL_ID
    fi

    log_step "Mengambil konfigurasi tunnel..."
    local response
    response=$(cf_api "GET" "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${CF_TUNNEL_ID}/configurations")

    if ! check_success "$response"; then
        log_error "Gagal mengambil konfigurasi tunnel"
        return 1
    fi

    local total
    total=$(echo "$response" | jq '.result.config.ingress | length')
    log_info "Total Routes: ${total}"
    separator

    printf "${BOLD}${WHITE}%-45s %-40s${NC}\n" "HOSTNAME" "SERVICE"
    separator

    echo "$response" | jq -r '.result.config.ingress[] | [.hostname // "catch-all", .service] | @tsv' | \
    while IFS=$'\t' read -r hostname service; do
        if [[ "$hostname" == "catch-all" ]]; then
            printf "${YELLOW}%-45s %-40s${NC}\n" "⚡ [catch-all]" "$service"
        else
            printf "${CYAN}%-45s${NC} ${GREEN}%-40s${NC}\n" "$hostname" "$service"
        fi
    done
}

# ─────────────────────────────────────────────
# Hapus Route dari Tunnel
# ─────────────────────────────────────────────
delete_tunnel_route() {
    log_title "HAPUS ROUTE DARI TUNNEL"

    if [[ -z "${CF_TUNNEL_ID:-}" ]]; then
        list_tunnels
        separator
        read -r -p "$(echo -e "${CYAN}Masukkan Tunnel ID: ${NC}")" CF_TUNNEL_ID
    fi

    # Tampilkan routes
    list_tunnel_routes
    separator

    local del_hostname
    read -r -p "$(echo -e "${CYAN}Masukkan hostname yang akan dihapus: ${NC}")" del_hostname

    if [[ -z "$del_hostname" ]]; then
        log_error "Hostname tidak boleh kosong!"
        return 1
    fi

    local confirm
    read -r -p "$(echo -e "${RED}Yakin hapus route ${del_hostname}? ${WHITE}[y/N]${RED}: ${NC}")" confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && { log_warn "Dibatalkan"; return 0; }

    # Ambil config yang ada
    local tunnel_config
    tunnel_config=$(cf_api "GET" "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${CF_TUNNEL_ID}/configurations")

    # Filter route yang akan dihapus
    local new_ingress
    new_ingress=$(echo "$tunnel_config" | \
        jq --arg hostname "$del_hostname" \
        '[.result.config.ingress[] | select(.hostname != $hostname)]')

    local final_payload
    final_payload=$(jq -n \
        --argjson ingress "$new_ingress" \
        '{"config": {"ingress": $ingress}}')

    log_step "Menghapus route..."
    local response
    response=$(cf_api "PUT" \
        "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${CF_TUNNEL_ID}/configurations" \
        "$final_payload")

    if check_success "$response"; then
        log_info "Route berhasil dihapus: ${del_hostname}"
    else
        local error_msg
        error_msg=$(echo "$response" | jq -r '.errors[0].message // "Unknown error"')
        log_error "Gagal hapus route: ${error_msg}"
    fi
}

# ─────────────────────────────────────────────
# Buat Tunnel Baru
# ─────────────────────────────────────────────
create_tunnel() {
    log_title "BUAT TUNNEL BARU"

    local tunnel_name
    read -r -p "$(echo -e "${CYAN}Nama Tunnel: ${NC}")" tunnel_name
    if [[ -z "$tunnel_name" ]]; then
        log_error "Nama tunnel tidak boleh kosong!"
        return 1
    fi

    # Generate random secret
    local tunnel_secret
    tunnel_secret=$(openssl rand -hex 32 2>/dev/null || \
        cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 64 | head -n 1)

    local payload
    payload=$(jq -n \
        --arg name "$tunnel_name" \
        --arg secret "$tunnel_secret" \
        '{name: $name, tunnel_secret: $secret}')

    log_step "Membuat tunnel baru..."
    local response
    response=$(cf_api "POST" "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel" "$payload")

    if check_success "$response"; then
        local new_tunnel_id
        new_tunnel_id=$(echo "$response" | jq -r '.result.id')
        local new_tunnel_token
        new_tunnel_token=$(echo "$response" | jq -r '.result.token // "N/A"')

        log_info "Tunnel berhasil dibuat!"
        log_info "Nama     : ${tunnel_name}"
        log_info "Tunnel ID: ${new_tunnel_id}"
        separator
        log_warn "Update CF_TUNNEL_ID di config.env dengan nilai berikut:"
        echo -e "${WHITE}CF_TUNNEL_ID=\"${new_tunnel_id}\"${NC}"
        separator
        echo -e "${YELLOW}Jalankan tunnel dengan:${NC}"
        echo -e "${WHITE}cloudflared tunnel run --token ${new_tunnel_token}${NC}"
        echo ""
        echo -e "${YELLOW}Atau install sebagai service:${NC}"
        echo -e "${WHITE}cloudflared service install${NC}"
    else
        local error_msg
        error_msg=$(echo "$response" | jq -r '.errors[0].message // "Unknown error"')
        log_error "Gagal membuat tunnel: ${error_msg}"
    fi
}

# ─────────────────────────────────────────────
# Hapus Tunnel
# ─────────────────────────────────────────────
delete_tunnel() {
    log_title "HAPUS TUNNEL"

    list_tunnels
    separator

    local tunnel_id
    read -r -p "$(echo -e "${CYAN}Masukkan Tunnel ID yang akan dihapus: ${NC}")" tunnel_id
    if [[ -z "$tunnel_id" ]]; then
        log_error "Tunnel ID tidak boleh kosong!"
        return 1
    fi

    local confirm
    read -r -p "$(echo -e "${RED}Yakin hapus tunnel ini? ${WHITE}[y/N]${RED}: ${NC}")" confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && { log_warn "Dibatalkan"; return 0; }

    log_step "Menghapus tunnel..."
    local response
    response=$(cf_api "DELETE" "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${tunnel_id}")

    if check_success "$response"; then
        log_info "Tunnel berhasil dihapus!"
    else
        local error_msg
        error_msg=$(echo "$response" | jq -r '.errors[0].message // "Unknown error"')
        log_error "Gagal hapus tunnel: ${error_msg}"
    fi
}

# ═══════════════════════════════════════════════
# MODUL 3: QUICK SETUP
# ═══════════════════════════════════════════════

# ─────────────────────────────────────────────
# Setup Lengkap (DNS + Tunnel Route sekaligus)
# ─────────────────────────────────────────────
quick_setup() {
    log_title "QUICK SETUP - DNS + TUNNEL SEKALIGUS"

    echo -e "${WHITE}Quick setup akan:${NC}"
    echo -e "  ${GREEN}1.${NC} Membuat/update route di tunnel"
    echo -e "  ${GREEN}2.${NC} Membuat DNS CNAME yang pointing ke tunnel"
    separator

    # Input data
    local subdomain
    read -r -p "$(echo -e "${CYAN}Subdomain: ${NC}")" subdomain
    [[ -z "$subdomain" ]] && { log_error "Subdomain kosong!"; return 1; }

    echo ""
    echo -e "${WHITE}Pilih tipe aplikasi:${NC}"
    echo -e "  ${GREEN}1)${NC} Web (HTTP  - port 80)"
    echo -e "  ${GREEN}2)${NC} Web (HTTPS - port 443)"
    echo -e "  ${GREEN}3)${NC} SSH (port 22)"
    echo -e "  ${GREEN}4)${NC} Custom (HTTP dengan port custom)"
    local quick_type
    read -r -p "Pilihan [1-4]: " quick_type

    local service_type default_port
    case "$quick_type" in
        1) service_type="http";  default_port=80 ;;
        2) service_type="https"; default_port=443 ;;
        3) service_type="ssh";   default_port=22 ;;
        4) service_type="http";  default_port="" ;;
        *) log_error "Pilihan tidak valid!"; return 1 ;;
    esac

    local port
    if [[ -n "$default_port" ]]; then
        read -r -p "$(echo -e "${CYAN}Port ${WHITE}[default: ${default_port}]${CYAN}: ${NC}")" port
        [[ -z "$port" ]] && port="$default_port"
    else
        read -r -p "$(echo -e "${CYAN}Port: ${NC}")" port
    fi

    local origin_host
    read -r -p "$(echo -e "${CYAN}Origin Host ${WHITE}[default: localhost]${CYAN}: ${NC}")" origin_host
    [[ -z "$origin_host" ]] && origin_host="localhost"

    local service_url="${service_type}://${origin_host}:${port}"
    local full_hostname="${subdomain}.${CF_DOMAIN}"
    local tunnel_id="${CF_TUNNEL_ID}"

    if [[ -z "$tunnel_id" ]]; then
        list_tunnels
        read -r -p "$(echo -e "${CYAN}Masukkan Tunnel ID: ${NC}")" tunnel_id
    fi

    # Konfirmasi
    separator
    echo -e "${WHITE}Summary:${NC}"
    echo -e "  ${CYAN}Subdomain  :${NC} ${full_hostname}"
    echo -e "  ${CYAN}Service    :${NC} ${service_url}"
    echo -e "  ${CYAN}Tunnel ID  :${NC} ${tunnel_id}"
    separator
    local confirm
    read -r -p "Lanjutkan? [y/N]: " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && { log_warn "Dibatalkan"; return 0; }

    # Step 1: Update Tunnel Config
    log_step "[1/2] Mengupdate tunnel route..."

    local tunnel_config
    tunnel_config=$(cf_api "GET" "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${tunnel_id}/configurations")

    local existing_ingress
    existing_ingress=$(echo "$tunnel_config" | jq '[.result.config.ingress[] | select(.service != "http_status:404")]')

    local new_rule catch_all new_ingress final_payload
    new_rule=$(jq -n \
        --arg hostname "$full_hostname" \
        --arg service "$service_url" \
        '{hostname: $hostname, service: $service}')

    catch_all='{"service": "http_status:404"}'
    new_ingress=$(echo "$existing_ingress" | jq --argjson rule "$new_rule" '. + [$rule]')
    new_ingress=$(echo "$new_ingress" | jq --argjson ca "$catch_all" '. + [$ca]')

    final_payload=$(jq -n --argjson ingress "$new_ingress" '{"config": {"ingress": $ingress}}')

    local resp1
    resp1=$(cf_api "PUT" "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${tunnel_id}/configurations" "$final_payload")

    if check_success "$resp1"; then
        log_info "Tunnel route berhasil ditambahkan!"
    else
        log_error "Gagal update tunnel route"
        echo "$resp1" | jq '.errors' 2>/dev/null || true
        return 1
    fi

    # Step 2: Buat DNS CNAME
    log_step "[2/2] Membuat DNS CNAME record..."

    local dns_payload
    dns_payload=$(jq -n \
        --arg name "$full_hostname" \
        --arg content "${tunnel_id}.cfargotunnel.com" \
        '{type: "CNAME", name: $name, content: $content, proxied: true, ttl: 1}')

    local resp2
    resp2=$(cf_api "POST" "/zones/${CF_ZONE_ID}/dns_records" "$dns_payload")

    if check_success "$resp2"; then
        log_info "DNS CNAME berhasil dibuat!"
    else
        log_warn "DNS mungkin sudah ada, coba update..."
        # Coba update jika sudah ada
        local existing_id
        existing_id=$(cf_api "GET" "/zones/${CF_ZONE_ID}/dns_records?name=${full_hostname}" | \
            jq -r '.result[0].id // empty')

        if [[ -n "$existing_id" ]]; then
            resp2=$(cf_api "PUT" "/zones/${CF_ZONE_ID}/dns_records/${existing_id}" "$dns_payload")
            if check_success "$resp2"; then
                log_info "DNS CNAME berhasil diupdate!"
            fi
        fi
    fi

    separator
    log_info "✅ Quick Setup Selesai!"
    log_info "Akses: https://${full_hostname}"
}

# ─────────────────────────────────────────────
# Cek Status & Info Zone
# ─────────────────────────────────────────────
check_zone_info() {
    log_title "INFORMASI ZONE"

    log_step "Mengambil informasi zone..."
    local response
    response=$(cf_api "GET" "/zones/${CF_ZONE_ID}")

    if check_success "$response"; then
        local name status plan ns
        name=$(echo "$response" | jq -r '.result.name')
        status=$(echo "$response" | jq -r '.result.status')
        plan=$(echo "$response" | jq -r '.result.plan.name')
        ns=$(echo "$response" | jq -r '.result.name_servers | join(", ")')

        echo -e "  ${CYAN}Domain     :${NC} ${name}"
        echo -e "  ${CYAN}Status     :${NC} ${status}"
        echo -e "  ${CYAN}Plan       :${NC} ${plan}"
        echo -e "  ${CYAN}Nameserver :${NC} ${ns}"
    else
        log_error "Gagal mengambil info zone"
    fi
}

# ─────────────────────────────────────────────
# Setup/Edit Config
# ─────────────────────────────────────────────
edit_config() {
    log_title "EDIT KONFIGURASI"

    echo -e "${WHITE}Konfigurasi Saat Ini:${NC}"
    separator
    echo -e "  ${CYAN}CF_API_TOKEN  :${NC} ${CF_API_TOKEN:0:10}..."
    echo -e "  ${CYAN}CF_ZONE_ID    :${NC} ${CF_ZONE_ID}"
    echo -e "  ${CYAN}CF_ACCOUNT_ID :${NC} ${CF_ACCOUNT_ID}"
    echo -e "  ${CYAN}CF_DOMAIN     :${NC} ${CF_DOMAIN}"
    echo -e "  ${CYAN}CF_TUNNEL_ID  :${NC} ${CF_TUNNEL_ID:-'(belum diset)'}"
    separator

    echo ""
    local new_token new_zone new_account new_domain new_tunnel
    read -r -p "$(echo -e "${CYAN}CF_API_TOKEN ${WHITE}[Enter untuk skip]${CYAN}: ${NC}")" new_token
    read -r -p "$(echo -e "${CYAN}CF_ZONE_ID ${WHITE}[Enter untuk skip]${CYAN}: ${NC}")" new_zone
    read -r -p "$(echo -e "${CYAN}CF_ACCOUNT_ID ${WHITE}[Enter untuk skip]${CYAN}: ${NC}")" new_account
    read -r -p "$(echo -e "${CYAN}CF_DOMAIN ${WHITE}[Enter untuk skip]${CYAN}: ${NC}")" new_domain
    read -r -p "$(echo -e "${CYAN}CF_TUNNEL_ID ${WHITE}[Enter untuk skip]${CYAN}: ${NC}")" new_tunnel

    # Update config file
    [[ -n "$new_token" ]]   && sed -i "s/CF_API_TOKEN=.*/CF_API_TOKEN=\"${new_token}\"/" "$CONFIG_FILE"
    [[ -n "$new_zone" ]]    && sed -i "s/CF_ZONE_ID=.*/CF_ZONE_ID=\"${new_zone}\"/" "$CONFIG_FILE"
    [[ -n "$new_account" ]] && sed -i "s/CF_ACCOUNT_ID=.*/CF_ACCOUNT_ID=\"${new_account}\"/" "$CONFIG_FILE"
    [[ -n "$new_domain" ]]  && sed -i "s/CF_DOMAIN=.*/CF_DOMAIN=\"${new_domain}\"/" "$CONFIG_FILE"
    [[ -n "$new_tunnel" ]]  && sed -i "s/CF_TUNNEL_ID=.*/CF_TUNNEL_ID=\"${new_tunnel}\"/" "$CONFIG_FILE"

    log_info "Konfigurasi berhasil diupdate!"
    log_warn "Restart script untuk menerapkan perubahan"
}

# ═══════════════════════════════════════════════
# MAIN MENU
# ═══════════════════════════════════════════════
show_banner() {
    clear
    echo -e "${BOLD}${BLUE}"
    cat << 'EOF'
  ██████╗███████╗    ███╗   ███╗ █████╗ ███╗   ██╗ █████╗  ██████╗ ███████╗██████╗
 ██╔════╝██╔════╝    ████╗ ████║██╔══██╗████╗  ██║██╔══██╗██╔════╝ ██╔════╝██╔══██╗
 ██║     █████╗      ██╔████╔██║███████║██╔██╗ ██║███████║██║  ███╗█████╗  ██████╔╝
 ██║     ██╔══╝      ██║╚██╔╝██║██╔══██║██║╚██╗██║██╔══██║██║   ██║██╔══╝  ██╔══██╗
 ╚██████╗██║         ██║ ╚═╝ ██║██║  ██║██║ ╚████║██║  ██║╚██████╔╝███████╗██║  ██║
  ╚═════╝╚═╝         ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═╝  ╚═══╝
EOF
    echo -e "   Cloudflare DNS & Zero Trust Tunnel Manager"
    echo -e "   Author  : IsekaiID (https://github.com/diona-katzlein)"
    echo -e "   Version : 2.0"
    separator
}

# Jalankan validasi awal
check_deps
validate_config

# Main Menu selection loop
while true; do
    show_banner
    echo -e " 1) Tambah DNS Record       8) Hapus Route Tunnel"
    echo -e " 2) Daftar DNS Record       9) Buat Tunnel Baru"
    echo -e " 3) Hapus DNS Record       10) Hapus Tunnel"
    echo -e " 4) Toggle Proxy DNS       11) Quick Setup (DNS + Tunnel)"
    echo -e " 5) Daftar Cloudflare Tunnel 12) Cek Informasi Domain (Zone)"
    echo -e " 6) Tambah App ke Tunnel    13) Edit Konfigurasi (config.env)"
    echo -e " 7) Daftar Route Tunnel     0) Keluar"
    separator
    local menu_choice
    read -r -p "Pilihan Anda [0-13]: " menu_choice

    case "$menu_choice" in
        1) add_dns_record; pause ;;
        2) list_dns_records; pause ;;
        3) delete_dns_record; pause ;;
        4) toggle_proxy_dns; pause ;;
        5) list_tunnels; pause ;;
        6) add_tunnel_app; pause ;;
        7) list_tunnel_routes; pause ;;
        8) delete_tunnel_route; pause ;;
        9) create_tunnel; pause ;;
        10) delete_tunnel; pause ;;
        11) quick_setup; pause ;;
        12) check_zone_info; pause ;;
        13) edit_config; pause ;;
        0) echo -e "\nTerima kasih!"; exit 0 ;;
        *) log_error "Pilihan tidak valid!"; sleep 1 ;;
    esac
done
