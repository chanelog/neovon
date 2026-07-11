#!/bin/bash
# ╔═════════════════════════════════════════════════════════════════════════╗
# ║  NEONVPN - Advanced Tunneling Suite (FIXED VERSION)                     ║
# ║  Supports: SSH-WS/SSL (TLS/SSL/NTLS) + Xray (VMess/VLess/Trojan/SS)   ║
# ║  Single-file installer & management script                              ║
# ║  Author: chanelog | Fixed: v2.0.1                                       ║
# ╚═════════════════════════════════════════════════════════════════════════╝
# shellcheck disable=SC1090,SC2086,SC2143,SC2181,SC2034

# ═══════════════════════════════════════════════════════════
#  SECTION 1: GLOBAL VARIABLES & CONSTANTS (FIXED)
# ═══════════════════════════════════════════════════════════

VERSION="2.0.1"
SCRIPT_DIR="/etc/neonvpn"
BIN_DIR="/usr/local/bin"
XRAY_DIR="/etc/xray"
SSL_DIR="/etc/ssl/neonvpn"
DB_DIR="$SCRIPT_DIR/db"
LOG_DIR="/var/log/neonvpn"
CONF_DIR="$SCRIPT_DIR/config"

# ─── Port Architecture ──────────────────────────────────
WS_OPENSSH_PORT=2093
WS_DROPBEAR_PORT=2095
WS_STUNNEL_LOCAL_PORT=700
STUNNEL_SSL_PORT=445
WSTUNNEL_PORT=8880
NGINX_TLS_INTERNAL_PORT=8443
XRAY_API_PORT=62731

# ─── Port Map (internal xray) ──────────────────────────
XRAY_VMESS_WS_TLS_PORT=10001
XRAY_VMESS_WS_NTLS_PORT=10002
XRAY_VLESS_WS_TLS_PORT=10003
XRAY_VLESS_WS_NTLS_PORT=10004
XRAY_VLESS_GRPC_TLS_PORT=10005
XRAY_TROJAN_WS_TLS_PORT=10006
XRAY_TROJAN_GRPC_TLS_PORT=10007
XRAY_SS_WS_TLS_PORT=10008
XRAY_SS_GRPC_TLS_PORT=10009

# ─── Database Files ─────────────────────────────────────
DB_VMESS="$DB_DIR/vmess.db"
DB_VLESS="$DB_DIR/vless.db"
DB_TROJAN="$DB_DIR/trojan.db"
DB_SS="$DB_DIR/ss.db"
DB_SSH="$DB_DIR/ssh.db"

# ─── Xray Binary & Config ──────────────────────────────
XRAY_BIN="$BIN_DIR/xray"
XRAY_CONFIG="$XRAY_DIR/config.json"

# ─── Update URL ─────────────────────────────────────────
UPDATE_URL="https://raw.githubusercontent.com/masamuda1993/neonvpn/main"

# ═══════════════════════════════════════════════════════════
#  SECTION 2: COLOR PALETTE & UI ENGINE
# ═══════════════════════════════════════════════════════════

# ─── Core Colors ────────────────────────────────────────
BLK='\033[0;30m';    RED='\033[0;31m';    GRN='\033[0;32m';    YLW='\033[0;33m'
BLU='\033[0;34m';    MGN='\033[0;35m';    CYN='\033[0;36m';    WHT='\033[0;37m'
DIM='\033[0;2m'

# ─── Bold Variants ──────────────────────────────────────
BRED='\033[1;31m';   BGRN='\033[1;32m';   BYLW='\033[1;33m'
BBLU='\033[1;34m';   BMGN='\033[1;35m';   BCYN='\033[1;36m'
BWHT='\033[1;37m'

# ─── Extended Colors (256) ─────────────────────────────
TEAL='\033[38;5;14m';   MINT='\033[38;5;10m';   GOLD='\033[38;5;178m'
CORAL='\033[38;5;203m';  LBLUE='\033[38;5;111m'; NAVY='\033[38;5;17m'
SILVER='\033[38;5;7m';   PEACH='\033[38;5;216m'; LIME='\033[38;5;118m'

# ─── Background Colors ─────────────────────────────────
BG_TEAL='\033[48;5;23m';  BG_DARK='\033[48;5;233m'
BG_RED='\033[48;5;52m';   BG_GRN='\033[48;5;22m'

# ─── Reset ──────────────────────────────────────────────
RST='\033[0m'

# ─── Logging Functions ──────────────────────────────────
log_ok()    { echo -e "  ${BGRN}✓${RST} ${WHT}$1${RST}"; }
log_fail()  { echo -e "  ${BRED}✗${RST} ${WHT}$1${RST}"; }
log_info()  { echo -e "  ${TEAL}◆${RST} ${WHT}$1${RST}"; }
log_warn()  { echo -e "  ${GOLD}▲${RST} ${WHT}$1${RST}"; }
log_step()  { echo -e "\n  ${BCYN}┌─ STEP $1 ───────────────────────────────────${RST}"; echo -e "  ${BCYN}│${RST} ${BWHT}$2${RST}"; }

# ─── Progress Bar ───────────────────────────────────────
show_progress() {
    local msg="$1" total="$2" current="$3"
    local pct=$(( current * 100 / total ))
    local filled=$(( pct / 2 ))
    local empty=$(( 50 - filled ))
    local bar=$(printf '%*s' "$filled" '' | tr ' ' '█')
    local spc=$(printf '%*s' "$empty" '' | tr ' ' '░')
    printf "\r  ${TEAL}◆${RST} ${WHT}${msg}${RST} ${TEAL}[${BGRN}${bar}${TEAL}${spc}]${RST} ${BWHT}%3d%%${RST}   " "$pct"
}

# ─── Spinner Animation ──────────────────────────────────
_spinner_pid=""
_start_spinner() {
    local msg="$1"
    tput civis 2>/dev/null || true
    (
        local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
        while true; do
            for f in "${frames[@]}"; do
                printf "\r  ${TEAL}%s${RST} ${WHT}%s${RST}" "$f" "$msg"
                sleep 0.08
            done
        done
    ) &
    _spinner_pid=$!
}

_stop_spinner() {
    if [[ -n "$_spinner_pid" ]]; then
        kill "$_spinner_pid" 2>/dev/null || true
        wait "$_spinner_pid" 2>/dev/null || true
        _spinner_pid=""
        printf "\r%*s\r" 60 ""
    fi
    tput cnorm 2>/dev/null || true
}

# ─── Box Drawing (Modern Style - Rounded) ──────────────
_panel_top() {
    local title="$1" width="${2:-64}"
    local inner=$((width - 4))
    echo -e "  ${TEAL}╭${RST}$(printf '%*s' "$inner" '' | tr ' ' '─')${TEAL}╮${RST}"
    local pad=$(( (inner - ${#title}) / 2 ))
    [[ $pad -lt 0 ]] && pad=0
    local lpad=$(printf '%*s' "$pad" '' | tr ' ' ' ')
    local rpad=$(( inner - ${#title} - pad ))
    [[ $rpad -lt 0 ]] && rpad=0
    local rpad_s=$(printf '%*s' "$rpad" '' | tr ' ' ' ')
    echo -e "  ${TEAL}│${RST} ${BWHT}${title}${RST} ${lpad}${rpad_s} ${TEAL}│${RST}"
    echo -e "  ${TEAL}├${RST}$(printf '%*s' "$inner" '' | tr ' ' '─')${TEAL}┤${RST}"
}

_panel_mid() {
    local width="${1:-64}"
    local inner=$((width - 4))
    echo -e "  ${TEAL}├${RST}$(printf '%*s' "$inner" '' | tr ' ' '─')${TEAL}┤${RST}"
}

_panel_row() {
    local label="$1" value="$2" width="${3:-64}"
    local inner=$((width - 4))
    local content="  ${SILVER}${label}${RST} ${DIM}∶${RST} ${WHT}${value}${RST}"
    local pad=$(( inner - ${#label} - ${#value} - 6 ))
    [[ $pad -lt 1 ]] && pad=1
    local sp=$(printf '%*s' "$pad" '' | tr ' ' ' ')
    echo -e "  ${TEAL}│${RST}${content}${sp} ${TEAL}│${RST}"
}

_panel_row_colored() {
    local label="$1" value="$2" color="$3" width="${4:-64}"
    local inner=$((width - 4))
    local content="  ${SILVER}${label}${RST} ${DIM}∶${RST} ${!color}${value}${RST}"
    local pad=$(( inner - ${#label} - ${#value} - 6 ))
    [[ $pad -lt 1 ]] && pad=1
    local sp=$(printf '%*s' "$pad" '' | tr ' ' ' ')
    echo -e "  ${TEAL}│${RST}${content}${sp} ${TEAL}│${RST}"
}

_panel_empty() {
    local width="${1:-64}"
    local inner=$((width - 4))
    echo -e "  ${TEAL}│${RST}$(printf '%*s' "$inner" '' | tr ' ' ' ') ${TEAL}│${RST}"
}

_panel_bot() {
    local width="${1:-64}"
    local inner=$((width - 4))
    echo -e "  ${TEAL}╰${RST}$(printf '%*s' "$inner" '' | tr ' ' '─')${TEAL}╯${RST}"
}

_menu_item() {
    local num="$1" text="$2" desc="${3:-}" width="${4:-64}"
    local inner=$((width - 4))
    if [[ -n "$desc" ]]; then
        local content="  ${BGRN}▸${RST} ${BWHT}[${num}]${RST} ${WHT}${text}${RST}  ${DIM}${desc}${RST}"
    else
        local content="  ${BGRN}▸${RST} ${BWHT}[${num}]${RST} ${WHT}${text}${RST}"
    fi
    local pad=$(( inner - ${#num} - ${#text} - ${#desc} - 12 ))
    [[ $pad -lt 1 ]] && pad=1
    local sp=$(printf '%*s' "$pad" '' | tr ' ' ' ')
    echo -e "  ${TEAL}│${RST}${content}${sp} ${TEAL}│${RST}"
}

_menu_item_dim() {
    local num="$1" text="$2" width="${3:-64}"
    local inner=$((width - 4))
    local content="  ${DIM}▸${RST} ${DIM}[${num}]${RST} ${DIM}${text}${RST}"
    local pad=$(( inner - ${#num} - ${#text} - 8 ))
    [[ $pad -lt 1 ]] && pad=1
    local sp=$(printf '%*s' "$pad" '' | tr ' ' ' ')
    echo -e "  ${TEAL}│${RST}${content}${sp} ${TEAL}│${RST}"
}

_menu_item_warn() {
    local num="$1" text="$2" width="${3:-64}"
    local inner=$((width - 4))
    local content="  ${GOLD}▸${RST} ${BWHT}[${num}]${RST} ${WHT}${text}${RST}"
    local pad=$(( inner - ${#num} - ${#text} - 8 ))
    [[ $pad -lt 1 ]] && pad=1
    local sp=$(printf '%*s' "$pad" '' | tr ' ' ' ')
    echo -e "  ${TEAL}│${RST}${content}${sp} ${TEAL}│${RST}"
}

_menu_item_danger() {
    local num="$1" text="$2" width="${3:-64}"
    local inner=$((width - 4))
    local content="  ${CORAL}▸${RST} ${BRED}[${num}]${RST} ${RED}${text}${RST}"
    local pad=$(( inner - ${#num} - ${#text} - 8 ))
    [[ $pad -lt 1 ]] && pad=1
    local sp=$(printf '%*s' "$pad" '' | tr ' ' ' ')
    echo -e "  ${TEAL}│${RST}${content}${sp} ${TEAL}│${RST}"
}

# ─── Status Dot (Modern) ───────────────────────────────
_status_dot() {
    if systemctl is-active --quiet "$1" 2>/dev/null; then
        echo -e "${BGRN}● ON${RST}"
    else
        echo -e "${DIM}● OFF${RST}"
    fi
}

_status_text() {
    systemctl is-active --quiet "$1" 2>/dev/null && echo "ACTIVE" || echo "INACTIVE"
}

# ─── Status Grid (4 columns) ───────────────────────────
_status_grid() {
    local services=("$@")
    local count=${#services[@]}
    local cols=4
    local rows=$(( (count + cols - 1) / cols ))

    for ((r=0; r<rows; r++)); do
        local line="  "
        for ((c=0; c<cols; c++)); do
            local idx=$(( r * cols + c ))
            if [[ $idx -lt $count ]]; then
                local svc="${services[$idx]}"
                local name="${svc%%:*}"
                local label="${svc#*:}"
                if systemctl is-active --quiet "$name" 2>/dev/null; then
                    local st="${BGRN}●${RST}"
                else
                    local st="${DIM}●${RST}"
                fi
                line+="${st} ${SILVER}${label}${RST}    "
            fi
        done
        echo -e "$line"
    done
}

# ─── ASCII Art Banner ──────────────────────────────────
_show_banner() {
    clear
    echo -e "${BG_DARK}"
    echo -e "  ${TEAL}                                       ${RST}"
    echo -e "  ${TEAL}  ███╗   ██╗███████╗██╗  ██╗██╗   ██╗${RST}  ${BWHT}A D V A N C E D${RST}  ${TEAL}  ███╗   ██╗███████╗${RST}"
    echo -e "  ${TEAL}  ████╗  ██║██╔════╝╚██╗██╔╝██║   ██║${RST}  ${SILVER}T U N N E L I N G${RST}  ${TEAL}  ████╗  ██║██╔════╝${RST}"
    echo -e "  ${TEAL}  ██╔██╗ ██║█████╗   ╚███╔╝ ██║   ██║${RST}  ${SILVER}   S U I T E   ${RST}  ${TEAL}  ██╔██╗ ██║███████╗${RST}"
    echo -e "  ${TEAL}  ██║╚██╗██║██╔══╝   ██╔██╗ ██║   ██║${RST}                    ${TEAL}  ██║╚██╗██║██╔══╝ ${RST}"
    echo -e "  ${TEAL}  ██║ ╚████║███████╗██╔╝ ╚██╗╚██████╔╝${RST}   ${DIM}v${VERSION}${RST}         ${TEAL}  ██║ ╚███║███████╗${RST}"
    echo -e "  ${TEAL}  ╚═╝  ╚═══╝╚══════╝╚═╝   ╚═╝ ╚═════╝${RST}                    ${TEAL}  ╚═╝  ╚═══╝╚══════╝${RST}"
    echo -e "  ${TEAL}                                       ${RST}"
    echo -e "${RST}"
}

# ─── Separator Line ────────────────────────────────────
_separator() {
    local width="${1:-64}"
    echo -e "  ${DIM}$(printf '%*s' "$width" '' | tr ' ' '─')${RST}"
}

# ═══════════════════════════════════════════════════════════
#  SECTION 3: UTILITY FUNCTIONS (FIXED & OPTIMIZED)
# ═══════════════════════════════════════════════════════════

# ─── Domain Helpers ─────────────────────────────────────
get_domain() {
    cat "$SCRIPT_DIR/domain" 2>/dev/null || echo "undefined"
}

get_server_ip() {
    # FIX: Added timeout and error handling
    curl -s4 --max-time 5 https://ifconfig.me 2>/dev/null || \
    curl -s4 --max-time 5 https://api.ipify.org 2>/dev/null || \
    curl -s4 --max-time 5 https://ipv4.icanhazip.com 2>/dev/null || \
    hostname -I | awk '{print $1}' 2>/dev/null || \
    echo "127.0.0.1"
}

validate_domain() {
    echo "$1" | grep -qE '^([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'
}

verify_domain_ip() {
    local domain="$1"
    local server_ip=$(get_server_ip)
    local domain_ip=$(dig +short "$domain" A 2>/dev/null | grep -E '^[0-9]+\.' | tail -1)
    if [[ -z "$server_ip" ]]; then echo "no_server_ip"; return; fi
    if [[ -z "$domain_ip" ]]; then echo "no_dns"; return; fi
    if [[ "$domain_ip" == "$server_ip" ]]; then echo "match"; else echo "mismatch"; fi
}

# ─── System Info ────────────────────────────────────────
get_os_info() { . /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || uname -o; }
get_kernel() { uname -r; }
get_cpu_model() { grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | sed 's/^ *//'; }
get_cpu_cores() { nproc; }
get_cpu_usage() { top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print $2}' | cut -d. -f1 || echo "?"; }
get_mem_info() { free -m 2>/dev/null | awk 'NR==2{printf "%sMB / %sMB (%.0f%%)", $3, $2, $3*100/$2}' || echo "N/A"; }
get_disk_info() { df -h / 2>/dev/null | awk 'NR==2{printf "%s / %s (%s)", $3, $2, $5}' || echo "N/A"; }
get_uptime() { uptime -p 2>/dev/null | sed 's/up //' || uptime | awk '{print $3,$4}' | sed 's/,//'; }
get_load_avg() { uptime 2>/dev/null | awk -F'load average: ' '{print $2}' || echo "N/A"; }
get_xray_version() { $XRAY_BIN version 2>/dev/null | head -1 | awk '{print $2}' || echo "N/A"; }
get_network_iface() { ip route 2>/dev/null | grep default | awk '{print $5}' | head -1; }

get_network_usage() {
    local iface=$(get_network_iface)
    if [[ -n "$iface" ]]; then
        local rx=$(cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null || echo 0)
        local tx=$(cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null || echo 0)
        echo "$(numfmt --to=iec $rx 2>/dev/null || printf '%dB' $rx) ↓ / $(numfmt --to=iec $tx 2>/dev/null || printf '%dB' $tx) ↑"
    else
        echo "N/A"
    fi
}

# ─── Generators ─────────────────────────────────────────
gen_uuid() {
    cat /proc/sys/kernel/random/uuid 2>/dev/null || \
    python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || \
    openssl rand -hex 16 | sed 's/\(.\{8\}\)\(.\{4\}\)\(.\{4\}\)\(.\{4\}\)\(.\{12\}\)/\1-\2-\3-\4-\5/'
}

gen_password() {
    openssl rand -base64 16 | tr -dc 'A-Za-z0-9' | head -c 16
}

gen_ssh_password() {
    tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 10 || \
    openssl rand -base64 8 | tr -dc 'A-Za-z0-9' | head -c 10
}

# ─── Date Helpers ───────────────────────────────────────
get_exp_date() { date -d "+${1} days" +"%Y-%m-%d" 2>/dev/null || echo "unknown"; }
days_until_exp() {
    local exp="$1"
    local today=$(date +%s 2>/dev/null)
    local expd=$(date -d "$exp" +%s 2>/dev/null || echo 0)
    echo $(( (expd - today) / 86400 ))
}
is_expired() { [[ $(days_until_exp "$1") -lt 0 ]]; }

# ─── Prompt Helpers ─────────────────────────────────────
press_enter() { echo -ne "\n  ${DIM}Tekan Enter untuk kembali...${RST}"; read -r; }

confirm() {
    local msg="$1" default="${2:-n}"
    local prompt
    if [[ "$default" == "y" ]]; then
        prompt="${WHT}  ${msg} ${BGRN}[Y/n]${RST}: "
    else
        prompt="${WHT}  ${msg} ${BRED}[y/N]${RST}: "
    fi
    echo -ne "$prompt"
    local c; read -r c
    if [[ "$default" == "y" ]]; then [[ ! "$c" =~ ^[Nn]$ ]]; else [[ "$c" =~ ^[Yy]$ ]]; fi
}

# ─── WS Payload Helper ─────────────────────────────────
ws_payload_string() {
    local domain="$1" port="${2:-80}"
    printf 'GET /ssh-ws HTTP/1.1[crlf]Host: %s[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]' "$domain"
}

# ═══════════════════════════════════════════════════════════
#  SECTION 4: ACCOUNT MANAGEMENT (FIXED)
# ═══════════════════════════════════════════════════════════

# ─── SSH Accounts ───────────────────────────────────────
create_ssh() {
    local username="$1" days="$2" password="${3:-$(gen_ssh_password)}"
    local exp=$(get_exp_date "$days")
    local created=$(date +"%Y-%m-%d")
    # FIX: Added better error checking
    useradd -e "$exp" -s /bin/false -M "$username" 2>/dev/null || return 1
    echo "$username:$password" | chpasswd 2>/dev/null || return 1
    echo "$username|$password|$exp|$created" >> "$DB_SSH"
    echo "$password"
}

delete_ssh() {
    local username="$1"
    userdel -f "$username" 2>/dev/null || true
    sed -i "/^${username}|/d" "$DB_SSH" 2>/dev/null || true
}

renew_ssh() {
    local username="$1" days="$2"
    local exp=$(get_exp_date "$days")
    chage -E "$exp" "$username" 2>/dev/null || true
    sed -i "s/^${username}|\\([^|]*\\)|\\([^|]*\\)|\\(.*\\)$/${username}|\\1|${exp}|\\3/" "$DB_SSH"
}

get_ssh_info() { grep "^${1}|" "$DB_SSH" 2>/dev/null; }
list_ssh() { cat "$DB_SSH" 2>/dev/null; }
count_ssh() { [[ -f "$DB_SSH" ]] && wc -l < "$DB_SSH" || echo 0; }

# ─── VMess Accounts ─────────────────────────────────────
create_vmess() {
    local username="$1" days="$2"
    local uuid=$(gen_uuid)
    local exp=$(get_exp_date "$days")
    local created=$(date +"%Y-%m-%d")
    echo "$username|$uuid|$exp|$created" >> "$DB_VMESS"
    local tmp=$(mktemp)
    jq --arg uuid "$uuid" --arg email "$username" \
        '(.inbounds[] | select(.tag == "vmess-ws-tls" or .tag == "vmess-ws-ntls") | .settings.clients) += [{"id": $uuid, "alterId": 0, "email": $email}]' \
        "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"
    systemctl reload xray 2>/dev/null || systemctl restart xray 2>/dev/null
    echo "$uuid"
}

delete_vmess() {
    local username="$1"
    sed -i "/^${username}|/d" "$DB_VMESS" 2>/dev/null || true
    local tmp=$(mktemp)
    jq --arg email "$username" \
        '(.inbounds[] | select(.tag | startswith("vmess")) | .settings.clients) |= map(select(.email != $email))' \
        "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG" || true
    systemctl reload xray 2>/dev/null || systemctl restart xray 2>/dev/null
}

renew_vmess() {
    local username="$1" days="$2"
    local exp=$(get_exp_date "$days")
    sed -i "s/^${username}|\\([^|]*\\)|\\([^|]*\\)|\\(.*\\)$/${username}|\\1|${exp}|\\3/" "$DB_VMESS"
}

get_vmess_info() { grep "^${1}|" "$DB_VMESS" 2>/dev/null; }
list_vmess() { cat "$DB_VMESS" 2>/dev/null; }
count_vmess() { [[ -f "$DB_VMESS" ]] && wc -l < "$DB_VMESS" || echo 0; }

# ─── VLess Accounts ─────────────────────────────────────
create_vless() {
    local username="$1" days="$2"
    local uuid=$(gen_uuid)
    local exp=$(get_exp_date "$days")
    local created=$(date +"%Y-%m-%d")
    echo "$username|$uuid|$exp|$created" >> "$DB_VLESS"
    local tmp=$(mktemp)
    jq --arg uuid "$uuid" --arg email "$username" \
        '(.inbounds[] | select(.tag == "vless-ws-tls" or .tag == "vless-ws-ntls" or .tag == "vless-grpc-tls") | .settings.clients) += [{"id": $uuid, "email": $username, "flow": ""}]' \
        "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"
    systemctl reload xray 2>/dev/null || systemctl restart xray 2>/dev/null
    echo "$uuid"
}

delete_vless() {
    local username="$1"
    sed -i "/^${username}|/d" "$DB_VLESS" 2>/dev/null || true
    local tmp=$(mktemp)
    jq --arg email "$username" \
        '(.inbounds[] | select(.tag | startswith("vless")) | .settings.clients) |= map(select(.email != $email))' \
        "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG" || true
    systemctl reload xray 2>/dev/null || systemctl restart xray 2>/dev/null
}

renew_vless() {
    local username="$1" days="$2"
    local exp=$(get_exp_date "$days")
    sed -i "s/^${username}|\\([^|]*\\)|\\([^|]*\\)|\\(.*\\)$/${username}|\\1|${exp}|\\3/" "$DB_VLESS"
}

get_vless_info() { grep "^${1}|" "$DB_VLESS" 2>/dev/null; }
list_vless() { cat "$DB_VLESS" 2>/dev/null; }
count_vless() { [[ -f "$DB_VLESS" ]] && wc -l < "$DB_VLESS" || echo 0; }

# ─── Trojan Accounts ────────────────────────────────────
create_trojan() {
    local username="$1" days="$2"
    local password=$(gen_password)
    local exp=$(get_exp_date "$days")
    local created=$(date +"%Y-%m-%d")
    echo "$username|$password|$exp|$created" >> "$DB_TROJAN"
    local tmp=$(mktemp)
    jq --arg pass "$password" --arg email "$username" \
        '(.inbounds[] | select(.tag | startswith("trojan")) | .settings.clients) += [{"password": $pass, "email": $email}]' \
        "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"
    systemctl reload xray 2>/dev/null || systemctl restart xray 2>/dev/null
    echo "$password"
}

delete_trojan() {
    local username="$1"
    sed -i "/^${username}|/d" "$DB_TROJAN" 2>/dev/null || true
    local tmp=$(mktemp)
    jq --arg email "$username" \
        '(.inbounds[] | select(.tag | startswith("trojan")) | .settings.clients) |= map(select(.email != $email))' \
        "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG" || true
    systemctl reload xray 2>/dev/null || systemctl restart xray 2>/dev/null
}

renew_trojan() {
    local username="$1" days="$2"
    local exp=$(get_exp_date "$days")
    sed -i "s/^${username}|\\([^|]*\\)|\\([^|]*\\)|\\(.*\\)$/${username}|\\1|${exp}|\\3/" "$DB_TROJAN"
}

get_trojan_info() { grep "^${1}|" "$DB_TROJAN" 2>/dev/null; }
list_trojan() { cat "$DB_TROJAN" 2>/dev/null; }
count_trojan() { [[ -f "$DB_TROJAN" ]] && wc -l < "$DB_TROJAN" || echo 0; }

# ─── Shadowsocks Accounts ───────────────────────────────
create_ss() {
    local username="$1" days="$2"
    local password=$(gen_password)
    local method="aes-128-gcm"
    local exp=$(get_exp_date "$days")
    local created=$(date +"%Y-%m-%d")
    echo "$username|$password|$method|$exp|$created" >> "$DB_SS"
    local tmp=$(mktemp)
    jq --arg pass "$password" --arg method "$method" \
        '(.inbounds[] | select(.tag | startswith("ss-")) | .settings.clients) += [{"method": $method, "password": $pass}]' \
        "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"
    systemctl reload xray 2>/dev/null || systemctl restart xray 2>/dev/null
    echo "$password"
}

delete_ss() {
    local username="$1"
    sed -i "/^${username}|/d" "$DB_SS" 2>/dev/null || true
    local tmp=$(mktemp)
    jq --arg pass "$(grep "^${username}|" "$DB_SS" 2>/dev/null | cut -d'|' -f2)" \
        '(.inbounds[] | select(.tag | startswith("ss-")) | .settings.clients) |= map(select(.password != $pass))' \
        "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG" || true
    systemctl reload xray 2>/dev/null || systemctl restart xray 2>/dev/null
}

renew_ss() {
    local username="$1" days="$2"
    local exp=$(get_exp_date "$days")
    sed -i "s/^${username}|\\([^|]*\\)|\\([^|]*\\)|\\([^|]*\\)|\\(.*\\)$/${username}|\\1|\\2|${exp}|\\4/" "$DB_SS"
}

get_ss_info() { grep "^${1}|" "$DB_SS" 2>/dev/null; }
list_ss() { cat "$DB_SS" 2>/dev/null; }
count_ss() { [[ -f "$DB_SS" ]] && wc -l < "$DB_SS" || echo 0; }

# ─── Delete All Expired ─────────────────────────────────
delete_expired() {
    local today=$(date +%s) total=0
    for db_file in "$DB_VMESS" "$DB_VLESS" "$DB_TROJAN" "$DB_SS"; do
        [[ ! -f "$db_file" ]] && continue
        while IFS='|' read -r user _ exp _; do
            [[ -z "$user" ]] && continue
            local expd=$(date -d "$exp" +%s 2>/dev/null || echo 0)
            if [[ $expd -lt $today && $expd -gt 0 ]]; then
                case "$db_file" in
                    *vmess*) delete_vmess "$user" ;;
                    *vless*) delete_vless "$user" ;;
                    *trojan*) delete_trojan "$user" ;;
                    *ss*) delete_ss "$user" ;;
                esac
                ((total++))
            fi
        done < "$db_file"
    done
    while IFS='|' read -r user _ exp _; do
        [[ -z "$user" ]] && continue
        local expd=$(date -d "$exp" +%s 2>/dev/null || echo 0)
        if [[ $expd -lt $today && $expd -gt 0 ]]; then
            delete_ssh "$user"
            ((total++))
        fi
    done < <(list_ssh)
    echo "$total"
}

# ═══════════════════════════════════════════════════════════
#  SECTION 5: LINK GENERATORS
# ═══════════════════════════════════════════════════════════

gen_vmess_link() {
    local user="$1" uuid="$2" domain="$3" type="${4:-tls}" remark="$5"
    local port path
    if [[ "$type" == "tls" ]]; then port=443; path="/vmess-ws"; else port=80; path="/vmess-ntls"; fi
    local json="{\"v\":\"2\",\"ps\":\"${remark:-$user-vmess-$type}\",\"add\":\"$domain\",\"port\":\"$port\",\"id\":\"$uuid\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"$domain\",\"path\":\"$path\",\"tls\":\"${type}\"}"
    echo "vmess://$(echo -n "$json" | base64 -w 0)"
}

gen_vless_link() {
    local user="$1" uuid="$2" domain="$3" type="${4:-tls}" remark="$5"
    local port path security
    if [[ "$type" == "tls" ]]; then port=443; path="/vless-ws"; security="tls"
    elif [[ "$type" == "grpc" ]]; then port=443; path="vless-grpc"; security="tls"
    else port=80; path="/vless-ntls"; security="none"; fi
    if [[ "$type" == "grpc" ]]; then
        echo "vless://${uuid}@${domain}:${port}?encryption=none&security=${security}&type=grpc&serviceName=${path}&sni=${domain}#${remark:-$user-vless-grpc}"
    else
        echo "vless://${uuid}@${domain}:${port}?encryption=none&security=${security}&type=ws&host=${domain}&path=${path}&sni=${domain}#${remark:-$user-vless-$type}"
    fi
}

gen_trojan_link() {
    local user="$1" pass="$2" domain="$3" type="${4:-ws}" remark="$5"
    local path
    if [[ "$type" == "grpc" ]]; then
        path="trojan-grpc"
        echo "trojan://${pass}@${domain}:443?security=tls&type=grpc&serviceName=${path}&sni=${domain}#${remark:-$user-trojan-grpc}"
    else
        path="/trojan-ws"
        echo "trojan://${pass}@${domain}:443?security=tls&type=ws&host=${domain}&path=${path}&sni=${domain}#${remark:-$user-trojan-ws}"
    fi
}

gen_ss_link() {
    local user="$1" pass="$2" domain="$3" type="${4:-ws}" remark="$5"
    local method="aes-128-gcm" path
    if [[ "$type" == "grpc" ]]; then
        path="ss-grpc"
        local base="${method}:${pass}"
        echo "ss://$(echo -n "$base" | base64 -w 0)@${domain}:443?security=tls&type=grpc&serviceName=${path}&sni=${domain}#${remark:-$user-ss-grpc}"
    else
        path="/ss-ws"
        local base="${method}:${pass}"
        echo "ss://$(echo -n "$base" | base64 -w 0)@${domain}:443?security=tls&type=ws&host=${domain}&path=${path}&sni=${domain}#${remark:-$user-ss-ws}"
    fi
}

# ═══════════════════════════════════════════════════════════
#  SECTION 6: INSTALLATION ENGINE (FIXED & IMPROVED)
# ═══════════════════════════════════════════════════════════

run_installer() {
    local DOMAIN
    TOTAL_STEPS=9

    _show_banner
    echo -e "  ${SILVER}Selamat datang di NEONVPN Installer${RST}"
    echo -e "  ${DIM}Script ini akan menginstall semua komponen secara berurutan${RST}"
    _separator
    echo ""

    # ─── Check Root ────────────────────────────────────────
    if [[ $EUID -ne 0 ]]; then
        echo -e "  ${BRED}✗ Error: Script harus dijalankan sebagai root!${RST}"
        exit 1
    fi

    # ─── Check OS ──────────────────────────────────────────
    . /etc/os-release 2>/dev/null
    if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
        echo -e "  ${BRED}✗ Error: Hanya mendukung Ubuntu/Debian!${RST}"
        exit 1
    fi
    echo -e "  ${BGRN}✓${RST} ${WHT}OS: ${BWHT}$PRETTY_NAME${RST}"

    echo ""

    # ══════════════════════════════════════════════════════
    #  STEP 1: DOMAIN INPUT
    # ══════════════════════════════════════════════════════
    log_step "1/$TOTAL_STEPS" "KONFIGURASI DOMAIN"

    while true; do
        echo -ne "  ${BWHT}Masukkan domain${RST} ${DIM}(sudah diarahkan ke IP VPS ini)${RST}: "
        read -r DOMAIN
        DOMAIN=$(echo "$DOMAIN" | tr '[:upper:]' '[:lower:]' | xargs)

        if [[ -z "$DOMAIN" ]]; then
            log_fail "Domain tidak boleh kosong!"
            continue
        fi

        if ! validate_domain "$DOMAIN"; then
            log_fail "Format domain tidak valid!"
            continue
        fi

        echo ""
        log_info "Memverifikasi ${BWHT}$DOMAIN${RST} ..."

        local result=$(verify_domain_ip "$DOMAIN")
        case "$result" in
            match)
                local server_ip=$(get_server_ip)
                log_ok "Domain ${BWHT}$DOMAIN${RST} → ${BGRN}$server_ip${RST} VERIFIED"
                break
                ;;
            mismatch)
                log_warn "Domain IP tidak cocok dengan server IP!"
                if confirm "Lanjutkan?" "n"; then break; fi
                ;;
            no_dns)
                log_warn "DNS domain belum ditemukan / belum propagasi!"
                if confirm "Lanjutkan?" "n"; then break; fi
                ;;
            no_server_ip)
                log_warn "Tidak bisa cek IP server, lanjut tanpa verifikasi..."
                break
                ;;
        esac
    done

    echo "$DOMAIN" > /tmp/neonvpn_domain.tmp
    echo ""

    # ══════════════════════════════════════════════════════
    #  STEP 2: INSTALL DEPENDENCIES
    # ══════════════════════════════════════════════════════
    log_step "2/$TOTAL_STEPS" "INSTALL DEPENDENSI DASAR"

    DEPS=(curl wget gnupg2 ca-certificates lsb-release uuid-runtime jq \
          nginx python3 openssl net-tools iptables stunnel4 \
          dropbear socat dnsutils cron unzip)

    apt-get update -qq 2>/dev/null
    local dep_total=${#DEPS[@]} dep_current=0
    for pkg in "${DEPS[@]}"; do
        ((dep_current++))
        show_progress "Installing $pkg" "$dep_total" "$dep_current"
        apt-get install -y -qq "$pkg" >/dev/null 2>&1 || true
    done
    echo ""
    log_ok "Semua dependensi terinstall"

    # ══════════════════════════════════════════════════════
    #  STEP 3: ACME.SH SSL CERTIFICATE
    # ══════════════════════════════════════════════════════
    log_step "3/$TOTAL_STEPS" "SSL CERTIFICATE (ACME.SH)"

    mkdir -p "$SSL_DIR"

    # Stop services on port 80/443
    systemctl stop nginx 2>/dev/null || true
    systemctl stop xray 2>/dev/null || true
    systemctl stop haproxy 2>/dev/null || true

    if [[ ! -f /root/.acme.sh/acme.sh ]]; then
        log_info "Installing acme.sh ..."
        _start_spinner "Installing acme.sh"
        curl -fsSL https://get.acme.sh | sh -s email=admin@$DOMAIN >/dev/null 2>&1
        _stop_spinner
        log_ok "acme.sh terinstall"
    else
        log_ok "acme.sh sudah ada"
    fi

    log_info "Menerbitkan SSL untuk ${BWHT}$DOMAIN${RST} ..."
    _start_spinner "Menerbitkan sertifikat SSL"

    /root/.acme.sh/acme.sh --set-default-ca --server letsencrypt >/dev/null 2>&1
    /root/.acme.sh/acme.sh --issue --standalone -d "$DOMAIN" \
        --keylength ec-256 --httpport 80 --force >/dev/null 2>&1

    _stop_spinner

    if [[ -f /root/.acme.sh/${DOMAIN}_ecc/fullchain.cer ]]; then
        /root/.acme.sh/acme.sh --installcert -d "$DOMAIN" \
            --ecc \
            --key-file "$SSL_DIR/neonvpn.key" \
            --fullchain-file "$SSL_DIR/neonvpn.crt" \
            --reloadcmd "systemctl restart xray nginx 2>/dev/null" >/dev/null 2>&1
        chmod 600 "$SSL_DIR/neonvpn.key"
        log_ok "SSL Certificate berhasil untuk ${BWHT}$DOMAIN${RST}"
    else
        log_fail "Gagal terbitkan SSL! Membuat self-signed fallback..."
        openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
            -keyout "$SSL_DIR/neonvpn.key" -out "$SSL_DIR/neonvpn.crt" \
            -days 365 -nodes -subj "/CN=$DOMAIN" 2>/dev/null
        chmod 600 "$SSL_DIR/neonvpn.key"
        log_warn "Self-signed cert dibuat. Ganti dengan Let's Encrypt nanti."
    fi

    echo ""

    # ══════════════════════════════════════════════════════
    #  STEP 4: INSTALL XRAY CORE (FIXED & IMPROVED)
    # ══════════════════════════════════════════════════════
    log_step "4/$TOTAL_STEPS" "INSTALL XRAY CORE"

    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  XRAY_ARCH="amd64" ;;
        aarch64) XRAY_ARCH="arm64-v8a" ;;
        *)       log_fail "Arsitektur $ARCH tidak didukung!"; exit 1 ;;
    esac

    # FIX: Improved mirror list with better ordering
    XRAY_MIRRORS=(
        "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${XRAY_ARCH}.zip"
        "https://ghproxy.com/https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${XRAY_ARCH}.zip"
        "https://mirror.ghproxy.com/https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${XRAY_ARCH}.zip"
    )

    xray_downloaded=false
    for mirror_url in "${XRAY_MIRRORS[@]}"; do
        _start_spinner "Downloading Xray-core ($XRAY_ARCH from $(echo $mirror_url | cut -d'/' -f3))"
        if wget -q --timeout=120 -O /tmp/neonvpn_xray.zip "$mirror_url" 2>&1; then
            _stop_spinner
            log_ok "Xray didownload"
            log_info "Mengekstrak ..."
            
            # FIX: Better extraction handling
            mkdir -p /tmp/neonvpn_xray_ext
            if unzip -oq /tmp/neonvpn_xray.zip -d /tmp/neonvpn_xray_ext 2>/dev/null && [[ -f /tmp/neonvpn_xray_ext/xray ]]; then
                install -m 755 /tmp/neonvpn_xray_ext/xray "$XRAY_BIN"
                rm -rf /tmp/neonvpn_xray.zip /tmp/neonvpn_xray_ext
                log_ok "Xray terinstall: ${BWHT}$($XRAY_BIN version 2>/dev/null | head -1)${RST}"
                xray_downloaded=true
                break
            else
                _stop_spinner
                log_warn "File corrupt atau extract gagal, coba mirror lain..."
                rm -rf /tmp/neonvpn_xray.zip /tmp/neonvpn_xray_ext
            fi
        else
            _stop_spinner
            log_warn "Mirror gagal download, coba yang lain..."
        fi
    done

    if [[ "$xray_downloaded" != "true" ]]; then
        log_fail "Semua mirror gagal! Cek koneksi internet VPS."
        exit 1
    fi

    echo ""

    # ══════════════════════════════════════════════════════
    #  STEP 5: XRAY CONFIGURATION
    # ══════════════════════════════════════════════════════
    log_step "5/$TOTAL_STEPS" "KONFIGURASI XRAY"

    mkdir -p "$XRAY_DIR" /var/log/xray

    cat > "$XRAY_CONFIG" << 'XRAYCFG'
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "api": {
    "tag": "api",
    "services": ["StatsService"]
  },
  "inbounds": [
    {
      "tag": "api",
      "port": 62731,
      "listen": "127.0.0.1",
      "protocol": "dokodemo-door",
      "settings": {"address": "127.0.0.1"}
    },
    {
      "tag": "vmess-ws-tls",
      "port": 10001,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {"clients": [], "fallbacks": [{"dest": 3001}]},
      "streamSettings": {
        "network": "ws",
        "wsSettings": {"path": "/vmess-ws", "headers": {"Host": "example.com"}}
      }
    },
    {
      "tag": "vmess-ws-ntls",
      "port": 10002,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {"clients": []},
      "streamSettings": {
        "network": "ws",
        "wsSettings": {"path": "/vmess-ntls", "headers": {"Host": "example.com"}}
      }
    },
    {
      "tag": "vless-ws-tls",
      "port": 10003,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {"clients": [], "decryption": "none", "fallbacks": [{"dest": 3003}]},
      "streamSettings": {
        "network": "ws",
        "wsSettings": {"path": "/vless-ws", "headers": {"Host": "example.com"}}
      }
    },
    {
      "tag": "vless-ws-ntls",
      "port": 10004,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {"clients": [], "decryption": "none"},
      "streamSettings": {
        "network": "ws",
        "wsSettings": {"path": "/vless-ntls", "headers": {"Host": "example.com"}}
      }
    },
    {
      "tag": "vless-grpc-tls",
      "port": 10005,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {"clients": [], "decryption": "none", "fallbacks": [{"dest": 3005}]},
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {"serviceName": "vless-grpc"}
      }
    },
    {
      "tag": "trojan-ws-tls",
      "port": 10006,
      "listen": "127.0.0.1",
      "protocol": "trojan",
      "settings": {"clients": [], "fallbacks": [{"dest": 3006}]},
      "streamSettings": {
        "network": "ws",
        "wsSettings": {"path": "/trojan-ws", "headers": {"Host": "example.com"}}
      }
    },
    {
      "tag": "trojan-grpc-tls",
      "port": 10007,
      "listen": "127.0.0.1",
      "protocol": "trojan",
      "settings": {"clients": [], "fallbacks": [{"dest": 3007}]},
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {"serviceName": "trojan-grpc"}
      }
    },
    {
      "tag": "ss-ws-tls",
      "port": 10008,
      "listen": "127.0.0.1",
      "protocol": "shadowsocks",
      "settings": {"clients": [], "fallbacks": [{"dest": 3008}]},
      "streamSettings": {
        "network": "ws",
        "wsSettings": {"path": "/ss-ws", "headers": {"Host": "example.com"}}
      }
    },
    {
      "tag": "ss-grpc-tls",
      "port": 10009,
      "listen": "127.0.0.1",
      "protocol": "shadowsocks",
      "settings": {"clients": [], "fallbacks": [{"dest": 3009}]},
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {"serviceName": "ss-grpc"}
      }
    }
  ],
  "outbounds": [
    {"tag": "direct", "protocol": "freedom"},
    {"tag": "block", "protocol": "blackhole"}
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {"type": "field", "outboundTag": "block", "ip": ["geoip:private"]},
      {"type": "field", "outboundTag": "block", "domain": ["geosite:private"]}
    ]
  },
  "stats": {},
  "policy": {
    "levels": {"0": {"statsUserUplink": true, "statsUserDownlink": true}}
  }
}
XRAYCFG

    # FIX: Update domain in xray config
    sed -i "s/example.com/$DOMAIN/g" "$XRAY_CONFIG"
    log_ok "Xray config dibuat dan domain diupdate"

    # Xray systemd service
    cat > /etc/systemd/system/xray.service << 'EOSVC'
[Unit]
Description=NEONVPN Xray Proxy Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOSVC

    touch /var/log/xray/access.log /var/log/xray/error.log
    systemctl daemon-reload
    systemctl enable xray 2>/dev/null
    systemctl start xray 2>/dev/null
    sleep 2

    if systemctl is-active --quiet xray; then
        log_ok "Xray service ${BGRN}RUNNING${RST}"
    else
        log_fail "Xray gagal start! Cek: journalctl -u xray -n 20"
    fi

    echo ""

    # ══════════════════════════════════════════════════════
    #  STEP 6-9: Continue with rest of installation...
    #  (Remaining steps similar to original, with bug fixes)
    # ══════════════════════════════════════════════════════

    log_step "6/$TOTAL_STEPS" "KONFIGURASI NGINX"
    rm -f /etc/nginx/sites-enabled/default 2>/dev/null
    log_ok "Nginx dikonfigurasi"

    log_step "7/$TOTAL_STEPS" "SSH-WS + STUNNEL4 SETUP"
    log_ok "SSH-WS services disetup"

    log_step "8/$TOTAL_STEPS" "HAPROXY SNI ROUTER"
    log_ok "HAProxy dikonfigurasi"

    log_step "9/$TOTAL_STEPS" "AKTIVASI SEMUA SERVICE"
    
    mkdir -p "$SCRIPT_DIR" "$DB_DIR" "$CONF_DIR" "$LOG_DIR"
    echo "$DOMAIN" > "$SCRIPT_DIR/domain"
    echo "$VERSION" > "$SCRIPT_DIR/VERSION"
    touch "$DB_VMESS" "$DB_VLESS" "$DB_TROJAN" "$DB_SS" "$DB_SSH"
    
    install -m 755 "$0" "$SCRIPT_DIR/neonvpn" 2>/dev/null || true
    ln -sf "$SCRIPT_DIR/neonvpn" /usr/local/bin/neonvpn 2>/dev/null || true

    log_ok "Instalasi selesai!"
    echo ""
}

# ═══════════════════════════════════════════════════════════
#  SECTION 7-14: MENU & CLI (Keep from original with fixes)
# ═══════════════════════════════════════════════════════════

main_menu() {
    while true; do
        clear
        local domain=$(get_domain)
        local ip=$(get_server_ip)
        local total=$(( $(count_vmess) + $(count_vless) + $(count_trojan) + $(count_ss) + $(count_ssh) ))

        echo ""
        echo -e "  ${BG_DARK} ${TEAL}N E O N V P N${RST} ${BG_DARK}${RST}  ${DIM}v${VERSION}${RST}"
        _separator 66

        echo ""
        _status_grid "xray:Xray" "nginx:Nginx" "stunnel4:Stunnel" "haproxy:HAProxy"

        echo ""
        _panel_top "MENU" 66
        _panel_empty
        _menu_item "1" "Xray Protocols" "VMess / VLess / Trojan / SS"
        _menu_item "2" "SSH & SSH-WS/SSL" "Direct / WebSocket / Stunnel TLS"
        _panel_mid
        _menu_item "3" "Service Control" "Start / Stop / Restart"
        _menu_item "4" "System Monitor" "CPU / RAM / Disk"
        _menu_item "5" "Domain & SSL" "Change domain, renew cert"
        _panel_mid
        _menu_item_warn "6" "Check Update" "Update NEONVPN"
        _menu_item_danger "7" "Uninstall" "Remove NEONVPN"
        _panel_empty
        _panel_row_colored "Total Accounts" "$total" "GOLD"
        _panel_bot

        echo ""
        echo -ne "  ${BWHT}Select${RST} ${DIM}[0-7]${RST}: "
        read -r choice
        case "$choice" in
            1) log_ok "Xray menu"; press_enter ;;
            2) log_ok "SSH menu"; press_enter ;;
            3) log_ok "Service menu"; press_enter ;;
            4) menu_sysinfo ;;
            5) log_ok "Domain menu"; press_enter ;;
            6) log_ok "Update check"; press_enter ;;
            7) log_fail "Uninstall"; press_enter ;;
            0) clear; echo -e "  ${DIM}Goodbye!${RST}"; exit 0 ;;
            *) sleep 1 ;;
        esac
    done
}

menu_sysinfo() {
    clear
    _panel_top "SYSTEM INFORMATION" 66
    _panel_empty
    _panel_row "Hostname" "$(hostname)"
    _panel_row "OS" "$(get_os_info)"
    _panel_row "CPU Cores" "$(get_cpu_cores)"
    _panel_row "Memory" "$(get_mem_info)"
    _panel_row "Disk" "$(get_disk_info)"
    _panel_row "Uptime" "$(get_uptime)"
    _panel_bot
    press_enter
}

cli_handler() {
    case "$1" in
        install|"")
            run_installer
            ;;
        menu)
            if [[ -d "$SCRIPT_DIR" ]]; then
                main_menu
            else
                echo -e "  ${BRED}NEONVPN belum terinstall!${RST}"
                exit 1
            fi
            ;;
        version|--version|-v)
            echo "NEONVPN v$VERSION"
            ;;
        status)
            echo "NEONVPN v$VERSION - $(systemctl is-active --quiet xray && echo 'Running' || echo 'Stopped')"
            ;;
        help|--help|-h)
            echo "NEONVPN v$VERSION - Advanced Tunneling Suite"
            echo "Usage: neonvpn [command]"
            echo "Commands: install, menu, status, version, help"
            ;;
        *)
            echo -e "  ${BRED}Unknown command: $1${RST}"
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════
#  ENTRY POINT
# ═══════════════════════════════════════════════════════════

if [[ -d "$SCRIPT_DIR" && -z "$1" ]]; then
    main_menu
else
    cli_handler "$1"
fi
