FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV TERM=xterm-256color

# Install packages
RUN apt-get update && apt-get install -y \
    curl \
    gnupg \
    python3 \
    sudo \
    procps \
    iproute2 \
    iputils-ping \
    dnsutils \
    net-tools \
    jq \
    ca-certificates \
    btop \
    htop \
    glances \
    ncdu \
    dfc \
    neofetch \
    sysbench \
    locales && \
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null && \
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list && \
    apt-get update && \
    apt-get install -y tailscale && \
    locale-gen en_US.UTF-8 && \
    update-locale LANG=en_US.UTF-8 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Enable forwarding for exit node usage
RUN echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf && \
    echo 'net.ipv6.conf.all.forwarding=1' >> /etc/sysctl.conf

# Startup script
RUN cat > /startup.sh << 'EOF'
#!/bin/bash
set -e

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export TERM=xterm-256color

# Persist shell env
grep -q 'export LANG=en_US.UTF-8' ~/.bashrc 2>/dev/null || echo 'export LANG=en_US.UTF-8' >> ~/.bashrc
grep -q 'export LC_ALL=en_US.UTF-8' ~/.bashrc 2>/dev/null || echo 'export LC_ALL=en_US.UTF-8' >> ~/.bashrc
grep -q 'export TERM=xterm-256color' ~/.bashrc 2>/dev/null || echo 'export TERM=xterm-256color' >> ~/.bashrc

# Simple HTTP server
python3 -c '
import http.server
import socketserver

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-type", "text/plain")
        self.end_headers()
        self.wfile.write(b"Hello World")

socketserver.TCPServer.allow_reuse_address = True
socketserver.TCPServer(("0.0.0.0", 7860), Handler).serve_forever()
' &

echo "🚀 Starting Tailscale container..."

mkdir -p /var/lib/tailscale

echo "▸ Starting tailscaled..."

tailscaled \
  --tun=userspace-networking \
  --socks5-server=localhost:1055 \
  --outbound-http-proxy-listen=localhost:1055 \
  --state=/var/lib/tailscale/tailscaled.state &

TAILSCALED_PID=$!

echo "▸ Waiting for tailscaled..."

for i in {1..60}; do
    if tailscale status >/dev/null 2>&1; then
        echo "✅ tailscaled ready"
        break
    fi
    sleep 1
done

# Use provided TS_AUTHKEY or fallback to hardcoded key
if [ -z "$TS_AUTHKEY" ]; then
    echo "⚠ TS_AUTHKEY not set, using fallback key"
    export TS_AUTHKEY="tskey-auth-kJkCt5kqqM11CNTRL-WN37CxCAMgeFbTVTcLEDge9SuaVGZdPc"
fi

HOSTNAME_VALUE="${TS_HOSTNAME:-$(hostname)}"

echo "▸ Connecting to tailnet..."

tailscale up \
  --authkey="$TS_AUTHKEY" \
  --hostname="$HOSTNAME_VALUE" \
  --ssh \
  --advertise-exit-node \
  --accept-routes \
  --timeout=60s

echo ""
echo "✅ Connected to Tailscale"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Hostname: $HOSTNAME_VALUE"
echo "Tailscale IP: $(tailscale ip -4)"
echo "Exit node: enabled"
echo "SSH: enabled"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Keep container alive
tail -f /dev/null
EOF

RUN chmod +x /startup.sh

CMD ["/startup.sh"]
