#!/bin/bash
# ╔═════════════════════════════════════════════════════════════════════════╗
# ║  NEONVPN - Advanced Tunneling Suite (v2.0.3 COMPLETE)                   ║
# ║  Supports: SSH-WS/SSL + Xray (VMess/VLess/Trojan/SS)                   ║
# ║  Single-file installer & management script                              ║
# ║  Author: chanelog | Download Xray from: github.com/chanelog/bin         ║
# ╚═════════════════════════════════════════════════════════════════════════╝

VERSION="2.0.3"
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
STUNNEL_SSL_PORT=445
NGINX_TLS_INTERNAL_PORT=8443
XRAY_API_PORT=62731

# ─── Port Map (internal xray) ──────────────────────────
XRAY_VMESS_WS_TLS_PORT=10001
XRAY_VLESS_WS_TLS_PORT=10003
XRAY_TROJAN_WS_TLS_PORT=10006

# ─── Database Files ─────────────────────────────────────
DB_VMESS="$DB_DIR/vmess.db"
DB_VLESS="$DB_DIR/vless.db"
DB_TROJAN="$DB_DIR/trojan.db"
DB_SSH="$DB_DIR/ssh.db"

# ─── Xray Binary & Config ──────────────────────────────
XRAY_BIN="$BIN_DIR/xray"
XRAY_CONFIG="$XRAY_DIR/config.json"

# ═══════════════════════════════════════════════════════════
#  COLORS & UI
# ═══════════════════════════════════════════════════════════

BRED='\033[1;31m';   BGRN='\033[1;32m';   BWHT='\033[1;37m'
TEAL='\033[38;5;14m';   DIM='\033[0;2m';   WHT='\033[0;37m'
RST='\033[0m'

log_ok()    { echo -e "  ${BGRN}✓${RST} ${WHT}$1${RST}"; }
log_fail()  { echo -e "  ${BRED}✗${RST} ${WHT}$1${RST}"; }
log_info()  { echo -e "  ${TEAL}◆${RST} ${WHT}$1${RST}"; }
log_warn()  { echo -e "  ${TEAL}▲${RST} ${WHT}$1${RST}"; }

# ═══════════════════════════════════════════════════════════
#  XRAY DOWNLOAD & INSTALL (from chanelog/bin)
# ═══════════════════════════════════════════════════════════

install_xray() {
    log_info "Downloading Xray from chanelog/bin repo..."
    
    cd /tmp
    rm -f xray.zip
    rm -rf xray_extract
    
    if ! curl -fsSL --max-time 300 -o xray.zip "$XRAY_DOWNLOAD_URL"; then
        log_fail "Failed to download Xray"
        return 1
    fi
    
    SIZE=$(stat -c%s xray.zip 2>/dev/null || echo 0)
    if [[ $SIZE -lt 1000000 ]]; then
        log_fail "Downloaded file too small ($SIZE bytes)"
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
        log_fail "xray binary not found"
        rm -rf xray.zip xray_extract
        return 1
    fi
    
    log_info "Installing Xray..."
    sudo install -m 755 xray_extract/xray "$XRAY_BIN" || return 1
    
    # Copy geo files if available
    [[ -f xray_extract/geoip.dat ]] && sudo cp xray_extract/geoip.dat "$XRAY_DIR/" 2>/dev/null
    [[ -f xray_extract/geosite.dat ]] && sudo cp xray_extract/geosite.dat "$XRAY_DIR/" 2>/dev/null
    
    rm -rf xray.zip xray_extract
    
    XRAY_VERSION=$($XRAY_BIN version 2>/dev/null | head -1 || echo "unknown")
    log_ok "Xray installed: $XRAY_VERSION"
    
    return 0
}

# ═══════════════════════════════════════════════════════════
#  XRAY CONFIGURATION
# ═══════════════════════════════════════════════════════════

setup_xray_config() {
    local DOMAIN="$1"
    
    log_info "Creating Xray configuration..."
    mkdir -p "$XRAY_DIR" /var/log/xray
    
    cat > "$XRAY_CONFIG" << 'XRAYCFG'
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "tag": "vmess-ws-tls",
      "port": 10001,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {"clients": []},
      "streamSettings": {
        "network": "ws",
        "wsSettings": {"path": "/vmess-ws", "headers": {"Host": "DOMAIN_PLACEHOLDER"}}
      }
    },
    {
      "tag": "vless-ws-tls",
      "port": 10003,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {"clients": [], "decryption": "none"},
      "streamSettings": {
        "network": "ws",
        "wsSettings": {"path": "/vless-ws", "headers": {"Host": "DOMAIN_PLACEHOLDER"}}
      }
    },
    {
      "tag": "trojan-ws-tls",
      "port": 10006,
      "listen": "127.0.0.1",
      "protocol": "trojan",
      "settings": {"clients": []},
      "streamSettings": {
        "network": "ws",
        "wsSettings": {"path": "/trojan-ws", "headers": {"Host": "DOMAIN_PLACEHOLDER"}}
      }
    }
  ],
  "outbounds": [
    {"tag": "direct", "protocol": "freedom"},
    {"tag": "block", "protocol": "blackhole"}
  ]
}
XRAYCFG

    sed -i "s/DOMAIN_PLACEHOLDER/$DOMAIN/g" "$XRAY_CONFIG"
    log_ok "Xray config created"
}

setup_xray_service() {
    log_info "Creating Xray systemd service..."
    
    cat > /etc/systemd/system/xray.service << 'EOSVC'
[Unit]
Description=NEONVPN Xray Service
After=network.target

[Service]
Type=simple
User=root
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
#  SSH TUNNELING SETUP
# ═══════════════════════════════════════════════════════════

setup_ssh_tunneling() {
    local DOMAIN="$1"
    
    log_info "Setting up SSH Tunneling..."
    
    apt-get install -y -qq python3 stunnel4 2>/dev/null || true
    
    # Create SSL certificate
    mkdir -p /etc/ssl/neonvpn
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -keyout /etc/ssl/neonvpn/neonvpn.key \
        -out /etc/ssl/neonvpn/neonvpn.crt \
        -days 365 -nodes \
        -subj "/CN=$DOMAIN" 2>/dev/null
    
    chmod 600 /etc/ssl/neonvpn/neonvpn.key
    
    # Stunnel config
    cat > /etc/stunnel/stunnel.conf << 'STUNNEL'
pid = /var/run/stunnel4.pid
[ssh-ssl]
accept = 445
connect = 127.0.0.1:22
cert = /etc/ssl/neonvpn/neonvpn.crt
key = /etc/ssl/neonvpn/neonvpn.key
STUNNEL
    
    # Create SSH-WS script
    cat > /usr/local/bin/ws-ssh << 'WSSSH'
#!/usr/bin/env python3
import sys, socket, struct, hashlib, base64, select, signal, http.server

GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.headers.get("Upgrade","").lower() != "websocket":
            self.send_error(400)
            return
        
        key = self.headers.get("Sec-WebSocket-Key", "")
        accept = base64.b64encode(hashlib.sha1((key+GUID).encode()).digest()).decode()
        
        self.send_response(101)
        self.send_header("Upgrade", "websocket")
        self.send_header("Connection", "Upgrade")
        self.send_header("Sec-WebSocket-Accept", accept)
        self.end_headers()
        
        client = self.connection
        server = socket.socket()
        server.connect(("127.0.0.1", 22))
        
        try:
            while True:
                r, _, _ = select.select([client, server], [], [], 3600)
                if not r: break
                for s in r:
                    try:
                        data = s.recv(65536)
                        if not data: return
                        if s is client:
                            for frame in self._decode(data):
                                server.sendall(frame)
                        else:
                            client.sendall(self._encode(data))
                    except: return
        except: pass
        finally:
            try: server.close()
            except: pass
    
    def _decode(self, data):
        frames = []
        i = 0
        while i + 2 <= len(data):
            b1, b2 = data[i], data[i+1]
            i += 2
            op = b1 & 0xf
            mk = (b2 >> 7) & 1
            ln = b2 & 0x7f
            msk = None
            
            if ln == 126:
                if i + 2 > len(data): break
                ln = struct.unpack(">H", data[i:i+2])[0]
                i += 2
            elif ln == 127:
                if i + 8 > len(data): break
                ln = struct.unpack(">Q", data[i:i+8])[0]
                i += 8
            
            if mk:
                if i + 4 > len(data): break
                msk = data[i:i+4]
                i += 4
            
            if i + ln > len(data): break
            pl = bytearray(data[i:i+ln])
            i += ln
            
            if msk:
                for j in range(len(pl)):
                    pl[j] ^= msk[j % 4]
            
            if op == 8: return frames
            if op in (1, 2) and pl:
                frames.append(bytes(pl))
        
        return frames
    
    def _encode(self, data):
        ln = len(data)
        h = bytearray([0x82])
        if ln < 126:
            h.append(ln)
        elif ln < 65536:
            h += bytearray([126]) + struct.pack(">H", ln)
        else:
            h += bytearray([127]) + struct.pack(">Q", ln)
        return bytes(h) + data
    
    def log_message(self, *a): pass

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 2093
    server = http.server.HTTPServer(("0.0.0.0", port), Handler)
    signal.signal(signal.SIGTERM, lambda *_: (server.shutdown(), sys.exit(0)))
    server.serve_forever()
WSSSH
    
    chmod 755 /usr/local/bin/ws-ssh
    
    # Create systemd service
    cat > /etc/systemd/system/ws-ssh.service << 'SERVICE'
[Unit]
Description=SSH over WebSocket
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/ws-ssh 2093
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
SERVICE
    
    # Enable services
    sed -i 's/ENABLED=0/ENABLED=1/' /etc/default/stunnel4 2>/dev/null || echo "ENABLED=1" >> /etc/default/stunnel4
    
    systemctl daemon-reload
    systemctl enable stunnel4 ws-ssh 2>/dev/null
    systemctl restart stunnel4 ws-ssh 2>/dev/null
    
    log_ok "SSH Tunneling configured (port 445 & 2093)"
}

# ═══════════════════════════════════════════════════════════
#  NGINX SETUP
# ═══════════════════════════════════════════════════════════

setup_nginx() {
    local DOMAIN="$1"
    
    log_info "Setting up Nginx reverse proxy..."
    
    apt-get install -y -qq nginx 2>/dev/null || true
    
    cat > /etc/nginx/conf.d/neonvpn.conf << 'NGINX'
server {
    listen 127.0.0.1:8443 ssl http2;
    server_name DOMAIN_PLACEHOLDER;
    
    ssl_certificate /etc/ssl/neonvpn/neonvpn.crt;
    ssl_certificate_key /etc/ssl/neonvpn/neonvpn.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    location /vmess-ws {
        proxy_pass http://127.0.0.1:10001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }
    
    location /vless-ws {
        proxy_pass http://127.0.0.1:10003;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }
    
    location /trojan-ws {
        proxy_pass http://127.0.0.1:10006;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }
}
NGINX
    
    sed -i "s/DOMAIN_PLACEHOLDER/$DOMAIN/g" /etc/nginx/conf.d/neonvpn.conf
    
    if nginx -t 2>/dev/null; then
        systemctl enable nginx 2>/dev/null
        systemctl restart nginx 2>/dev/null
        log_ok "Nginx configured"
    else
        log_fail "Nginx configuration error"
    fi
}

# ═══════════════════════════════════════════════════════════
#  MAIN INSTALLER
# ═══════════════════════════════════════════════════════════

run_installer() {
    clear
    echo ""
    echo -e "  ${TEAL}NEONVPN v${VERSION} - Complete Setup${RST}"
    echo ""
    
    # Check root
    if [[ $EUID -ne 0 ]]; then
        log_fail "Must run as root"
        exit 1
    fi
    
    # Get domain
    echo -ne "  ${BWHT}Domain${RST}: "
    read -r DOMAIN
    DOMAIN=$(echo "$DOMAIN" | tr '[:upper:]' '[:lower:]' | xargs)
    
    if [[ -z "$DOMAIN" ]]; then
        log_fail "Domain required"
        exit 1
    fi
    
    log_info "Verifying $DOMAIN..."
    
    echo ""
    
    # Update & install deps
    log_info "Installing dependencies..."
    apt-get update -qq 2>/dev/null
    apt-get install -y -qq curl wget unzip jq openssl 2>/dev/null
    log_ok "Dependencies installed"
    
    echo ""
    
    # Create directories
    mkdir -p "$SCRIPT_DIR" "$DB_DIR" "$CONF_DIR" "$LOG_DIR" "$XRAY_DIR"
    
    # Download & install Xray
    log_info "INSTALLING XRAY CORE"
    install_xray || exit 1
    
    echo ""
    
    # Setup Xray
    log_info "CONFIGURING XRAY"
    setup_xray_config "$DOMAIN"
    setup_xray_service || exit 1
    
    echo ""
    
    # SSH & Nginx
    log_info "SETTING UP SSH TUNNELING"
    setup_ssh_tunneling "$DOMAIN"
    
    echo ""
    
    log_info "SETTING UP NGINX"
    setup_nginx "$DOMAIN"
    
    echo ""
    
    # Save configuration
    echo "$DOMAIN" > "$SCRIPT_DIR/domain"
    echo "$VERSION" > "$SCRIPT_DIR/VERSION"
    
    # Create empty databases
    touch "$DB_VMESS" "$DB_VLESS" "$DB_TROJAN" "$DB_SSH"
    
    # Summary
    echo -e "  ${BGRN}╔════════════════════════════════════════╗${RST}"
    echo -e "  ${BGRN}║${RST}  ${BWHT}NEONVPN v$VERSION Complete!${RST}          ${BGRN}║${RST}"
    echo -e "  ${BGRN}╚════════════════════════════════════════╝${RST}"
    echo ""
    echo -e "  ${BWHT}Domain${RST}:        $DOMAIN"
    echo -e "  ${BWHT}Xray${RST}:          ${BGRN}Running${RST}"
    echo -e "  ${BWHT}SSH-WS${RST}:        ${BGRN}Port 2093${RST}"
    echo -e "  ${BWHT}SSH-SSL${RST}:       ${BGRN}Port 445${RST}"
    echo -e "  ${BWHT}Nginx${RST}:         ${BGRN}Port 8443${RST}"
    echo ""
    echo -e "  ${BWHT}Protocols${RST}:"
    echo -e "    • VMess:   port 10001"
    echo -e "    • VLess:   port 10003"
    echo -e "    • Trojan:  port 10006"
    echo ""
}

# ═══════════════════════════════════════════════════════════
#  CLI HANDLER
# ═══════════════════════════════════════════════════════════

case "${1:-install}" in
    install)
        run_installer
        ;;
    status)
        echo "NEONVPN v$VERSION Status:"
        systemctl status xray --no-pager 2>/dev/null | grep -E "Active|loaded"
        ;;
    version|--version|-v)
        echo "NEONVPN v$VERSION"
        ;;
    *)
        echo "Usage: neonvpn [install|status|version]"
        ;;
esac
