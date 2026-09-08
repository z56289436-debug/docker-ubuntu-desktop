FROM --platform=linux/amd64 ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# =========================================================
# 基础软件 + Ubuntu Desktop + VNC + noVNC
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
# 安装 wstunnel 10.7.1
# =========================================================
RUN curl -fL \
    "https://github.com/erebe/wstunnel/releases/download/v10.7.1/wstunnel_10.7.1_linux_amd64.tar.gz" \
    -o /tmp/wstunnel.tar.gz \
    && tar -xzf /tmp/wstunnel.tar.gz -C /tmp \
    && install -m 0755 /tmp/wstunnel /usr/local/bin/wstunnel \
    && rm -f /tmp/wstunnel.tar.gz /tmp/wstunnel

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
# 2. 生成 noVNC TLS 证书
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
    echo "Please add WSTUNNEL_SECRET in Railway Variables"
    exit 1
fi

echo "WSTUNNEL_SECRET is configured"

# ---------------------------------------------------------
# 5. 启动 wstunnel
# ---------------------------------------------------------
echo "Starting wstunnel on :8000"

/usr/local/bin/wstunnel server \
    -r "$WSTUNNEL_SECRET" \
    ws://0.0.0.0:8000 \
    >/var/log/wstunnel-server.log 2>&1 &

WSTUNNEL_PID=$!

echo "wstunnel started with PID ${WSTUNNEL_PID}"

# ---------------------------------------------------------
# 6. 简单检查 wstunnel 是否还活着
# ---------------------------------------------------------
sleep 2

if ! kill -0 "$WSTUNNEL_PID" 2>/dev/null; then
    echo "ERROR: wstunnel failed to start"
    cat /var/log/wstunnel-server.log || true
    exit 1
fi

echo "wstunnel is running"

# ---------------------------------------------------------
# 7. 保持容器运行
# ---------------------------------------------------------
echo "========================================"
echo "All services started"
echo "========================================"

exec tail -f /dev/null
EOF

RUN chmod +x /usr/local/bin/start-all.sh

# =========================================================
# Railway 公网端口
# =========================================================
EXPOSE 5901
EXPOSE 6080
EXPOSE 8000

# =========================================================
# 默认启动命令
# Railway Start Command 必须保持为空
# =========================================================
CMD ["/usr/local/bin/start-all.sh"]
