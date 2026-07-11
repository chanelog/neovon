#!/bin/bash
# ╔═════════════════════════════════════════════════════════════════════════╗
# ║  NEONVPN - Advanced Tunneling Suite (v2.0.2)                            ║
# ║  Supports: SSH-WS/SSL (TLS/SSL/NTLS) + Xray (VMess/VLess/Trojan/SS)   ║
# ║  Single-file installer & management script                              ║
# ║  Author: chanelog | Fixed: v2.0.2                                       ║
# ║  Xray Download: https://github.com/chanelog/bin                         ║
# ╚═════════════════════════════════════════════════════════════════════════╝

VERSION="2.0.2"
SCRIPT_DIR="/etc/neonvpn"
BIN_DIR="/usr/local/bin"
XRAY_DIR="/etc/xray"
SSL_DIR="/etc/ssl/neonvpn"
DB_DIR="$SCRIPT_DIR/db"
LOG_DIR="/var/log/neonvpn"
CONF_DIR="$SCRIPT_DIR/config"

# ─── Xray Download URL (from chanelog/bin repo) ──────────
XRAY_DOWNLOAD_URL="https://github.com/chanelog/bin/raw/refs/heads/main/Xray-linux-64.zip"

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

# ═══════════════════════════════════════════════════════════
#  COLORS & UI
# ═══════════════════════════════════════════════════════════

BGRN='\033[1;32m'
BRED='\033[1;31m'
BWHT='\033[1;37m'
TEAL='\033[38;5;14m'
WHT='\033[0;37m'
DIM='\033[0;2m'
RST='\033[0m'

log_ok()    { echo -e "  ${BGRN}✓${RST} ${WHT}$1${RST}"; }
log_fail()  { echo -e "  ${BRED}✗${RST} ${WHT}$1${RST}"; }
log_info()  { echo -e "  ${TEAL}◆${RST} ${WHT}$1${RST}"; }
log_warn()  { echo -e "  ${TEAL}▲${RST} ${WHT}$1${RST}"; }

# ═══════════════════════════════════════════════════════════
#  XRAY DOWNLOAD & INSTALL (FIXED v2.0.2)
# ═══════════════════════════════════════════════════════════

install_xray() {
    local DOMAIN="$1"
    
    log_info "Downloading Xray from chanelog/bin repo..."
    
    cd /tmp
    rm -f xray.zip xray_extract -rf
    
    # Download from chanelog/bin repo
    if ! curl -fsSL --max-time 300 -o xray.zip "$XRAY_DOWNLOAD_URL"; then
        log_fail "Failed to download Xray"
        return 1
    fi
    
    SIZE=$(stat -c%s xray.zip 2>/dev/null || echo 0)
    if [[ $SIZE -lt 1000000 ]]; then
        log_fail "Downloaded file too small ($SIZE bytes) - possibly corrupt"
        rm -f xray.zip
        return 1
    fi
    
    log_info "Downloaded: $SIZE bytes"
    log_info "Extracting..."
    
    mkdir -p xray_extract
    if ! unzip -oq xray.zip -d xray_extract 2>/dev/null; then
        log_fail "Failed to extract Xray"
        rm -rf xray.zip xray_extract
        return 1
    fi
    
    if [[ ! -f xray_extract/xray ]]; then
        log_fail "xray binary not found in archive"
        rm -rf xray.zip xray_extract
        return 1
    fi
    
    log_info "Installing Xray..."
    sudo install -m 755 xray_extract/xray "$XRAY_BIN" || return 1
    
    # Copy geoip & geosite if available
    [[ -f xray_extract/geoip.dat ]] && sudo cp xray_extract/geoip.dat "$XRAY_DIR/"
    [[ -f xray_extract/geosite.dat ]] && sudo cp xray_extract/geosite.dat "$XRAY_DIR/"
    
    rm -rf xray.zip xray_extract
    
    XRAY_VERSION=$($XRAY_BIN version 2>/dev/null | head -1 || echo "unknown")
    log_ok "Xray installed: $XRAY_VERSION"
    
    return 0
}

# ═══════════════════════════════════════════════════════════
#  XRAY CONFIG & SERVICE
# ═══════════════════════════════════════════════════════════

setup_xray_config() {
    local DOMAIN="$1"
    
    log_info "Creating Xray config..."
    mkdir -p "$XRAY_DIR" /var/log/xray
    
    cat > "$XRAY_CONFIG" << XRAYCFG
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "tag": "vmess-ws-tls",
      "port": $XRAY_VMESS_WS_TLS_PORT,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {"clients": []},
      "streamSettings": {
        "network": "ws",
        "wsSettings": {"path": "/vmess-ws", "headers": {"Host": "$DOMAIN"}}
      }
    },
    {
      "tag": "vless-ws-tls",
      "port": $XRAY_VLESS_WS_TLS_PORT,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {"clients": [], "decryption": "none"},
      "streamSettings": {
        "network": "ws",
        "wsSettings": {"path": "/vless-ws", "headers": {"Host": "$DOMAIN"}}
      }
    }
  ],
  "outbounds": [
    {"tag": "direct", "protocol": "freedom"},
    {"tag": "block", "protocol": "blackhole"}
  ]
}
XRAYCFG
    
    log_ok "Xray config created"
}

setup_xray_service() {
    log_info "Creating systemd service..."
    
    cat > /etc/systemd/system/xray.service << 'EOSVC'
[Unit]
Description=NEONVPN Xray Service
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
    
    systemctl daemon-reload
    systemctl enable xray 2>/dev/null
    systemctl start xray 2>/dev/null
    sleep 1
    
    if systemctl is-active --quiet xray; then
        log_ok "Xray service running"
        return 0
    else
        log_fail "Xray service failed to start"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════
#  QUICK INSTALL
# ═══════════════════════════════════════════════════════════

quick_install() {
    clear
    echo ""
    echo -e "  ${TEAL}NEONVPN v${VERSION} - Quick Setup${RST}"
    echo ""
    
    # Check root
    [[ $EUID -ne 0 ]] && { echo -e "  ${BRED}Must run as root!${RST}"; exit 1; }
    
    # Get domain
    echo -ne "  ${BWHT}Domain${RST}: "
    read -r DOMAIN
    [[ -z "$DOMAIN" ]] && { log_fail "Domain required"; exit 1; }
    
    # Update & install deps
    log_info "Installing dependencies..."
    apt-get update -qq 2>/dev/null
    apt-get install -y -qq curl wget unzip jq 2>/dev/null
    
    # Create directories
    mkdir -p "$SCRIPT_DIR" "$DB_DIR" "$CONF_DIR" "$LOG_DIR" "$XRAY_DIR"
    
    # Download & install Xray
    install_xray "$DOMAIN" || exit 1
    
    # Setup Xray
    setup_xray_config "$DOMAIN"
    setup_xray_service || exit 1
    
    # Save domain
    echo "$DOMAIN" > "$SCRIPT_DIR/domain"
    echo "$VERSION" > "$SCRIPT_DIR/VERSION"
    
    # Create databases
    touch "$DB_VMESS" "$DB_VLESS" "$DB_TROJAN" "$DB_SS" "$DB_SSH"
    
    echo ""
    echo -e "  ${BGRN}✅ Installation Complete!${RST}"
    echo -e "  ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
    echo -e "  Domain: ${BWHT}$DOMAIN${RST}"
    echo -e "  Xray: ${BGRN}Running${RST}"
    echo -e "  Ports: 10001 (VMess), 10003 (VLess)"
    echo -e "  ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RST}"
    echo ""
}

# ═══════════════════════════════════════════════════════════
#  CLI HANDLER
# ═══════════════════════════════════════════════════════════

case "${1:-install}" in
    install)
        quick_install
        ;;
    version|--version|-v)
        echo "NEONVPN v$VERSION"
        ;;
    status)
        systemctl status xray --no-pager
        ;;
    *)
        echo "Usage: neonvpn [install|status|version]"
        ;;
esac
