FROM --platform=linux/amd64 ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

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
    && rm -rf /var/lib/apt/lists/*

RUN apt update -y && apt install -y \
    dbus-x11 \
    x11-utils \
    x11-xserver-utils \
    x11-apps

RUN apt install -y software-properties-common

RUN add-apt-repository ppa:mozillateam/ppa -y

RUN echo 'Package: *' >> /etc/apt/preferences.d/mozilla-firefox
RUN echo 'Pin: release o=LP-PPA-mozillateam' >> /etc/apt/preferences.d/mozilla-firefox
RUN echo 'Pin-Priority: 1001' >> /etc/apt/preferences.d/mozilla-firefox

RUN echo 'Unattended-Upgrade::Allowed-Origins:: "LP-PPA-mozillateam:jammy";' \
    | tee /etc/apt/apt.conf.d/51unattended-upgrades-firefox

RUN apt update -y && apt install -y firefox

RUN apt update -y && apt install -y xubuntu-icon-theme

RUN touch /root/.Xauthority

RUN curl -fL \
    "https://github.com/erebe/wstunnel/releases/download/v10.7.1/wstunnel_10.7.1_linux_amd64.tar.gz" \
    -o /tmp/wstunnel.tar.gz \
    && tar -xzf /tmp/wstunnel.tar.gz -C /tmp \
    && install -m 0755 /tmp/wstunnel /usr/local/bin/wstunnel \
    && rm -f /tmp/wstunnel.tar.gz /tmp/wstunnel

EXPOSE 5901
EXPOSE 6080
EXPOSE 8000

CMD ["/bin/bash", "-c", "vncserver -localhost no -SecurityTypes None -geometry 1024x768 --I-KNOW-THIS-IS-INSECURE && openssl req -new -subj '/C=JP' -x509 -days 365 -nodes -out /root/self.pem -keyout /root/self.pem && websockify -D --web=/usr/share/novnc/ --cert=/root/self.pem 6080 localhost:5901 && /usr/local/bin/wstunnel server ws://0.0.0.0:8000 >/var/log/wstunnel-server.log 2>&1 & tail -f /dev/null"]
