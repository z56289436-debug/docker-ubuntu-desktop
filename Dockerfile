FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# =========================================================
# Ubuntu Desktop + VNC + noVNC + 基础工具
# =========================================================
RUN apt update -y && apt install --no-install-recommends -y \
    xfce4 \
    xfce4-goodies \
    tigervnc-standalone-server \
    novnc \
    websockify \
    sudo \
    xterm \
    init \
    systemd \
    snapd \
    vim \
    net-tools \
    curl \
    wget \
    git \
    tzdata \
    ca-certificates \
    openssl \
    dbus-x11 \
    x11-utils \
    x11-xserver-utils \
    x11-apps \
    software-properties-common \
    gnupg \
    gpg-agent \
    && rm -rf /var/lib/apt/lists/*

# =========================================================
# Firefox
# =========================================================
RUN add-apt-repository ppa:mozillateam/ppa -y

RUN echo 'Package: *' > /etc/apt/preferences.d/mozilla-firefox && \
    echo 'Pin: release o=LP-PPA-mozillateam' >> /etc/apt/preferences.d/mozilla-firefox && \
    echo 'Pin-Priority: 1001' >> /etc/apt/preferences.d/mozilla-firefox

RUN echo 'Unattended-Upgrade::Allowed-Origins:: "LP-PPA-mozillateam:jammy";' \
    > /etc/apt/apt.conf.d/51unattended-upgrades-firefox

RUN apt update -y && \
    apt install -y firefox xubuntu-icon-theme && \
    rm -rf /var/lib/apt/lists/*

RUN touch /root/.Xauthority

# =========================================================
# wstunnel 10.7.1
# =========================================================
RUN curl -fL \
    "https://github.com/erebe/wstunnel/releases/download/v10.7.1/wstunnel_10.7.1_linux_amd64.tar.gz" \
    -o /tmp/wstunnel.tar.gz \
    && tar -xzf /tmp/wstunnel.tar.gz -C /tmp \
    && install -m 0755 /tmp/wstunnel /usr/local/bin/wstunnel \
    && rm -f /tmp/wstunnel.tar.gz /tmp/wstunnel

# =========================================================
# Shadowsocks (shadowsocks-libev)
# 仅当环境变量 SS_PASSWORD 设置时，启动脚本才会在 1080 监听；
# 未设置时 1080 保持关闭，避免开放代理。
# 独立成层且靠后，尽量命中前面大层的构建缓存。
# =========================================================
RUN apt update -y && apt install --no-install-recommends -y \
    shadowsocks-libev \
    && rm -rf /var/lib/apt/lists/*

# =========================================================
# 统一启动脚本
# =========================================================
RUN cat > /usr/local/bin/start-all.sh <<'EOF'
#!/bin/bash

set -e

echo "========================================"
echo "Starting Ubuntu Desktop"
echo "========================================"

# ---------------------------------------------------------
# 1. 启动 VNC
# ---------------------------------------------------------
vncserver \
    -localhost no \
    -SecurityTypes None \
    -geometry 1024x768 \
    --I-KNOW-THIS-IS-INSECURE

echo "VNC started on :5901"

# ---------------------------------------------------------
# 2. 生成 noVNC 自签名证书
# ---------------------------------------------------------
openssl req \
    -new \
    -subj "/C=JP" \
    -x509 \
    -days 365 \
    -nodes \
    -out /root/self.pem \
    -keyout /root/self.pem

echo "Self-signed certificate generated"

# ---------------------------------------------------------
# 3. 启动 noVNC / websockify
# ---------------------------------------------------------
websockify \
    -D \
    --web=/usr/share/novnc/ \
    --cert=/root/self.pem \
    6080 \
    localhost:5901

echo "noVNC started on :6080"

# ---------------------------------------------------------
# 4. 检查 Secret
# ---------------------------------------------------------
if [ -z "${WSTUNNEL_SECRET:-}" ]; then
    echo "ERROR: WSTUNNEL_SECRET is not set"
    exit 1
fi

echo "WSTUNNEL_SECRET is configured"

# ---------------------------------------------------------
# 5. 启动 wstunnel
#
# -r = 限制 WebSocket Upgrade 的 path prefix
#      这里作为认证 Secret
#
# 不使用 restrictions.yaml，
# 避免额外的目标地址 allow-list 限制。
# ---------------------------------------------------------
echo "Starting authenticated wstunnel on :8000"

/usr/local/bin/wstunnel server \
    -r "$WSTUNNEL_SECRET" \
    ws://0.0.0.0:8000 \
    >/var/log/wstunnel-server.log 2>&1 &

WSTUNNEL_PID=$!

echo "wstunnel started with PID ${WSTUNNEL_PID}"

# ---------------------------------------------------------
# 6. 检查 wstunnel
# ---------------------------------------------------------
sleep 2

if ! kill -0 "${WSTUNNEL_PID}" 2>/dev/null; then
    echo "ERROR: wstunnel failed to start"
    cat /var/log/wstunnel-server.log || true
    exit 1
fi

echo "wstunnel is running"

# ---------------------------------------------------------
# 7. Shadowsocks（仅当 SS_PASSWORD 设置时启用；未设置则 1080 不监听）
# ---------------------------------------------------------
if [ -n "${SS_PASSWORD:-}" ]; then
    SS_PORT="${SS_PORT:-1080}"
    SS_METHOD="${SS_METHOD:-chacha20-ietf-poly1305}"
    echo "Starting Shadowsocks on :${SS_PORT} (${SS_METHOD})"
    /usr/bin/ss-server \
        -s 0.0.0.0 \
        -p "${SS_PORT}" \
        -k "${SS_PASSWORD}" \
        -m "${SS_METHOD}" \
        -t 300 \
        --no-delay \
        >/var/log/ss-server.log 2>&1 &
    SS_PID=$!
    sleep 1
    if ! kill -0 "${SS_PID}" 2>/dev/null; then
        echo "ERROR: ss-server failed to start"
        cat /var/log/ss-server.log || true
        exit 1
    fi
    echo "Shadowsocks is running (PID ${SS_PID})"
else
    echo "SS_PASSWORD not set; Shadowsocks DISABLED (port 1080 stays closed)"
fi

# ---------------------------------------------------------
# 8. 保持容器运行
# ---------------------------------------------------------
echo "========================================"
echo "All services started"
echo "========================================"

exec tail -f /dev/null
EOF

RUN chmod +x /usr/local/bin/start-all.sh

# =========================================================
# Railway ports
# =========================================================
EXPOSE 5901
EXPOSE 6080
EXPOSE 8000
EXPOSE 1080

# =========================================================
# Default startup
# Railway Start Command 保持为空
# =========================================================
CMD ["/usr/local/bin/start-all.sh"]
