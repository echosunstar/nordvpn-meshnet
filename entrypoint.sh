#!/bin/bash
set -eo pipefail

echo "=========================================================="
echo " Starting NordVPN Client with Meshnet & Hardened Killswitch"
echo " Build Date : ${IMAGE_BUILD_DATE:-Unknown}"
echo " Git Commit : ${IMAGE_VCS_REF:-Unknown}"
echo "=========================================================="

echo "=========================================================="
echo " Starting NordVPN Client with Meshnet & Hardened Killswitch"
echo "=========================================================="

# Soft-Restart: Clean up stale sockets and virtual interfaces
echo "Cleaning up any stale processes or sockets..."
rm -rf /run/nordvpn/*
ip link delete nordlynx 2>/dev/null || true

# Meshnet: Generate a unique machine-id if missing or empty
if [ ! -s /etc/machine-id ]; then
    echo "Generating machine-id for Meshnet..."
    cat /proc/sys/kernel/random/uuid | tr -d '-' > /etc/machine-id
fi

# Create runtime directory NordVPN expects
mkdir -p /run/nordvpn

# Start the NordVPN daemon in background
echo "Starting nordvpnd..."
nordvpnd > /var/log/nordvpnd.log 2>&1 &

# Wait actively for the daemon socket to be created (max 10 seconds)
echo "Waiting for nordvpnd socket..."
TIMEOUT=10
while [ ! -S /run/nordvpn/nordvpnd.sock ]; do
    TIMEOUT=$((TIMEOUT - 1))
    if [ $TIMEOUT -le 0 ]; then
        echo "Error: nordvpnd failed to start or create its socket within 10 seconds."
        cat /var/log/nordvpnd.log
        exit 1
    fi
    sleep 1
done
echo "nordvpnd socket is ready."

# Validate Access Token
if [ -z "$NORDVPN_TOKEN" ]; then
    echo "Error: NORDVPN_TOKEN environment variable is not set."
    exit 1
fi

# Authenticate with NordVPN
echo "Logging in to NordVPN..."
echo "no" | nordvpn login --token "$NORDVPN_TOKEN"

# Forcefully disable telemetry and tracking
nordvpn set analytics off
sleep 3

# Apply Built-in Kill Switch
if [ "${KILL_SWITCH:-on}" = "on" ]; then
    nordvpn set killswitch on
else
    nordvpn set killswitch off
fi

# Apply LAN Discovery
if [ "${LAN_DISCOVERY:-on}" = "on" ]; then
    echo "Enabling LAN discovery..."
    nordvpn set lan-discovery on
else
    nordvpn set lan-discovery off
fi

# Apply DNS Settings
if [ -n "$CUSTOM_DNS" ]; then
    echo "Applying custom DNS: $CUSTOM_DNS..."
    nordvpn set threatprotectionlite off
    nordvpn set dns $CUSTOM_DNS
else
    echo "Using default NordVPN DNS servers."
    if [ "${THREAT_PROTECTION:-on}" = "on" ]; then
        nordvpn set threatprotectionlite on
    else
        nordvpn set threatprotectionlite off
    fi
fi

# ==============================================================================
# OPTIONAL: KERNEL-LEVEL FIREWALL HARDENING
# ==============================================================================
if [ "${HARDEN_FIREWALL:-off}" = "on" ]; then
    echo "Hardened kernel firewall requested. Detecting primary interface..."

    # Auto-detect the default outgoing interface (defaults to eth0 if detection fails)
    PRIMARY_IFACE=$(ip route show default 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -n1)
    PRIMARY_IFACE="${PRIMARY_IFACE:-eth0}"

    echo "Enforcing kernel-level firewall on ${PRIMARY_IFACE}..."

    # Flush pre-existing OUTPUT rules
    iptables -F OUTPUT 2>/dev/null || true

    # 1. Allow local loopback and VPN tunnel
    iptables -A OUTPUT -o lo -j ACCEPT
    iptables -A OUTPUT -o nordlynx -j ACCEPT

    # 2. Allow standard RFC1918 private subnets (WebUI, local scripts, Arr stack)
    iptables -A OUTPUT -o "$PRIMARY_IFACE" -d 127.0.0.0/8 -j ACCEPT
    iptables -A OUTPUT -o "$PRIMARY_IFACE" -d 10.0.0.0/8 -j ACCEPT
    iptables -A OUTPUT -o "$PRIMARY_IFACE" -d 172.16.0.0/12 -j ACCEPT
    iptables -A OUTPUT -o "$PRIMARY_IFACE" -d 192.168.0.0/16 -j ACCEPT

    # 3. Allow DNS resolution queries
    iptables -A OUTPUT -o "$PRIMARY_IFACE" -p udp --dport 53 -j ACCEPT
    iptables -A OUTPUT -o "$PRIMARY_IFACE" -p tcp --dport 53 -j ACCEPT

    # 4. Allow NordVPN authentication and API communication (HTTPS)
    iptables -A OUTPUT -o "$PRIMARY_IFACE" -p tcp --dport 443 -j ACCEPT

    # 5. Allow standard NordVPN tunnel handshakes
    iptables -A OUTPUT -o "$PRIMARY_IFACE" -p udp -m multiport --dports 1194,51820 -j ACCEPT

    # 6. Allow dynamic UDP range for Meshnet WebRTC / STUN / ICE traversal
    iptables -A OUTPUT -o "$PRIMARY_IFACE" -p udp --dport 1024:65535 -m comment --comment "Meshnet-STUN" -j ACCEPT

    # 7. Block unencrypted public TCP/UDP traffic on the primary adapter
    iptables -A OUTPUT -o "$PRIMARY_IFACE" -p tcp -j DROP
    iptables -A OUTPUT -o "$PRIMARY_IFACE" -j DROP
else
    echo "Hardened kernel firewall disabled (relying on standard NordVPN killswitch)."
fi

# ==============================================================================
# MESHNET CONFIGURATION
# ==============================================================================
MESHNET_FAILED_WARNING=false
if [ "${CONNECT_MESHNET:-on}" = "on" ]; then
    echo "Enabling Meshnet..."
    MAX_RETRIES=5
    RETRY_COUNT=0
    MESHNET_SUCCESS=false

    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        nordvpn set meshnet on
        if nordvpn settings | grep -q "Meshnet: enabled"; then
            echo "Meshnet successfully enabled!"
            MESHNET_SUCCESS=true
            break
        fi
        RETRY_COUNT=$((RETRY_COUNT + 1))
        echo "Meshnet activation pending daemon sync... Retrying in 5 seconds ($RETRY_COUNT/$MAX_RETRIES)"
        sleep 5
    done

    if [ "$MESHNET_SUCCESS" = false ]; then
        echo "Warning: Could not enable Meshnet after $MAX_RETRIES attempts."
        MESHNET_FAILED_WARNING=true
    else
        if [ -n "$MESHNET_NICKNAME" ]; then
            echo "Applying Meshnet nickname: $MESHNET_NICKNAME"
            nordvpn meshnet set nickname "$MESHNET_NICKNAME"
        fi
    fi
else
    echo "Meshnet option disabled. Skipping..."
    nordvpn set meshnet off
fi

# ==============================================================================
# VPN CONNECTION ROUTING (Standard vs Double VPN)
# ==============================================================================
CONNECT_TARGET="${VPN_COUNTRY:-}"
EXTRA_ARGS=()

if [ "${DOUBLE_VPN:-off}" = "on" ]; then
    echo "Double VPN requested! Routing traffic through two chained servers..."
    EXTRA_ARGS+=(--group double_vpn)
fi

if [ -n "$CONNECT_TARGET" ] || [ "${DOUBLE_VPN:-off}" = "on" ]; then
    MAX_VPN_RETRIES=5
    VPN_RETRY_COUNT=0
    VPN_CONNECTED=false

    while [ $VPN_RETRY_COUNT -lt $MAX_VPN_RETRIES ]; do
        echo "Connecting to VPN (${EXTRA_ARGS[*]} $CONNECT_TARGET)..."
        if nordvpn connect "${EXTRA_ARGS[@]}" $CONNECT_TARGET; then
            VPN_CONNECTED=true
            break
        fi
        VPN_RETRY_COUNT=$((VPN_RETRY_COUNT + 1))
        echo "VPN connection failed. Retrying in 5 seconds ($VPN_RETRY_COUNT/$MAX_VPN_RETRIES)..."
        sleep 5
    done

    if [ "$VPN_CONNECTED" = false ]; then
        echo "Error: Could not connect to VPN after $MAX_VPN_RETRIES attempts. Exiting so Docker can restart."
        exit 1
    fi

    sleep 2
    echo "Verifying secure routing..."
    PUBLIC_IP=$(curl -s --interface nordlynx ipinfo.io/ip || echo "Hidden")
    ISP_ORG=$(curl -s --interface nordlynx ipinfo.io/org || echo "Protected")
    CITY=$(curl -s --interface nordlynx ipinfo.io/city || echo "Unknown")
fi

# Extract DNS and Ping data
ACTIVE_DNS=$(grep nameserver /etc/resolv.conf | awk '{print $2}' | paste -sd "," - || true)
FIRST_DNS=$(echo "$ACTIVE_DNS" | cut -d',' -f1)

echo "========================================"
echo "          PRIVACY & CONNECTION          "
echo "========================================"
nordvpn settings | grep -E "Technology|Meshnet|Kill Switch|Threat Protection Lite|Analytics" || true

if [ -n "$CONNECT_TARGET" ] || [ "${DOUBLE_VPN:-off}" = "on" ]; then
    echo "----------------------------------------"
    echo "Masked IP:  $PUBLIC_IP"
    echo "Location:   $CITY"
    echo "ISP/Owner:  $ISP_ORG"
fi
echo "----------------------------------------"
echo "Active DNS: $ACTIVE_DNS"
echo "========================================"

if [ "$MESHNET_FAILED_WARNING" = true ]; then
    echo " WARNING: MESHNET ACTIVATION FAILED!    "
    nordvpn meshnet peer list || true
fi

echo "Setup complete! Keeping container alive..."
tail -f /dev/null
