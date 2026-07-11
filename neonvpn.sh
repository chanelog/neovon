#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  NEONVPN - Advanced Tunneling Suite                                        ║
# ║  Supports: SSH-WS/SSL (TLS/SSL/NTLS) + Xray (VMess/VLess/Trojan/SS)       ║
# ║  Single-file installer & management script                                 ║
# ║  Author: chanelog                                                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
# shellcheck disable=SC1090,SC2086,SC2143,SC2181,SC2034

# ═══════════════════════════════════════════════════════════
#  SECTION 1: GLOBAL VARIABLES & CONSTANTS
# ═══════════════════════════════════════════════════════════

VERSION="2.0.0"
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
log_step()  { echo -e "\n  ${BCYN}┌─ STEP $1 ───────────────────────────────────${RST}"; echo -e "  ${BCYN}│${RST} ${BWHT}$2${RST}"; echo -e "  ${BCYN}└────────────────────────────────────────────${RST}"; }

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
    tput civis 2>/dev/null
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
        kill "$_spinner_pid" 2>/dev/null
        wait "$_spinner_pid" 2>/dev/null
        _spinner_pid=""
        printf "\r%*s\r" 60 ""
    fi
    tput cnorm 2>/dev/null
}

# ─── Box Drawing (Modern Style - Rounded) ──────────────
# Uses ╭─╮│╰─╯ for rounded corners instead of ╔═╗║╚═╝

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

# ─── Menu Item (Unique Style) ──────────────────────────
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
    echo -e "  ${TEAL}  ███╗   ██╗███████╗██╗  ██╗██╗   ██╗${RST}  ${BWHT}A D V A N C E D${RST}  ${TEAL}  ███╗   ██╗███████╗██╗  ██╗██╗   ██╗${RST}"
    echo -e "  ${TEAL}  ████╗  ██║██╔════╝╚██╗██╔╝██║   ██║${RST}  ${SILVER}T U N N E L I N G${RST}  ${TEAL}  ████╗  ██║██╔════╝╚██╗██╔╝██║   ██║${RST}"
    echo -e "  ${TEAL}  ██╔██╗ ██║█████╗   ╚███╔╝ ██║   ██║${RST}  ${SILVER}   S U I T E   ${RST}  ${TEAL}  ██╔██╗ ██║█████╗   ╚███╔╝ ██║   ██║${RST}"
    echo -e "  ${TEAL}  ██║╚██╗██║██╔══╝   ██╔██╗ ██║   ██║${RST}                    ${TEAL}  ██║╚██╗██║██╔══╝   ██╔██╗ ██║   ██║${RST}"
    echo -e "  ${TEAL}  ██║ ╚████║███████╗██╔╝ ╚██╗╚██████╔╝${RST}   ${DIM}v${VERSION}${RST}         ${TEAL}  ██║ ╚████║███████╗██╔╝ ╚██╗╚██████╔╝${RST}"
    echo -e "  ${TEAL}  ╚═╝  ╚═══╝╚══════╝╚═╝   ╚═╝ ╚═════╝${RST}                    ${TEAL}  ╚═╝  ╚═══╝╚══════╝╚═╝   ╚═╝ ╚═════╝${RST}"
    echo -e "  ${TEAL}                                       ${RST}"
    echo -e "${RST}"
}

# ─── Separator Line ────────────────────────────────────
_separator() {
    local width="${1:-64}"
    echo -e "  ${DIM}$(printf '%*s' "$width" '' | tr ' ' '─')${RST}"
}

# ═══════════════════════════════════════════════════════════
#  SECTION 3: UTILITY FUNCTIONS
# ═══════════════════════════════════════════════════════════

# ─── Domain Helpers ─────────────────────────────────────
get_domain() {
    cat "$SCRIPT_DIR/domain" 2>/dev/null || echo "undefined"
}

get_server_ip() {
    curl -s4 --max-time 5 https://ifconfig.me 2>/dev/null || \
    curl -s4 --max-time 5 https://api.ipify.org 2>/dev/null || \
    curl -s4 --max-time 5 https://ipv4.icanhazip.com 2>/dev/null || \
    hostname -I | awk '{print $1}'
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
get_cpu_usage() { top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d. -f1 2>/dev/null || echo "?"; }
get_mem_info() { free -m | awk 'NR==2{printf "%sMB / %sMB (%.0f%%)", $3, $2, $3*100/$2}'; }
get_disk_info() { df -h / | awk 'NR==2{printf "%s / %s (%s)", $3, $2, $5}'; }
get_uptime() { uptime -p 2>/dev/null | sed 's/up //' || uptime | awk '{print $3,$4}' | sed 's/,//'; }
get_load_avg() { uptime | awk -F'load average: ' '{print $2}'; }
get_xray_version() { $XRAY_BIN version 2>/dev/null | head -1 | awk '{print $2}' || echo "N/A"; }
get_network_iface() { ip route | grep default | awk '{print $5}' | head -1; }

get_network_usage() {
    local iface=$(get_network_iface)
    if [[ -n "$iface" ]]; then
        local rx=$(cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null || echo 0)
        local tx=$(cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null || echo 0)
        echo "$(numfmt --to=iec $rx 2>/dev/null || echo ${rx}B) ↓ / $(numfmt --to=iec $tx 2>/dev/null || echo ${tx}B) ↑"
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
get_exp_date() { date -d "+${1} days" +"%Y-%m-%d"; }
days_until_exp() {
    local exp="$1"
    local today=$(date +%s)
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
#  SECTION 4: ACCOUNT MANAGEMENT
# ═══════════════════════════════════════════════════════════

# ─── SSH Accounts ───────────────────────────────────────
create_ssh() {
    local username="$1" days="$2" password="${3:-$(gen_ssh_password)}"
    local exp=$(get_exp_date "$days")
    local created=$(date +"%Y-%m-%d")
    useradd -e "$exp" -s /bin/false -M "$username" 2>/dev/null
    echo "$username:$password" | chpasswd 2>/dev/null
    echo "$username|$password|$exp|$created" >> "$DB_SSH"
    echo "$password"
}

delete_ssh() {
    local username="$1"
    userdel -f "$username" 2>/dev/null
    sed -i "/^${username}|/d" "$DB_SSH"
}

renew_ssh() {
    local username="$1" days="$2"
    local exp=$(get_exp_date "$days")
    chage -E "$exp" "$username" 2>/dev/null
    sed -i "s/^${username}|\\([^|]*\\)|\\([^|]*\\)|\\(.*\\)\$/${username}|\\1|${exp}|\\3/" "$DB_SSH"
}

get_ssh_info() { grep "^${1}|" "$DB_SSH" 2>/dev/null; }
list_ssh() { cat "$DB_SSH" 2>/dev/null; }
count_ssh() { wc -l < "$DB_SSH" 2>/dev/null || echo 0; }

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
    sed -i "/^${username}|/d" "$DB_VMESS"
    local tmp=$(mktemp)
    jq --arg email "$username" \
        '(.inbounds[] | select(.tag | startswith("vmess")) | .settings.clients) |= map(select(.email != $email))' \
        "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"
    systemctl reload xray 2>/dev/null || systemctl restart xray 2>/dev/null
}

renew_vmess() {
    local username="$1" days="$2"
    local exp=$(get_exp_date "$days")
    sed -i "s/^${username}|\\([^|]*\\)|\\([^|]*\\)|\\(.*\\)\$/${username}|\\1|${exp}|\\3/" "$DB_VMESS"
}

get_vmess_info() { grep "^${1}|" "$DB_VMESS" 2>/dev/null; }
list_vmess() { cat "$DB_VMESS" 2>/dev/null; }
count_vmess() { wc -l < "$DB_VMESS" 2>/dev/null || echo 0; }

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
    sed -i "/^${username}|/d" "$DB_VLESS"
    local tmp=$(mktemp)
    jq --arg email "$username" \
        '(.inbounds[] | select(.tag | startswith("vless")) | .settings.clients) |= map(select(.email != $email))' \
        "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"
    systemctl reload xray 2>/dev/null || systemctl restart xray 2>/dev/null
}

renew_vless() {
    local username="$1" days="$2"
    local exp=$(get_exp_date "$days")
    sed -i "s/^${username}|\\([^|]*\\)|\\([^|]*\\)|\\(.*\\)\$/${username}|\\1|${exp}|\\3/" "$DB_VLESS"
}

get_vless_info() { grep "^${1}|" "$DB_VLESS" 2>/dev/null; }
list_vless() { cat "$DB_VLESS" 2>/dev/null; }
count_vless() { wc -l < "$DB_VLESS" 2>/dev/null || echo 0; }

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
    sed -i "/^${username}|/d" "$DB_TROJAN"
    local tmp=$(mktemp)
    jq --arg email "$username" \
        '(.inbounds[] | select(.tag | startswith("trojan")) | .settings.clients) |= map(select(.email != $email))' \
        "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"
    systemctl reload xray 2>/dev/null || systemctl restart xray 2>/dev/null
}

renew_trojan() {
    local username="$1" days="$2"
    local exp=$(get_exp_date "$days")
    sed -i "s/^${username}|\\([^|]*\\)|\\([^|]*\\)|\\(.*\\)\$/${username}|\\1|${exp}|\\3/" "$DB_TROJAN"
}

get_trojan_info() { grep "^${1}|" "$DB_TROJAN" 2>/dev/null; }
list_trojan() { cat "$DB_TROJAN" 2>/dev/null; }
count_trojan() { wc -l < "$DB_TROJAN" 2>/dev/null || echo 0; }

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
    sed -i "/^${username}|/d" "$DB_SS"
    local tmp=$(mktemp)
    jq --arg pass "$(grep "^${username}|" "$DB_SS" | cut -d'|' -f2)" \
        '(.inbounds[] | select(.tag | startswith("ss-")) | .settings.clients) |= map(select(.password != $pass))' \
        "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"
    systemctl reload xray 2>/dev/null || systemctl restart xray 2>/dev/null
}

renew_ss() {
    local username="$1" days="$2"
    local exp=$(get_exp_date "$days")
    sed -i "s/^${username}|\\([^|]*\\)|\\([^|]*\\)|\\([^|]*\\)|\\(.*\\)\$/${username}|\\1|\\2|${exp}|\\4/" "$DB_SS"
}

get_ss_info() { grep "^${1}|" "$DB_SS" 2>/dev/null; }
list_ss() { cat "$DB_SS" 2>/dev/null; }
count_ss() { wc -l < "$DB_SS" 2>/dev/null || echo 0; }

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
    local json="{\"v\":\"2\",\"ps\":\"${remark:-$user-vmess-$type}\",\"add\":\"$domain\",\"port\":\"$port\",\"id\":\"$uuid\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"$domain\",\"path\":\"$path\",\"tls\":\"$([ "$type" == "tls" ] && echo "tls" || echo "")\",\"sni\":\"$domain\"}"
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
#  SECTION 6: INSTALLATION ENGINE
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
    echo -e "  ${BGRN}✓${RST} ${WHT}OS: ${BWHT}$PRETTY_NAME${RST} ($KERNEL)"

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
    #  STEP 4: INSTALL XRAY CORE
    # ══════════════════════════════════════════════════════
    log_step "4/$TOTAL_STEPS" "INSTALL XRAY CORE"

    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  XRAY_ARCH="amd64" ;;
        aarch64) XRAY_ARCH="arm64-v8a" ;;
        *)       log_fail "Arsitektur $ARCH tidak didukung!"; exit 1 ;;
    esac

    XRAY_MIRRORS=(
        "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${XRAY_ARCH}.zip"
        "https://ghfast.top/https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${XRAY_ARCH}.zip"
        "https://gh-proxy.com/https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${XRAY_ARCH}.zip"
        "https://mirror.ghproxy.com/https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${XRAY_ARCH}.zip"
    )

    xray_downloaded=false
    for mirror_url in "${XRAY_MIRRORS[@]}"; do
        _start_spinner "Downloading Xray-core ($XRAY_ARCH)"
        if wget -q --timeout=120 "$mirror_url" -O /tmp/neonvpn_xray.zip 2>&1; then
            _stop_spinner
            log_ok "Xray didownload"
            log_info "Mengekstrak ..."
            unzip -oq /tmp/neonvpn_xray.zip -d /tmp/neonvpn_xray_ext
            if [[ -f /tmp/neonvpn_xray_ext/xray ]]; then
                install -m 755 /tmp/neonvpn_xray_ext/xray "$XRAY_BIN"
                rm -rf /tmp/neonvpn_xray.zip /tmp/neonvpn_xray_ext
                log_ok "Xray terinstall: ${BWHT}$($XRAY_BIN version 2>/dev/null | head -1)${RST}"
                xray_downloaded=true
                break
            else
                _stop_spinner
                log_warn "File corrupt, coba mirror lain..."
                rm -rf /tmp/neonvpn_xray.zip /tmp/neonvpn_xray_ext
            fi
        else
            _stop_spinner
            log_warn "Mirror gagal, coba yang lain..."
        fi
    done

    if [[ "$xray_downloaded" != "true" ]]; then
        log_fail "Semua mirror gagal! Cek koneksi internet VPS."
        log_info "Coba manual: wget yang url di atas di VPS kamu"
        exit 1
    fi

    echo ""

    # ══════════════════════════════════════════════════════
    #  STEP 5: XRAY CONFIGURATION
    # ══════════════════════════════════════════════════════
    log_step "5/$TOTAL_STEPS" "KONFIGURASI XRAY"

    mkdir -p "$XRAY_DIR" /var/log/xray

    cat > "$XRAY_CONFIG" << XRAYCFG
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
      "port": $XRAY_API_PORT,
      "listen": "127.0.0.1",
      "protocol": "dokodemo-door",
      "settings": {"address": "127.0.0.1"}
    },
    {
      "tag": "vmess-ws-tls",
      "port": $XRAY_VMESS_WS_TLS_PORT,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {"clients": [], "fallbacks": [{"dest": 3001}]},
      "streamSettings": {
        "network": "ws",
        "wsSettings": {"path": "/vmess-ws", "headers": {"Host": "$DOMAIN"}}
      }
    },
    {
      "tag": "vmess-ws-ntls",
      "port": $XRAY_VMESS_WS_NTLS_PORT,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {"clients": []},
      "streamSettings": {
        "network": "ws",
        "wsSettings": {"path": "/vmess-ntls", "headers": {"Host": "$DOMAIN"}}
      }
    },
    {
      "tag": "vless-ws-tls",
      "port": $XRAY_VLESS_WS_TLS_PORT,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {"clients": [], "decryption": "none", "fallbacks": [{"dest": 3003}]},
      "streamSettings": {
        "network": "ws",
        "wsSettings": {"path": "/vless-ws", "headers": {"Host": "$DOMAIN"}}
      }
    },
    {
      "tag": "vless-ws-ntls",
      "port": $XRAY_VLESS_WS_NTLS_PORT,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {"clients": [], "decryption": "none"},
      "streamSettings": {
        "network": "ws",
        "wsSettings": {"path": "/vless-ntls", "headers": {"Host": "$DOMAIN"}}
      }
    },
    {
      "tag": "vless-grpc-tls",
      "port": $XRAY_VLESS_GRPC_TLS_PORT,
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
      "port": $XRAY_TROJAN_WS_TLS_PORT,
      "listen": "127.0.0.1",
      "protocol": "trojan",
      "settings": {"clients": [], "fallbacks": [{"dest": 3006}]},
      "streamSettings": {
        "network": "ws",
        "wsSettings": {"path": "/trojan-ws", "headers": {"Host": "$DOMAIN"}}
      }
    },
    {
      "tag": "trojan-grpc-tls",
      "port": $XRAY_TROJAN_GRPC_TLS_PORT,
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
      "port": $XRAY_SS_WS_TLS_PORT,
      "listen": "127.0.0.1",
      "protocol": "shadowsocks",
      "settings": {"clients": [], "fallbacks": [{"dest": 3008}]},
      "streamSettings": {
        "network": "ws",
        "wsSettings": {"path": "/ss-ws", "headers": {"Host": "$DOMAIN"}}
      }
    },
    {
      "tag": "ss-grpc-tls",
      "port": $XRAY_SS_GRPC_TLS_PORT,
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

    log_ok "Xray config dibuat"

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
    sleep 1

    if systemctl is-active --quiet xray; then
        log_ok "Xray service ${BGRN}RUNNING${RST}"
    else
        log_fail "Xray gagal start! Cek: journalctl -u xray -n 20"
    fi

    echo ""

    # ══════════════════════════════════════════════════════
    #  STEP 6: NGINX CONFIGURATION
    # ══════════════════════════════════════════════════════
    log_step "6/$TOTAL_STEPS" "KONFIGURASI NGINX"

    rm -f /etc/nginx/sites-enabled/default 2>/dev/null

    cat > /etc/nginx/conf.d/neonvpn.conf << NGINXCFG
# ─── NEONVPN - Nginx Configuration ──────────────────────
# Domain: $DOMAIN

# --- NON-TLS (Port 80) ---
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location /vmess-ntls {
        proxy_pass http://127.0.0.1:$XRAY_VMESS_WS_NTLS_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }

    location /vless-ntls {
        proxy_pass http://127.0.0.1:$XRAY_VLESS_WS_NTLS_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

# --- TLS (Port 443 or Internal) ---
server {
    listen 127.0.0.1:$NGINX_TLS_INTERNAL_PORT ssl http2;
    server_name $DOMAIN;

    ssl_certificate     $SSL_DIR/neonvpn.crt;
    ssl_certificate_key $SSL_DIR/neonvpn.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    location /vmess-ws {
        proxy_pass http://127.0.0.1:$XRAY_VMESS_WS_TLS_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }

    location /vless-ws {
        proxy_pass http://127.0.0.1:$XRAY_VLESS_WS_TLS_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }

    location /trojan-ws {
        proxy_pass http://127.0.0.1:$XRAY_TROJAN_WS_TLS_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }

    location /ss-ws {
        proxy_pass http://127.0.0.1:$XRAY_SS_WS_TLS_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }

    location /vless-grpc {
        grpc_pass grpc://127.0.0.1:$XRAY_VLESS_GRPC_TLS_PORT;
    }

    location /trojan-grpc {
        grpc_pass grpc://127.0.0.1:$XRAY_TROJAN_GRPC_TLS_PORT;
    }

    location /ss-grpc {
        grpc_pass grpc://127.0.0.1:$XRAY_SS_GRPC_TLS_PORT;
    }

    location / {
        return 200 '{"neonvpn":"running","version":"$VERSION"}';
        add_header Content-Type application/json;
    }
}
NGINXCFG

    if nginx -t 2>/dev/null; then
        systemctl enable nginx 2>/dev/null
        systemctl restart nginx 2>/dev/null
        log_ok "Nginx dikonfigurasi (internal port $NGINX_TLS_INTERNAL_PORT)"
    else
        log_fail "nginx -t gagal! Cek konfigurasi."
    fi

    echo ""

    # ══════════════════════════════════════════════════════
    #  STEP 7: SSH-WS + STUNNEL4 SETUP
    # ══════════════════════════════════════════════════════
    log_step "7/$TOTAL_STEPS" "SSH-WS + STUNNEL4 (TLS/SSL/NTLS)"

    local PYTHON_BIN=$(command -v python3)

    # --- 7a: Create ws-stunnel Python script ---
    log_info "Membuat ws-stunnel (SSH over WebSocket) ..."
    cat > "$BIN_DIR/ws-stunnel" << 'WSEOF'
#!/usr/bin/env python3
import sys, socket, struct, hashlib, base64, select, signal, http.server
DEFAULT_HOST="127.0.0.1"; DEFAULT_PORT=22; GUID="258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.headers.get("Upgrade","").lower()!="websocket": self.send_error(400); return
        k=self.headers.get("Sec-WebSocket-Key","")
        a=base64.b64encode(hashlib.sha1((k+GUID).encode()).digest()).decode()
        xrh=self.headers.get("X-Real-Host",""); hp=xrh.split(":") if xrh else []
        bh,bp=(hp[0],int(hp[1])) if len(hp)==2 else (DEFAULT_HOST,DEFAULT_PORT) if not xrh else (xrh,DEFAULT_PORT)
        self.send_response(101); self.send_header("Upgrade","websocket")
        self.send_header("Connection","Upgrade"); self.send_header("Sec-WebSocket-Accept",a); self.end_headers()
        c=self.connection; b=socket.socket(); b.connect((bh,bp))
        try:
            while True:
                r,_,_=select.select([c,b],[],[],3600)
                if not r: break
                for s in r:
                    try:
                        d=s.recv(65536)
                        if not d: return
                        if s is c:
                            for fr in self._df(d): b.sendall(fr)
                        else: c.sendall(self._ef(d))
                    except: return
        except: pass
        finally:
            try: b.close()
            except: pass
    def _df(self,data):
        fs=[]; i=0
        while i<len(data):
            if i+2>len(data): break
            b1,b2=data[i],data[i+1]; i+=2; op=b1&0xf; mk=(b2>>7)&1; ln=b2&0x7f; msk=None
            if ln==126:
                if i+2>len(data): break; ln=struct.unpack(">H",data[i:i+2])[0]; i+=2
            elif ln==127:
                if i+8>len(data): break; ln=struct.unpack(">Q",data[i:i+8])[0]; i+=8
            if mk:
                if i+4>len(data): break; msk=data[i:i+4]; i+=4
            if i+ln>len(data): break; pl=bytearray(data[i:i+ln]); i+=ln
            if msk and msk:
                for j in range(len(pl)): pl[j]^=msk[j%4]
            if op==8: return fs
            if op in(1,2) and pl: fs.append(bytes(pl))
        return fs
    def _ef(self,data):
        ln=len(data); h=bytearray([0x82])
        if ln<126: h.append(ln)
        elif ln<65536: h+=bytearray([126])+struct.pack(">H",ln)
        else: h+=bytearray([127])+struct.pack(">Q",ln)
        return bytes(h)+data
    def log_message(self,*a): pass
if __name__=="__main__":
    p=int(sys.argv[1]) if len(sys.argv)>1 else 700
    s=http.server.HTTPServer(("0.0.0.0",p),H)
    signal.signal(signal.SIGTERM,lambda *_:(s.shutdown(),sys.exit(0)))
    s.serve_forever()
WSEOF
    chmod 755 "$BIN_DIR/ws-stunnel"
    log_ok "ws-stunnel terinstall"

    # --- 7b: Create ws-openssh ---
    cat > "$BIN_DIR/ws-openssh" << 'WSEOF2'
#!/usr/bin/env python3
import sys, socket, struct, hashlib, base64, select, signal, http.server
DEFAULT_HOST="127.0.0.1"; DEFAULT_PORT=22; GUID="258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.headers.get("Upgrade","").lower()!="websocket": self.send_error(400); return
        k=self.headers.get("Sec-WebSocket-Key","")
        a=base64.b64encode(hashlib.sha1((k+GUID).encode()).digest()).decode()
        self.send_response(101); self.send_header("Upgrade","websocket")
        self.send_header("Connection","Upgrade"); self.send_header("Sec-WebSocket-Accept",a); self.end_headers()
        c=self.connection; b=socket.socket(); b.connect((DEFAULT_HOST,DEFAULT_PORT))
        try:
            while True:
                r,_,_=select.select([c,b],[],[],3600)
                if not r: break
                for s in r:
                    try:
                        d=s.recv(65536)
                        if not d: return
                        if s is c:
                            for fr in self._df(d): b.sendall(fr)
                        else: c.sendall(self._ef(d))
                    except: return
        except: pass
        finally:
            try: b.close()
            except: pass
    def _df(self,data):
        fs=[]; i=0
        while i<len(data):
            if i+2>len(data): break
            b1,b2=data[i],data[i+1]; i+=2; op=b1&0xf; mk=(b2>>7)&1; ln=b2&0x7f; msk=None
            if ln==126:
                if i+2>len(data): break; ln=struct.unpack(">H",data[i:i+2])[0]; i+=2
            elif ln==127:
                if i+8>len(data): break; ln=struct.unpack(">Q",data[i:i+8])[0]; i+=8
            if mk:
                if i+4>len(data): break; msk=data[i:i+4]; i+=4
            if i+ln>len(data): break; pl=bytearray(data[i:i+ln]); i+=ln
            if msk and msk:
                for j in range(len(pl)): pl[j]^=msk[j%4]
            if op==8: return fs
            if op in(1,2) and pl: fs.append(bytes(pl))
        return fs
    def _ef(self,data):
        ln=len(data); h=bytearray([0x82])
        if ln<126: h.append(ln)
        elif ln<65536: h+=bytearray([126])+struct.pack(">H",ln)
        else: h+=bytearray([127])+struct.pack(">Q",ln)
        return bytes(h)+data
    def log_message(self,*a): pass
if __name__=="__main__":
    p=int(sys.argv[1]) if len(sys.argv)>1 else 2093
    s=http.server.HTTPServer(("0.0.0.0",p),H)
    signal.signal(signal.SIGTERM,lambda *_:(s.shutdown(),sys.exit(0)))
    s.serve_forever()
WSEOF2
    chmod 755 "$BIN_DIR/ws-openssh"
    log_ok "ws-openssh terinstall"

    # --- 7c: Create ws-dropbear ---
    sed 's/DEFAULT_PORT=22/DEFAULT_PORT=109/' "$BIN_DIR/ws-openssh" > "$BIN_DIR/ws-dropbear"
    sed -i "s/else 2093/else 2095/" "$BIN_DIR/ws-dropbear"
    chmod 755 "$BIN_DIR/ws-dropbear"
    log_ok "ws-dropbear terinstall"

    # --- 7d: Systemd services for WS scripts ---
    for svc_name in ws-stunnel ws-openssh ws-dropbear; do
        local svc_port
        case "$svc_name" in
            ws-stunnel)  svc_port="$WS_STUNNEL_LOCAL_PORT" ;;
            ws-openssh)  svc_port="$WS_OPENSSH_PORT" ;;
            ws-dropbear) svc_port="$WS_DROPBEAR_PORT" ;;
        esac

        cat > /etc/systemd/system/${svc_name}.service << SVCEOF
[Unit]
Description=NEONVPN SSH over WebSocket (${svc_name})
After=network.target

[Service]
Type=simple
ExecStart=$PYTHON_BIN -O $BIN_DIR/${svc_name} ${svc_port}
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
SVCEOF
    done

    # --- 7e: Stunnel4 configuration ---
    log_info "Konfigurasi Stunnel4 ..."

    # Create stunnel SSL cert from ACME cert
    if [[ -f "$SSL_DIR/neonvpn.crt" && -f "$SSL_DIR/neonvpn.key" ]]; then
        cat "$SSL_DIR/neonvpn.crt" "$SSL_DIR/neonvpn.key" > /etc/stunnel/stunnel.pem
    else
        openssl req -x509 -newkey rsa:2048 -keyout /tmp/st.key -out /tmp/st.crt \
            -days 365 -nodes -subj "/CN=${DOMAIN:-localhost}" 2>/dev/null
        cat /tmp/st.crt /tmp/st.key > /etc/stunnel/stunnel.pem
        rm -f /tmp/st.key /tmp/st.crt
    fi
    chmod 600 /etc/stunnel/stunnel.pem

    # Write clean stunnel config
    cat > /etc/stunnel/stunnel.conf << STUNCFG
pid = /var/run/stunnel4.pid

[ssh-ssl]
accept = $STUNNEL_SSL_PORT
connect = 127.0.0.1:$WS_STUNNEL_LOCAL_PORT
cert = /etc/stunnel/stunnel.pem
STUNCFG

    sed -i 's/^ENABLED=0/ENABLED=1/' /etc/default/stunnel4 2>/dev/null
    grep -q "^ENABLED=" /etc/default/stunnel4 2>/dev/null || echo "ENABLED=1" >> /etc/default/stunnel4

    log_ok "Stunnel4: port $STUNNEL_SSL_PORT → 127.0.0.1:$WS_STUNNEL_LOCAL_PORT"

    echo ""

    # ══════════════════════════════════════════════════════
    #  STEP 8: HAPROXY SNI ROUTER
    # ══════════════════════════════════════════════════════
    log_step "8/$TOTAL_STEPS" "HAPROXY SNI ROUTER (Port 443)"

    apt-get install -y -qq haproxy >/dev/null 2>&1

    cat > /etc/haproxy/haproxy.cfg << HAPCFG
# ═══════════════════════════════════════════════════════════
# NEONVPN - HAProxy SNI Router
# Port 443 -> Nginx/Xray (SNI=$DOMAIN) or Stunnel4 (SNI!=domain)
# ═══════════════════════════════════════════════════════════

global
    log /dev/log local0
    log /dev/log local1 notice
    maxconn 4096
    daemon

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 5s
    timeout client  300s
    timeout server  300s
    retries 3

frontend ssl_front
    bind *:443
    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }

    acl is_xray req_ssl_sni -i $DOMAIN
    use_backend xray_nginx if is_xray
    default_backend stunnel_ssh

backend xray_nginx
    server nginx 127.0.0.1:$NGINX_TLS_INTERNAL_PORT

backend stunnel_ssh
    server stunnel 127.0.0.1:$STUNNEL_SSL_PORT
HAPCFG

    sed -i 's/ENABLED=0/ENABLED=1/' /etc/default/haproxy 2>/dev/null
    grep -q "^ENABLED=" /etc/default/haproxy 2>/dev/null || echo "ENABLED=1" >> /etc/default/haproxy

    log_ok "HAProxy config dibuat"

    echo ""

    # ══════════════════════════════════════════════════════
    #  STEP 9: START ALL SERVICES & FINALIZE
    # ══════════════════════════════════════════════════════
    log_step "9/$TOTAL_STEPS" "AKTIVASI SEMUA SERVICE"

    systemctl daemon-reload

    local services=(xray nginx ws-stunnel ws-openssh ws-dropbear stunnel4 haproxy)
    local svc_ok=0 svc_fail=0

    for svc in "${services[@]}"; do
        echo -ne "  ${TEAL}◆${RST} ${WHT}Starting $svc ...${RST}  "
        systemctl enable "$svc" 2>/dev/null
        systemctl restart "$svc" 2>/dev/null
        sleep 0.5
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            echo -e "${BGRN}● ACTIVE${RST}"
            ((svc_ok++))
        else
            echo -e "${DIM}● INACTIVE${RST}"
            ((svc_fail++))
        fi
    done

    # --- Firewall ---
    echo ""
    log_info "Membuka port firewall ..."
    for port in 80 443 $WS_OPENSSH_PORT $WS_DROPBEAR_PORT $STUNNEL_SSL_PORT $WSTUNNEL_PORT; do
        iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || \
        iptables -I INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null
    done
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4 2>/dev/null
    log_ok "Firewall configured"

    # --- Create script directories ---
    mkdir -p "$SCRIPT_DIR" "$DB_DIR" "$CONF_DIR" "$LOG_DIR"

    # Save domain
    echo "$DOMAIN" > "$SCRIPT_DIR/domain"

    # Save version
    echo "$VERSION" > "$SCRIPT_DIR/VERSION"

    # Create empty databases
    touch "$DB_VMESS" "$DB_VLESS" "$DB_TROJAN" "$DB_SS" "$DB_SSH"

    # Create cleanup cronjob
    grep -q "neonvpn-cleanup" /etc/crontab 2>/dev/null || \
    echo "0 3 * * * root $SCRIPT_DIR/neonvpn cleanup-expired >> $LOG_DIR/cleanup.log 2>&1" >> /etc/crontab

    # Install menu script
    install -m 755 "$0" "$SCRIPT_DIR/neonvpn"
    ln -sf "$SCRIPT_DIR/neonvpn" /usr/local/bin/neonvpn 2>/dev/null

    echo ""
    echo ""

    # ══════════════════════════════════════════════════════
    #  INSTALLATION SUMMARY
    # ══════════════════════════════════════════════════════
    local ip=$(get_server_ip)

    _panel_top "INSTALLATION COMPLETE" 66
    _panel_empty
    _panel_row "Domain" "$DOMAIN"
    _panel_row "Server IP" "$ip"
    _panel_row "Version" "$VERSION"
    _panel_mid
    _panel_row "Service OK" "$svc_ok / ${#services[@]}"
    _panel_row "Service Fail" "$svc_fail"
    _panel_mid
    _panel_row_colored "Xray" "VMess / VLess / Trojan / SS" "BGRN"
    _panel_row_colored "SSH-WS OpenSSH" "port $WS_OPENSSH_PORT" "BGRN"
    _panel_row_colored "SSH-WS Dropbear" "port $WS_DROPBEAR_PORT" "BGRN"
    _panel_row_colored "SSH-SSL (Stunnel)" "port $STUNNEL_SSL_PORT" "BGRN"
    _panel_row_colored "HAProxy SNI" "port 443" "BGRN"
    _panel_mid
    _panel_row_colored "Port 443 Rule" "SNI=domain → Xray, else → Stunnel4" "TEAL"
    _panel_empty
    _panel_row_colored "Menu Command" "neonvpn" "GOLD"
    _panel_bot

    echo ""
    echo -e "  ${DIM}Terima kasih telah menggunakan NEONVPN!${RST}"
    echo ""
}

# ═══════════════════════════════════════════════════════════
#  SECTION 7: MENU SYSTEM
# ═══════════════════════════════════════════════════════════

# ─── Main Menu ──────────────────────────────────────────
main_menu() {
    while true; do
        clear

        local domain=$(get_domain)
        local ip=$(get_server_ip)
        local total=$(( $(count_vmess) + $(count_vless) + $(count_trojan) + $(count_ss) + $(count_ssh) ))

        # ─── Render Header ────────────────────────────────
        echo ""
        echo -e "  ${BG_DARK} ${TEAL}N E O N V P N${RST} ${BG_DARK}                        ${RST}  ${DIM}v${VERSION}${RST}"
        echo -e "  ${TEAL}┌─────────────────────────────────────────────────────────┐${RST}"
        echo -e "  ${TEAL}│${RST}  ${SILVER}Domain${RST} ${DIM}∶${RST} ${BWHT}${domain}${RST}  ${DIM}│${RST}  ${SILVER}IP${RST} ${DIM}∶${RST} ${WHT}${ip}${RST}            ${TEAL}│${RST}"
        echo -e "  ${TEAL}└─────────────────────────────────────────────────────────┘${RST}"

        # ─── Status Grid ──────────────────────────────────
        echo ""
        _status_grid \
            "xray:Xray" "nginx:Nginx" "stunnel4:Stunnel" "haproxy:HAProxy" \
            "ws-stunnel:WS-Stun" "ws-openssh:WS-SSH" "ws-dropbear:WS-DB" "dropbear:Dropbear"

        echo ""
        _panel_top "MENU" 66
        _panel_empty
        _menu_item "1" "Xray Protocols" "VMess / VLess / Trojan / Shadowsocks"
        _menu_item "2" "SSH & SSH-WS/SSL" "Direct / WebSocket / Stunnel TLS"
        _panel_mid
        _menu_item "3" "Service Control" "Start / Stop / Restart services"
        _menu_item "4" "System Monitor" "CPU / RAM / Disk / Network"
        _menu_item "5" "Domain & SSL" "Change domain, renew certificate"
        _menu_item "6" "Account Cleanup" "Delete all expired accounts"
        _panel_mid
        _menu_item_warn "7" "Check Update" "Update NEONVPN to latest version"
        _menu_item_danger "8" "Uninstall" "Remove NEONVPN completely"
        _panel_empty
        _panel_row_colored "Total Accounts" "$total" "GOLD"
        _panel_bot

        echo ""
        echo -ne "  ${BWHT}Select${RST} ${DIM}[0-8]${RST} ${DIM}∶${RST} "
        read -r choice

        case "$choice" in
            1) menu_xray ;;
            2) menu_sshws ;;
            3) menu_services ;;
            4) menu_sysinfo ;;
            5) menu_domain ;;
            6) _do_cleanup ;;
            7) menu_update ;;
            8) menu_uninstall ;;
            0) clear; echo -e "  ${DIM}Goodbye!${RST}"; echo ""; exit 0 ;;
            *) sleep 1 ;;
        esac
    done
}

# ═══════════════════════════════════════════════════════════
#  SECTION 8: XRAY PROTOCOL MENU
# ═══════════════════════════════════════════════════════════

menu_xray() {
    while true; do
        clear
        local vm_c=$(count_vmess) vl_c=$(count_vless) tr_c=$(count_trojan) ss_c=$(count_ss)

        _panel_top "XRAY PROTOCOLS" 66
        _panel_row "VMess" "$vm_c accounts"
        _panel_row "VLess" "$vl_c accounts"
        _panel_row "Trojan" "$tr_c accounts"
        _panel_row "Shadowsocks" "$ss_c accounts"
        _panel_empty
        _menu_item "1" "VMess Management" ""
        _menu_item "2" "VLess Management" ""
        _menu_item "3" "Trojan Management" ""
        _menu_item "4" "Shadowsocks Management" ""
        _panel_mid
        _menu_item "5" "Delete All Expired" ""
        _panel_empty
        _menu_item_dim "0" "Back"
        _panel_bot

        echo ""
        echo -ne "  ${BWHT}Select${RST} ${DIM}[0-5]${RST} ${DIM}∶${RST} "
        read -r c
        case "$c" in
            1) _xray_sub "vmess" "VMess" ;;
            2) _xray_sub "vless" "VLess" ;;
            3) _xray_sub "trojan" "Trojan" ;;
            4) _xray_sub "ss" "Shadowsocks" ;;
            5) _do_cleanup ;;
            0) return ;;
        esac
    done
}

_xray_sub() {
    local type="$1" label="$2"
    while true; do
        clear
        local cnt
        case "$type" in
            vmess) cnt=$(count_vmess) ;;
            vless) cnt=$(count_vless) ;;
            trojan) cnt=$(count_trojan) ;;
            ss) cnt=$(count_ss) ;;
        esac

        _panel_top "${label} MANAGEMENT" 66
        _panel_row "Total Accounts" "$cnt"
        _panel_empty
        _menu_item "1" "Create ${label} Account" ""
        _menu_item "2" "Delete ${label} Account" ""
        _menu_item "3" "Extend Expiry" ""
        _menu_item "4" "List All Accounts" ""
        _panel_empty
        _menu_item_dim "0" "Back"
        _panel_bot

        echo ""
        echo -ne "  ${BWHT}Select${RST} ${DIM}[0-4]${RST} ${DIM}∶${RST} "
        read -r c
        case "$c" in
            1) _xray_create "$type" "$label" ;;
            2) _xray_delete "$type" "$label" ;;
            3) _xray_renew "$type" "$label" ;;
            4) _xray_list "$type" "$label" ;;
            0) return ;;
        esac
    done
}

_xray_create() {
    local type="$1" label="$2"
    clear
    _panel_top "CREATE ${label^^} ACCOUNT" 66
    _panel_empty
    echo -ne "  ${BWHT}Username${RST}    ${DIM}∶${RST} "; read -r user
    [[ -z "$user" ]] && { log_fail "Username kosong!"; press_enter; return; }

    local db_file
    case "$type" in
        vmess) db_file="$DB_VMESS" ;;
        vless) db_file="$DB_VLESS" ;;
        trojan) db_file="$DB_TROJAN" ;;
        ss) db_file="$DB_SS" ;;
    esac
    grep -q "^${user}|" "$db_file" && { log_fail "Username sudah ada!"; press_enter; return; }

    echo -ne "  ${BWHT}Active Days${RST} ${DIM}∶${RST} "; read -r days; days=${days:-30}
    [[ ! "$days" =~ ^[0-9]+$ ]] && { log_fail "Harus angka!"; press_enter; return; }

    local domain=$(get_domain)
    local exp=$(get_exp_date "$days")

    case "$type" in
        vmess)
            local key=$(create_vmess "$user" "$days")
            clear
            _panel_top "${label^^} ACCOUNT CREATED" 66
            _panel_empty
            _panel_row "Username" "$user"
            _panel_row "UUID" "$key"
            _panel_row "Domain" "$domain"
            _panel_row "Expired" "$exp ($days days)"
            _panel_mid
            _panel_row_colored "VMess TLS" "Port 443" "BGRN"
            _panel_row_colored "VMess non-TLS" "Port 80" "GOLD"
            _panel_bot
            echo ""
            local link_tls=$(gen_vmess_link "$user" "$key" "$domain" "tls")
            local link_ntls=$(gen_vmess_link "$user" "$key" "$domain" "ntls")
            echo -e "  ${TEAL}TLS Link${RST}  ${DIM}∶${RST} ${DIM}${link_tls}${RST}"
            echo -e "  ${GOLD}NTLS Link${RST} ${DIM}∶${RST} ${DIM}${link_ntls}${RST}"
            ;;
        vless)
            local key=$(create_vless "$user" "$days")
            clear
            _panel_top "${label^^} ACCOUNT CREATED" 66
            _panel_empty
            _panel_row "Username" "$user"
            _panel_row "UUID" "$key"
            _panel_row "Domain" "$domain"
            _panel_row "Expired" "$exp ($days days)"
            _panel_mid
            _panel_row_colored "VLess WS+TLS" "Port 443" "BGRN"
            _panel_row_colored "VLess WS+NTLS" "Port 80" "GOLD"
            _panel_row_colored "VLess gRPC+TLS" "Port 443" "LBLU"
            _panel_bot
            echo ""
            echo -e "  ${TEAL}WS+TLS${RST}  ${DIM}∶${RST} ${DIM}$(gen_vless_link "$user" "$key" "$domain" "tls")${RST}"
            echo -e "  ${GOLD}NTLS${RST}   ${DIM}∶${RST} ${DIM}$(gen_vless_link "$user" "$key" "$domain" "ntls")${RST}"
            echo -e "  ${LBLU}gRPC${RST}   ${DIM}∶${RST} ${DIM}$(gen_vless_link "$user" "$key" "$domain" "grpc")${RST}"
            ;;
        trojan)
            local key=$(create_trojan "$user" "$days")
            clear
            _panel_top "${label^^} ACCOUNT CREATED" 66
            _panel_empty
            _panel_row "Username" "$user"
            _panel_row "Password" "$key"
            _panel_row "Domain" "$domain"
            _panel_row "Expired" "$exp ($days days)"
            _panel_bot
            echo ""
            echo -e "  ${TEAL}WS${RST}  ${DIM}∶${RST} ${DIM}$(gen_trojan_link "$user" "$key" "$domain" "ws")${RST}"
            echo -e "  ${LBLU}gRPC${RST} ${DIM}∶${RST} ${DIM}$(gen_trojan_link "$user" "$key" "$domain" "grpc")${RST}"
            ;;
        ss)
            local key=$(create_ss "$user" "$days")
            clear
            _panel_top "${label^^} ACCOUNT CREATED" 66
            _panel_empty
            _panel_row "Username" "$user"
            _panel_row "Password" "$key"
            _panel_row "Method" "aes-128-gcm"
            _panel_row "Domain" "$domain"
            _panel_row "Expired" "$exp ($days days)"
            _panel_bot
            echo ""
            echo -e "  ${TEAL}WS${RST}  ${DIM}∶${RST} ${DIM}$(gen_ss_link "$user" "$key" "$domain" "ws")${RST}"
            echo -e "  ${LBLU}gRPC${RST} ${DIM}∶${RST} ${DIM}$(gen_ss_link "$user" "$key" "$domain" "grpc")${RST}"
            ;;
    esac

    press_enter
}

_xray_delete() {
    local type="$1" label="$2"
    clear
    _panel_top "DELETE ${label^^} ACCOUNT" 66
    _panel_empty
    _list_xray_db "$type" "$label"
    echo ""
    echo -ne "  ${BWHT}Username${RST} ${DIM}∶${RST} "; read -r user

    local db_file info_func del_func
    case "$type" in
        vmess)  db_file="$DB_VMESS";  info_func="get_vmess_info";  del_func="delete_vmess" ;;
        vless)  db_file="$DB_VLESS";  info_func="get_vless_info";  del_func="delete_vless" ;;
        trojan) db_file="$DB_TROJAN"; info_func="get_trojan_info"; del_func="delete_trojan" ;;
        ss)     db_file="$DB_SS";     info_func="get_ss_info";     del_func="delete_ss" ;;
    esac

    [[ -z "$($info_func "$user")" ]] && { log_fail "Tidak ditemukan!"; press_enter; return; }
    echo -ne "  ${BRED}Hapus '${user}'? [y/N]${RST} ${DIM}∶${RST} "; read -r c
    [[ "$c" =~ ^[Yy]$ ]] && { $del_func "$user"; log_ok "Account dihapus!"; }
    press_enter
}

_xray_renew() {
    local type="$1" label="$2"
    clear
    _panel_top "EXTEND ${label^^} EXPIRY" 66
    _panel_empty
    _list_xray_db "$type" "$label"
    echo ""
    echo -ne "  ${BWHT}Username${RST} ${DIM}∶${RST} "; read -r user

    local db_file renew_func info_func
    case "$type" in
        vmess)  db_file="$DB_VMESS";  renew_func="renew_vmess";  info_func="get_vmess_info" ;;
        vless)  db_file="$DB_VLESS";  renew_func="renew_vless";  info_func="get_vless_info" ;;
        trojan) db_file="$DB_TROJAN"; renew_func="renew_trojan"; info_func="get_trojan_info" ;;
        ss)     db_file="$DB_SS";     renew_func="renew_ss";     info_func="get_ss_info" ;;
    esac

    [[ -z "$($info_func "$user")" ]] && { log_fail "Tidak ditemukan!"; press_enter; return; }
    echo -ne "  ${BWHT}Extend (days)${RST} ${DIM}∶${RST} "; read -r days; days=${days:-30}
    $renew_func "$user" "$days"
    log_ok "Diperpanjang hingga $(get_exp_date "$days")"
    press_enter
}

_xray_list() {
    local type="$1" label="$2"
    clear
    _panel_top "${label^^} ACCOUNT LIST" 66
    _panel_empty
    _list_xray_db "$type" "$label"
    press_enter
}

_list_xray_db() {
    local type="$1" label="$2"
    local db_file
    case "$type" in
        vmess)  db_file="$DB_VMESS" ;;
        vless)  db_file="$DB_VLESS" ;;
        trojan) db_file="$DB_TROJAN" ;;
        ss)     db_file="$DB_SS" ;;
    esac

    local count=0
    echo -e "  ${TEAL}$(printf '%-18s %-20s %-12s %-10s' "USERNAME" "KEY (truncated)" "EXPIRED" "STATUS")${RST}"
    echo -e "  ${DIM}$(printf '%-18s %-20s %-12s %-10s' "──────────────────" "────────────────────" "────────────" "──────────")${RST}"
    while IFS='|' read -r user key exp created; do
        [[ -z "$user" ]] && continue
        local r=$(days_until_exp "$exp") c="${WHT}" st="ACTIVE"
        [[ $r -lt 0 ]] && { c="${BRED}"; st="EXPIRED"; }
        [[ $r -le 3 && $r -ge 0 ]] && { c="${GOLD}"; st="EXPIRING"; }
        printf "  ${c}%-18s %-20s %-12s %-10s${RST}\n" "$user" "${key:0:18}..." "$exp" "$st"
        ((count++))
    done < "$db_file" 2>/dev/null
    echo -e "  ${DIM}$(printf '%-18s %-20s %-12s %-10s' "──────────────────" "────────────────────" "────────────" "──────────")${RST}"
    echo -e "  ${GOLD}Total${RST} ${DIM}∶${RST} ${BWHT}${count}${RST} accounts"
}

# ═══════════════════════════════════════════════════════════
#  SECTION 9: SSH / SSH-WS / SSH-SSL MENU
# ═══════════════════════════════════════════════════════════

menu_sshws() {
    while true; do
        clear
        local domain=$(get_domain)
        local count=$(count_ssh)

        _panel_top "SSH / SSH-WS / SSH-SSL" 66
        _panel_row "Domain" "$domain"
        _panel_mid

        # Status in grid
        echo -e "  ${TEAL}│${RST}  $(_status_dot dropbear)  ${DIM}Dropbear${RST}        $(_status_dot stunnel4)  ${DIM}Stunnel4${RST}        $(_status_dot haproxy)  ${DIM}HAProxy${RST}  ${TEAL}│${RST}"
        echo -e "  ${TEAL}│${RST}  $(_status_dot ws-openssh)  ${DIM}WS-SSH${RST} ${DIM}:${WS_OPENSSH_PORT}${RST}    $(_status_dot ws-dropbear)  ${DIM}WS-DB${RST} ${DIM}:${WS_DROPBEAR_PORT}${RST}     $(_status_dot ws-stunnel)  ${DIM}WS-Stun${RST} ${DIM}:${WS_STUNNEL_LOCAL_PORT}${RST}  ${TEAL}│${RST}"

        _panel_mid
        _panel_row_colored "SSH Direct" "port 442, 109, 143" "SILVER"
        _panel_row_colored "SSH-SSL" "port $STUNNEL_SSL_PORT (stunnel4 TLS)" "BGRN"
        _panel_row_colored "SSH-WS OpenSSH" "port $WS_OPENSSH_PORT" "BGRN"
        _panel_row_colored "SSH-WS Dropbear" "port $WS_DROPBEAR_PORT" "BGRN"
        if systemctl is-active --quiet haproxy 2>/dev/null; then
            _panel_row_colored "SSH-SSL via 443" "SNI routing (HAProxy)" "BMGN"
        fi
        _panel_row "Total Accounts" "$count"
        _panel_empty
        _menu_item "1" "Create SSH Account" ""
        _menu_item "2" "SSH Account Info" ""
        _menu_item "3" "Connection Details" ""
        _menu_item "4" "Delete SSH Account" ""
        _menu_item "5" "Extend Expiry" ""
        _menu_item "6" "List All Accounts" ""
        _panel_empty
        _menu_item_dim "0" "Back"
        _panel_bot

        echo ""
        echo -ne "  ${BWHT}Select${RST} ${DIM}[0-6]${RST} ${DIM}∶${RST} "
        read -r c
        case "$c" in
            1) _ssh_create ;;
            2) _ssh_info ;;
            3) _ssh_detail ;;
            4) _ssh_delete ;;
            5) _ssh_renew ;;
            6) _ssh_list ;;
            0) return ;;
        esac
    done
}

_ssh_create() {
    clear
    _panel_top "CREATE SSH ACCOUNT" 66
    _panel_empty
    echo -ne "  ${BWHT}Username${RST}    ${DIM}∶${RST} "; read -r user
    [[ -z "$user" ]] && { log_fail "Kosong!"; press_enter; return; }
    grep -q "^${user}|" "$DB_SSH" && { log_fail "Sudah ada!"; press_enter; return; }
    echo -ne "  ${BWHT}Password${RST}    ${DIM}∶${RST} "; read -r pass
    echo -ne "  ${BWHT}Active Days${RST} ${DIM}∶${RST} "; read -r days; days=${days:-30}
    [[ ! "$days" =~ ^[0-9]+$ ]] && { log_fail "Harus angka!"; press_enter; return; }

    local real_pass=$(create_ssh "$user" "$days" "$pass")
    local domain=$(get_domain)
    local exp=$(get_exp_date "$days")

    clear
    _panel_top "SSH ACCOUNT CREATED" 66
    _panel_empty
    _panel_row "Username" "$user"
    _panel_row "Password" "$real_pass"
    _panel_row "Domain" "$domain"
    _panel_row "Expired" "$exp ($days days)"
    _panel_mid
    _panel_row_colored "SSH Direct" "port 442 / 109 / 143" "SILVER"
    _panel_row_colored "SSH-SSL" "port $STUNNEL_SSL_PORT TLS:ON" "BGRN"
    _panel_row_colored "SSH-WS (OpenSSH)" "port $WS_OPENSSH_PORT" "BGRN"
    _panel_row_colored "SSH-WS (Dropbear)" "port $WS_DROPBEAR_PORT" "BGRN"
    if systemctl is-active --quiet haproxy 2>/dev/null; then
        _panel_row_colored "SSH-SSL via 443" "port 443 SNI: !domain" "BMGN"
    fi
    _panel_mid
    _panel_row "WS Payload" "$(ws_payload_string "$domain")"
    _panel_bot
    press_enter
}

_ssh_info() {
    clear
    _panel_top "SSH ACCOUNT INFO" 66
    _panel_empty
    echo -ne "  ${BWHT}Username${RST} ${DIM}∶${RST} "; read -r user
    local info=$(get_ssh_info "$user")
    [[ -z "$info" ]] && { log_fail "Tidak ditemukan!"; press_enter; return; }

    local pass=$(echo "$info" | cut -d'|' -f2)
    local exp=$(echo "$info"  | cut -d'|' -f3)
    local r=$(days_until_exp "$exp")
    local sc="BGRN" st="ACTIVE"
    [[ $r -lt 0 ]] && { sc="BRED"; st="EXPIRED"; }
    [[ $r -le 3 && $r -ge 0 ]] && { sc="GOLD"; st="EXPIRING SOON"; }

    _panel_empty
    _panel_row "Username" "$user"
    _panel_row "Password" "$pass"
    _panel_row "Expired" "$exp"
    _panel_row "Remaining" "$r days"
    _panel_row_colored "Status" "$st" "$sc"
    _panel_bot
    press_enter
}

_ssh_detail() {
    clear
    _panel_top "SSH CONNECTION DETAILS" 66
    _panel_empty
    echo -ne "  ${BWHT}Username${RST} ${DIM}∶${RST} "; read -r user
    local info=$(get_ssh_info "$user")
    [[ -z "$info" ]] && { log_fail "Tidak ditemukan!"; press_enter; return; }

    local pass=$(echo "$info" | cut -d'|' -f2)
    local exp=$(echo "$info"  | cut -d'|' -f3)
    local domain=$(get_domain)

    clear
    _panel_top "CONNECTION DETAILS" 66
    _panel_empty
    _panel_row "Username" "$user"
    _panel_row "Password" "$pass"
    _panel_row "Domain" "$domain"
    _panel_row "Expired" "$exp"
    _panel_mid
    echo -e "  ${TEAL}│${RST}  ${BGRN}[1]${RST} ${WHT}SSH Direct${RST}          ${DIM}∶${RST} ${WHT}${domain} port 442 / 109 / 143${RST}  ${TEAL}│${RST}"
    echo -e "  ${TEAL}│${RST}  ${DIM}─────────────────────────────────────────────────────${RST}  ${TEAL}│${RST}"
    echo -e "  ${TEAL}│${RST}  ${BGRN}[2]${RST} ${WHT}SSH-SSL (Stunnel)${RST}   ${DIM}∶${RST} ${WHT}${domain} port $STUNNEL_SSL_PORT TLS:ON${RST}  ${TEAL}│${RST}"
    echo -e "  ${TEAL}│${RST}  ${DIM}─────────────────────────────────────────────────────${RST}  ${TEAL}│${RST}"
    echo -e "  ${TEAL}│${RST}  ${BGRN}[3]${RST} ${WHT}SSH-WS (OpenSSH)${RST}    ${DIM}∶${RST} ${WHT}${domain} port $WS_OPENSSH_PORT${RST}  ${TEAL}│${RST}"
    echo -e "  ${TEAL}│${RST}  ${GOLD}    Payload${RST} ${DIM}∶${RST} $(ws_payload_string "$domain") ${TEAL}│${RST}"
    echo -e "  ${TEAL}│${RST}  ${DIM}─────────────────────────────────────────────────────${RST}  ${TEAL}│${RST}"
    echo -e "  ${TEAL}│${RST}  ${BGRN}[4]${RST} ${WHT}SSH-WS (Dropbear)${RST}   ${DIM}∶${RST} ${WHT}${domain} port $WS_DROPBEAR_PORT${RST}  ${TEAL}│${RST}"
    echo -e "  ${TEAL}│${RST}  ${GOLD}    Payload${RST} ${DIM}∶${RST} $(ws_payload_string "$domain") ${TEAL}│${RST}"
    if systemctl is-active --quiet haproxy 2>/dev/null; then
        echo -e "  ${TEAL}│${RST}  ${DIM}─────────────────────────────────────────────────────${RST}  ${TEAL}│${RST}"
        echo -e "  ${TEAL}│${RST}  ${BMGN}[5]${RST} ${WHT}SSH-SSL via 443${RST}     ${DIM}∶${RST} ${WHT}${domain} port 443${RST}  ${TEAL}│${RST}"
        echo -e "  ${TEAL}│${RST}  ${BMGN}    SNI${RST} ${DIM}∶${RST} ${DIM}anything EXCEPT '$domain'${RST}  ${TEAL}│${RST}"
    fi
    _panel_bot
    press_enter
}

_ssh_delete() {
    clear
    _panel_top "DELETE SSH ACCOUNT" 66
    _panel_empty
    _list_ssh_simple
    echo ""
    echo -ne "  ${BWHT}Username${RST} ${DIM}∶${RST} "; read -r user
    [[ -z "$(get_ssh_info "$user")" ]] && { log_fail "Tidak ditemukan!"; press_enter; return; }
    echo -ne "  ${BRED}Hapus '$user'? [y/N]${RST} ${DIM}∶${RST} "; read -r c
    [[ "$c" =~ ^[Yy]$ ]] && { delete_ssh "$user"; log_ok "Dihapus!"; }
    press_enter
}

_ssh_renew() {
    clear
    _panel_top "EXTEND SSH EXPIRY" 66
    _panel_empty
    _list_ssh_simple
    echo ""
    echo -ne "  ${BWHT}Username${RST} ${DIM}∶${RST} "; read -r user
    [[ -z "$(get_ssh_info "$user")" ]] && { log_fail "Tidak ditemukan!"; press_enter; return; }
    echo -ne "  ${BWHT}Extend (days)${RST} ${DIM}∶${RST} "; read -r days; days=${days:-30}
    renew_ssh "$user" "$days"
    log_ok "Diperpanjang hingga $(get_exp_date "$days")"
    press_enter
}

_ssh_list() {
    clear
    _panel_top "SSH ACCOUNT LIST" 66
    _panel_empty
    _list_ssh_simple
    press_enter
}

_list_ssh_simple() {
    local count=0
    echo -e "  ${TEAL}$(printf '%-18s %-14s %-12s %-10s' "USERNAME" "PASSWORD" "EXPIRED" "STATUS")${RST}"
    echo -e "  ${DIM}$(printf '%-18s %-14s %-12s %-10s' "──────────────────" "──────────────" "────────────" "──────────")${RST}"
    while IFS='|' read -r user pass exp created; do
        [[ -z "$user" ]] && continue
        local r=$(days_until_exp "$exp") c="${WHT}" st="ACTIVE"
        [[ $r -lt 0 ]] && { c="${BRED}"; st="EXPIRED"; }
        [[ $r -le 3 && $r -ge 0 ]] && { c="${GOLD}"; st="EXPIRING"; }
        printf "  ${c}%-18s %-14s %-12s %-10s${RST}\n" "$user" "$pass" "$exp" "$st"
        ((count++))
    done < <(list_ssh)
    echo -e "  ${DIM}$(printf '%-18s %-14s %-12s %-10s' "──────────────────" "──────────────" "────────────" "──────────")${RST}"
    echo -e "  ${GOLD}Total${RST} ${DIM}∶${RST} ${BWHT}${count}${RST} accounts"
}

# ═══════════════════════════════════════════════════════════
#  SECTION 10: SERVICE CONTROL MENU
# ═══════════════════════════════════════════════════════════

menu_services() {
    while true; do
        clear
        _panel_top "SERVICE CONTROL" 66
        _panel_empty
        _menu_item "1" "Restart All Services" ""
        _menu_item "2" "Restart Xray" ""
        _menu_item "3" "Restart Nginx" ""
        _menu_item "4" "Restart Stunnel4" ""
        _menu_item "5" "Restart HAProxy" ""
        _menu_item "6" "Restart SSH-WS Services" ""
        _panel_mid
        _menu_item "7" "Service Status Overview" ""
        _panel_empty
        _menu_item_dim "0" "Back"
        _panel_bot

        echo ""
        echo -ne "  ${BWHT}Select${RST} ${DIM}[0-7]${RST} ${DIM}∶${RST} "
        read -r c
        case "$c" in
            1) _restart_all ;;
            2) _restart_svc "xray" ;;
            3) _restart_svc "nginx" ;;
            4) _restart_svc "stunnel4" ;;
            5) _restart_svc "haproxy" ;;
            6) _restart_ws_services ;;
            7) _show_service_status ;;
            0) return ;;
        esac
    done
}

_restart_svc() {
    echo -ne "  ${TEAL}◆${RST} Restarting ${BWHT}$1${RST} ... "
    systemctl restart "$1" 2>/dev/null
    sleep 0.5
    if systemctl is-active --quiet "$1"; then
        echo -e "${BGRN}● ACTIVE${RST}"
    else
        echo -e "${BRED}● FAILED${RST}"
    fi
    press_enter
}

_restart_all() {
    echo ""
    local services=(xray nginx ws-stunnel ws-openssh ws-dropbear stunnel4 haproxy)
    for svc in "${services[@]}"; do
        echo -ne "  ${TEAL}◆${RST} ${WHT}$svc${RST} ... "
        systemctl restart "$svc" 2>/dev/null
        sleep 0.3
        if systemctl is-active --quiet "$svc"; then
            echo -e "${BGRN}● ACTIVE${RST}"
        else
            echo -e "${DIM}● INACTIVE${RST}"
        fi
    done
    echo ""
    log_ok "Semua service di-restart"
    press_enter
}

_restart_ws_services() {
    echo ""
    for svc in ws-stunnel ws-openssh ws-dropbear; do
        echo -ne "  ${TEAL}◆${RST} ${WHT}$svc${RST} ... "
        systemctl restart "$svc" 2>/dev/null
        sleep 0.3
        if systemctl is-active --quiet "$svc"; then
            echo -e "${BGRN}● ACTIVE${RST}"
        else
            echo -e "${DIM}● INACTIVE${RST}"
        fi
    done
    press_enter
}

_show_service_status() {
    clear
    _panel_top "SERVICE STATUS OVERVIEW" 66
    _panel_empty

    local services=(xray nginx stunnel4 haproxy ws-stunnel ws-openssh ws-dropbear dropbear)
    for svc in "${services[@]}"; do
        local st
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            st="${BGRN}● ACTIVE${RST}"
        else
            st="${DIM}● INACTIVE${RST}"
        fi
        _panel_row "$svc" "$st"
    done

    _panel_bot
    press_enter
}

# ═══════════════════════════════════════════════════════════
#  SECTION 11: SYSTEM MONITOR
# ═══════════════════════════════════════════════════════════

menu_sysinfo() {
    clear
    _panel_top "SYSTEM INFORMATION" 66
    _panel_empty
    _panel_row "Hostname" "$(hostname)"
    _panel_row "OS" "$(get_os_info)"
    _panel_row "Kernel" "$(get_kernel)"
    _panel_row "Uptime" "$(get_uptime)"
    _panel_mid
    _panel_row "CPU" "$(get_cpu_model)"
    _panel_row "CPU Cores" "$(get_cpu_cores)"
    _panel_row "CPU Usage" "$(get_cpu_usage)%"
    _panel_mid
    _panel_row "Memory" "$(get_mem_info)"
    _panel_row "Disk" "$(get_disk_info)"
    _panel_row "Network I/O" "$(get_network_usage)"
    _panel_row "Load Average" "$(get_load_avg)"
    _panel_mid
    _panel_row "Xray Version" "$(get_xray_version)"
    _panel_row "NEONVPN Version" "$VERSION"
    _panel_row "Domain" "$(get_domain)"
    _panel_row "Server IP" "$(get_server_ip)"
    _panel_bot
    press_enter
}

# ═══════════════════════════════════════════════════════════
#  SECTION 12: DOMAIN & SSL MENU
# ═══════════════════════════════════════════════════════════

menu_domain() {
    while true; do
        clear
        local domain=$(get_domain)
        _panel_top "DOMAIN & SSL" 66
        _panel_empty
        _panel_row "Current Domain" "$domain"
        _panel_row "Server IP" "$(get_server_ip)"

        # Show cert info
        if [[ -f "$SSL_DIR/neonvpn.crt" ]]; then
            local cert_info=$(openssl x509 -in "$SSL_DIR/neonvpn.crt" -noout -dates 2>/dev/null)
            local not_after=$(echo "$cert_info" | grep "notAfter" | cut -d= -f2)
            _panel_row "Cert Expires" "$not_after"
        else
            _panel_row "SSL Cert" "NOT FOUND"
        fi

        _panel_empty
        _menu_item "1" "Change Domain" "Reconfigure all services"
        _menu_item "2" "Renew SSL Certificate" "Force ACME renewal"
        _panel_empty
        _menu_item_dim "0" "Back"
        _panel_bot

        echo ""
        echo -ne "  ${BWHT}Select${RST} ${DIM}[0-2]${RST} ${DIM}∶${RST} "
        read -r c
        case "$c" in
            1) _change_domain ;;
            2) _renew_ssl ;;
            0) return ;;
        esac
    done
}

_change_domain() {
    clear
    _panel_top "CHANGE DOMAIN" 66
    _panel_empty
    echo -ne "  ${BWHT}New Domain${RST} ${DIM}∶${RST} "; read -r new_domain
    new_domain=$(echo "$new_domain" | tr '[:upper:]' '[:lower:]' | xargs)

    if [[ -z "$new_domain" ]]; then
        log_fail "Domain kosong!"; press_enter; return
    fi

    if ! validate_domain "$new_domain"; then
        log_fail "Format tidak valid!"; press_enter; return
    fi

    local old_domain=$(get_domain)

    if ! confirm "Ganti domain dari $old_domain ke $new_domain?" "n"; then
        press_enter; return
    fi

    log_info "Memverifikasi domain baru ..."
    local result=$(verify_domain_ip "$new_domain")
    case "$result" in
        match) log_ok "Domain verified!" ;;
        mismatch) log_warn "IP tidak cocok!"; if ! confirm "Lanjutkan?" "n"; then press_enter; return; fi ;;
        *) log_warn "Tidak bisa verifikasi, lanjutkan..." ;;
    esac

    # Stop services
    systemctl stop nginx 2>/dev/null
    systemctl stop haproxy 2>/dev/null

    # Issue new SSL
    log_info "Menerbitkan SSL baru ..."
    _start_spinner "Menerbitkan sertifikat SSL"
    /root/.acme.sh/acme.sh --issue --standalone -d "$new_domain" \
        --keylength ec-256 --httpport 80 --force >/dev/null 2>&1
    _stop_spinner

    if [[ -f /root/.acme.sh/${new_domain}_ecc/fullchain.cer ]]; then
        /root/.acme.sh/acme.sh --installcert -d "$new_domain" \
            --ecc \
            --key-file "$SSL_DIR/neonvpn.key" \
            --fullchain-file "$SSL_DIR/neonvpn.crt" \
            --reloadcmd "systemctl restart xray nginx 2>/dev/null" >/dev/null 2>&1
        chmod 600 "$SSL_DIR/neonvpn.key"
        log_ok "SSL baru berhasil!"
    else
        log_fail "Gagal terbitkan SSL!"
        press_enter; return
    fi

    # Update stunnel cert
    cat "$SSL_DIR/neonvpn.crt" "$SSL_DIR/neonvpn.key" > /etc/stunnel/stunnel.pem
    chmod 600 /etc/stunnel/stunnel.pem

    # Update nginx config
    local NGINX_CONF="/etc/nginx/conf.d/neonvpn.conf"
    if [[ -f "$NGINX_CONF" ]]; then
        sed -i "s/${old_domain}/${new_domain}/g" "$NGINX_CONF"
    fi

    # Update HAProxy config
    local HAPROXY_CFG="/etc/haproxy/haproxy.cfg"
    if [[ -f "$HAPROXY_CFG" ]]; then
        sed -i "s/${old_domain}/${new_domain}/g" "$HAPROXY_CFG"
    fi

    # Update xray config
    if [[ -f "$XRAY_CONFIG" ]]; then
        local tmp=$(mktemp)
        sed "s/${old_domain}/${new_domain}/g" "$XRAY_CONFIG" > "$tmp"
        mv "$tmp" "$XRAY_CONFIG"
    fi

    # Save new domain
    echo "$new_domain" > "$SCRIPT_DIR/domain"

    # Restart all
    systemctl restart xray 2>/dev/null
    systemctl restart nginx 2>/dev/null
    systemctl restart stunnel4 2>/dev/null
    systemctl restart haproxy 2>/dev/null

    log_ok "Domain berhasil diganti ke ${BWHT}$new_domain${RST}"
    press_enter
}

_renew_ssl() {
    local domain=$(get_domain)
    log_info "Memperbarui SSL untuk ${BWHT}$domain${RST} ..."

    systemctl stop nginx 2>/dev/null
    systemctl stop haproxy 2>/dev/null

    _start_spinner "Memperbarui sertifikat SSL"
    /root/.acme.sh/acme.sh --issue --standalone -d "$domain" \
        --keylength ec-256 --httpport 80 --force >/dev/null 2>&1
    _stop_spinner

    if [[ -f /root/.acme.sh/${domain}_ecc/fullchain.cer ]]; then
        /root/.acme.sh/acme.sh --installcert -d "$domain" \
            --ecc \
            --key-file "$SSL_DIR/neonvpn.key" \
            --fullchain-file "$SSL_DIR/neonvpn.crt" \
            --reloadcmd "systemctl restart xray nginx 2>/dev/null" >/dev/null 2>&1
        chmod 600 "$SSL_DIR/neonvpn.key"

        # Update stunnel cert
        cat "$SSL_DIR/neonvpn.crt" "$SSL_DIR/neonvpn.key" > /etc/stunnel/stunnel.pem
        chmod 600 /etc/stunnel/stunnel.pem

        systemctl restart xray 2>/dev/null
        systemctl restart nginx 2>/dev/null
        systemctl restart stunnel4 2>/dev/null
        systemctl restart haproxy 2>/dev/null

        log_ok "SSL berhasil diperbarui!"
    else
        log_fail "Gagal memperbarui SSL!"
    fi
    press_enter
}

# ═══════════════════════════════════════════════════════════
#  SECTION 13: UPDATE & UNINSTALL
# ═══════════════════════════════════════════════════════════

menu_update() {
    clear
    _panel_top "CHECK UPDATE" 66
    _panel_empty

    local local_v="$VERSION"
    local remote_v=$(curl -s --max-time 10 "${UPDATE_URL}/VERSION" 2>/dev/null)

    _panel_row "Local Version" "$local_v"
    _panel_row "Remote Version" "${remote_v:-N/A}"
    _panel_empty

    if [[ -z "$remote_v" ]]; then
        log_fail "Tidak bisa cek versi terbaru!"
    elif [[ "$local_v" == "$remote_v" ]]; then
        log_ok "Sudah versi terbaru!"
    else
        log_info "Update tersedia: ${BWHT}$local_v${RST} → ${BGRN}$remote_v${RST}"
        if confirm "Update sekarang?" "n"; then
            _start_spinner "Downloading update"
            curl -fsSL "${UPDATE_URL}/neonvpn.sh" -o "$SCRIPT_DIR/neonvpn" 2>/dev/null
            _stop_spinner
            chmod 755 "$SCRIPT_DIR/neonvpn"
            log_ok "Update berhasil! Jalankan ulang: neonvpn"
        fi
    fi
    press_enter
}

menu_uninstall() {
    clear
    _panel_top "UNINSTALL NEONVPN" 66
    _panel_empty
    echo -e "  ${BRED}PERINGATAN: Semua data akun dan konfigurasi akan dihapus!${RST}"
    _panel_empty
    echo -ne "  ${BRED}Yakin ingin uninstall NEONVPN? [y/N]${RST} ${DIM}∶${RST} "; read -r c

    if [[ "$c" =~ ^[Yy]$ ]]; then
        echo -ne "  ${BRED}Ketik 'DELETE' untuk konfirmasi${RST} ${DIM}∶${RST} "; read -r confirm
        if [[ "$confirm" == "DELETE" ]]; then
            log_info "Menghentikan semua service ..."
            for svc in xray nginx ws-stunnel ws-openssh ws-dropbear stunnel4 haproxy; do
                systemctl stop "$svc" 2>/dev/null
                systemctl disable "$svc" 2>/dev/null
            done

            log_info "Menghapus file ..."
            rm -rf "$SCRIPT_DIR" "$XRAY_DIR" "$SSL_DIR" "$LOG_DIR"
            rm -f "$XRAY_BIN"
            rm -f /etc/systemd/system/xray.service
            rm -f /etc/systemd/system/ws-*.service
            rm -f /etc/nginx/conf.d/neonvpn.conf
            rm -f /usr/local/bin/neonvpn
            rm -f /usr/local/bin/ws-stunnel /usr/local/bin/ws-openssh /usr/local/bin/ws-dropbear

            # Restore default nginx
            systemctl restart nginx 2>/dev/null

            systemctl daemon-reload

            # Remove cron
            sed -i '/neonvpn-cleanup/d' /etc/crontab 2>/dev/null

            echo ""
            log_ok "NEONVPN berhasil diuninstall!"
            echo ""
            exit 0
        else
            log_warn "Batal uninstall."
        fi
    fi
    press_enter
}

_do_cleanup() {
    echo ""
    log_info "Menghapus akun expired ..."
    local deleted=$(delete_expired)
    if [[ "$deleted" -gt 0 ]]; then
        log_ok "$deleted akun expired dihapus"
    else
        log_ok "Tidak ada akun expired"
    fi
    press_enter
}

# ═══════════════════════════════════════════════════════════
#  SECTION 14: CLI HANDLER
# ═══════════════════════════════════════════════════════════

cli_handler() {
    case "$1" in
        install|"")
            run_installer
            ;;
        menu)
            if [[ -f "$SCRIPT_DIR/lib.sh" ]] || [[ -d "$SCRIPT_DIR" ]]; then
                main_menu
            else
                echo -e "  ${BRED}NEONVPN belum terinstall!${RST}"
                echo -e "  Jalankan: ${BWHT}bash neonvpn.sh install${RST}"
                exit 1
            fi
            ;;
        cleanup-expired)
            delete_expired >/dev/null
            ;;
        version|--version|-v)
            echo "NEONVPN v$VERSION"
            ;;
        status)
            if [[ -d "$SCRIPT_DIR" ]]; then
                echo "NEONVPN v$VERSION - Installed"
                echo "Domain: $(get_domain)"
                echo "Xray: $(_status_text xray)"
                echo "Nginx: $(_status_text nginx)"
                echo "Stunnel4: $(_status_text stunnel4)"
                echo "HAProxy: $(_status_text haproxy)"
                echo "Total Accounts: $(( $(count_vmess) + $(count_vless) + $(count_trojan) + $(count_ss) + $(count_ssh) ))"
            else
                echo "NEONVPN not installed."
            fi
            ;;
        help|--help|-h)
            echo -e "${BWHT}NEONVPN${RST} v$VERSION - Advanced Tunneling Suite"
            echo ""
            echo "Usage: neonvpn [command]"
            echo ""
            echo "Commands:"
            echo "  install         Run full installation wizard"
            echo "  menu            Open management menu (default if installed)"
            echo "  status          Show service status"
            echo "  cleanup-expired Delete all expired accounts (cron job)"
            echo "  version         Show version"
            echo "  help            Show this help"
            ;;
        *)
            echo -e "  ${BRED}Unknown command: $1${RST}"
            echo -e "  Run ${BWHT}neonvpn help${RST} for usage"
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════
#  SECTION 15: ENTRY POINT
# ═══════════════════════════════════════════════════════════

# If script is already installed and no args, go to menu
if [[ -d "$SCRIPT_DIR" && -z "$1" ]]; then
    main_menu
else
    cli_handler "$1"
fi
