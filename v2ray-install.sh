#!/bin/bash

# Script Name: v2ray-install.sh
# Author: hcsun
# Description: This script installs and configures V2ray and Nginx on a Linux server, and sets up TLS encryption.

# Update and install required packages
apt-get update && apt-get install nginx curl ufw socat -y

# Set server time
timedatectl set-local-rtc 1
timedatectl set-timezone Asia/Shanghai

# Open ports 80 and 443
ufw allow 80
ufw allow 443

# Prompt user to input domain info
read -p "Input your email for web certificate: " cert_email
read -p "Input your domain name: " domain_name
read -p "Input your Cloudflare API key: " cf_key
read -p "Input your Cloudflare email: " cf_email
read -p "Input a port number:" port_num

# Install V2ray
bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)

# Issue TLS certificate for the website
curl https://get.acme.sh | sh -s email="$cert_email"
source ~/.bashrc
export CF_Key="$cf_key"
export CF_Email="$cf_email"
~/.acme.sh/acme.sh --issue -d "$domain_name" -d "*.$domain_name" --dns dns_cf
~/.acme.sh/acme.sh --installcert -d "$domain_name" -d "*.$domain_name" --fullchainpath /usr/local/etc/v2ray/$domain_name.crt --keypath /usr/local/etc/v2ray/$domain_name.key

# Create V2ray configuration file
uuid=$(cat /proc/sys/kernel/random/uuid)
cat <<EOF >/usr/local/etc/v2ray/config.json
{
  "inbounds": [
    {
      "port": "$port_num",
      "listen": "127.0.0.1",
      "tag": "vmess-in",
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$uuid",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "/wsapp"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "inboundTag": [
          "vmess-in"
        ],
        "outboundTag": "direct"
      }
    ]
  }
}
EOF

# Configure Nginx
cat <<EOF >/etc/nginx/conf.d/default.conf
server {
    listen 443 ssl;
    ssl on;
    ssl_certificate /usr/local/etc/v2ray/$domain_name.crt;
    ssl_certificate_key /usr/local/etc/v2ray/$domain_name.key;
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    server_name domainname.com;
    index index.html index.htm;
    root /var/www/html;
    location /wsapp
    {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:$port_num;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
    }
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
}
EOF

# Edit sysctl.conf to enable BBR congestion control algorithm
echo "net.core.default_qdisc = fq" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control = bbr" | sudo tee -a /etc/sysctl.conf
# Apply changes
sudo sysctl -p
sysctl net.ipv4.tcp_congestion_control

# Set V2ray and Nginx to run at startup
sudo systemctl enable v2ray
sudo systemctl enable nginx

# Restart services
sudo systemctl restart nginx
sudo systemctl restart v2ray


echo "Generated UUID: $uuid"
echo "Websocket Path: /wsapp"