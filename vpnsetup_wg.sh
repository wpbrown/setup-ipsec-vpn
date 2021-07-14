#!/bin/bash

set -euo pipefail

# Required Variables
#
# VPN_SERVER_PRIVATE_KEY
# VPN_CLIENT_PUBLIC_KEY
# VPN_REMOTE_NET
# VPN_LOCAL_NET 
# VPN_LOCAL_IP
# VPN_LOCAL_PORT

# Enable IP forwarding
sed -i '/^#\s*net.ipv4.ip_forward\s*=\s*1/s/^#//' /etc/sysctl.conf 
sysctl -p

# Install updates
apt-get update 
apt-get upgrade -y

# Install wireguard
apt-get install -y wireguard

# Configure wireguard
conf_data="
[Interface]
PrivateKey = ${VPN_SERVER_PRIVATE_KEY}
Address = ${VPN_LOCAL_IP}
PostUp = iptables -A FORWARD -i %i -d ${VPN_LOCAL_NET} -j ACCEPT
PostDown = iptables -D FORWARD -i %i -d ${VPN_LOCAL_NET} -j ACCEPT
ListenPort = ${VPN_LOCAL_PORT}

[Peer]
PublicKey = ${VPN_CLIENT_PUBLIC_KEY}
AllowedIPs = ${VPN_REMOTE_NET}
"

echo "$conf_data" > /etc/wireguard/wg0.conf

# Start wireguard
wg-quick up wg0
systemctl enable wg-quick@wg0