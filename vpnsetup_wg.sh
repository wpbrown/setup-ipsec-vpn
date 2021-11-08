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

export DEBIAN_FRONTEND=noninteractive

# Enable IP forwarding
sed -i '/^#\s*net.ipv4.ip_forward\s*=\s*1/s/^#//' /etc/sysctl.conf 
sysctl -p

# Install wireguard
install_tries=10
if ! command -v wg; then
    for i in $(seq 1 ${install_tries}); do
        [[ $i -eq ${install_tries} ]] && exit 1
        apt-get update \
          && apt-get install -y wireguard \
          && break \
          || true
        echo "Package install failed..."
        sleep 30
    done
fi

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

# Stop existing
if wg show wg0; then
	wg-quick down wg0
fi

# SSH Port
ssh_port=$(cat /etc/ssh/sshd_config | grep -oP '^\s*Port\s*\K\d+\s*$') && true
[[ -z $ssh_port ]] && ssh_port=22

# Setup firewall
iptables -N chain-vpnsetup-wg && true
iptables -F chain-vpnsetup-wg
iptables -A chain-vpnsetup-wg -p tcp --dport ${ssh_port} -j ACCEPT # SSH
iptables -A chain-vpnsetup-wg -p udp --dport ${VPN_LOCAL_PORT} -j ACCEPT # Wireguard
iptables -A chain-vpnsetup-wg -j RETURN

if [[ -f "/etc/iptables/rules.v4" ]]; then
	# Repersist firewall
	netfilter-persistent save
else
	## Input setup
	iptables -A INPUT -i lo -j ACCEPT
	iptables -A INPUT -p icmp -j ACCEPT
	iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
	iptables -A INPUT -j chain-vpnsetup-wg
	iptables -P INPUT DROP

	## Forward setup
	iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
	iptables -P FORWARD DROP

	# Persist firewall
	apt-get install -y iptables-persistent
fi

# Start wireguard
wg-quick up wg0
systemctl enable wg-quick@wg0

