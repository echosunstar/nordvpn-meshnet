#!/bin/bash

# Meshnet Fix: Generate a unique machine-id if missing or empty
if [ ! -s /etc/machine-id ]; then
    echo "Generating machine-id for Meshnet..."
    cat /proc/sys/kernel/random/uuid | tr -d '-' > /etc/machine-id
fi

# Soft-Restart : Clean up stale sockets and virtual interfaces from previous runs
echo "Cleaning up any stale processes or sockets..."
rm -rf /run/nordvpn/*
ip link delete nordlynx 2>/dev/null || true

# Create the runtime directory NordVPN expects
mkdir -p /run/nordvpn

# Start the NordVPN daemon and redirect logs to a file
echo "Starting nordvpnd..."
nordvpnd > /var/log/nordvpnd.log 2>&1 &

# Give the daemon time to fully initialize
sleep 5

# Check if the user provided a token
if [ -z "$NORDVPN_TOKEN" ]; then
    echo "Error: NORDVPN_TOKEN environment variable is not set."
    exit 1
fi

# Log in using the token
echo "Logging in to NordVPN..."
echo "no" | nordvpn login --token "$NORDVPN_TOKEN"

# disable all telemetry and tracking
nordvpn set analytics off

# Let the daemon sync with API servers post-login
sleep 3

# Apply Privacy Settings (Kill Switch & Threat Protection)
if [ "$KILL_SWITCH" = "on" ]; then
    nordvpn set killswitch on
else
    nordvpn set killswitch off
fi

# Threat Protection conflicts with Custom DNS so handle it
if [ -n "$CUSTOM_DNS" ]; then
    echo "Applying custom DNS: $CUSTOM_DNS..."
    nordvpn set threatprotectionlite off
    nordvpn set dns $CUSTOM_DNS
else
    echo "Using default NordVPN DNS servers."
    if [ "$THREAT_PROTECTION" = "on" ]; then
        nordvpn set threatprotectionlite on
    else
        nordvpn set threatprotectionlite off
    fi
fi

# Conditional Meshnet Configuration with Retry Logic
if [ "$CONNECT_MESHNET" = "on" ]; then
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
else
    echo "Meshnet option disabled. Skipping..."
    nordvpn set meshnet off
fi

# Conditional VPN Country Routing
if [ -n "$VPN_COUNTRY" ]; then
    echo "Connecting to $VPN_COUNTRY servers..."
    nordvpn connect "$VPN_COUNTRY"
    
    sleep 2
    
    echo "Verifying secure routing..."
    PUBLIC_IP=$(curl -s ipinfo.io/ip)
    ISP_ORG=$(curl -s ipinfo.io/org)
    CITY=$(curl -s ipinfo.io/city)
fi

# Extract DNS and Ping data
ACTIVE_DNS=$(grep nameserver /etc/resolv.conf | awk '{print $2}' | paste -sd "," -)
FIRST_DNS=$(echo "$ACTIVE_DNS" | cut -d',' -f1)
DNS_OWNER=$(curl -s "ipinfo.io/$FIRST_DNS/org")

if [ -n "$VPN_COUNTRY" ]; then
    # Keep ping testing strictly in-house to the VPN's DNS
    PING_AVG=$(ping -c 3 "$FIRST_DNS" | tail -1 | awk -F '/' '{print $5}')
fi

echo "========================================"
echo "          PRIVACY & CONNECTION          "
echo "========================================"

# Print key status lines directly from the Nord CLI
nordvpn settings | grep -E "Technology|Meshnet|Kill Switch|Threat Protection Lite|Analytics"

if [ -n "$VPN_COUNTRY" ]; then
    echo "----------------------------------------"
    echo "Masked IP:  $PUBLIC_IP"
    echo "Location:   $CITY"
    echo "ISP/Owner:  $ISP_ORG"
    echo "Latency:    ${PING_AVG} ms (to $FIRST_DNS)"
fi
echo "----------------------------------------"
echo "Active DNS: $ACTIVE_DNS"
echo "DNS Owner:  $DNS_OWNER"
echo "========================================"
echo "Setup complete! Keeping container alive..."

# Keep the container running in the foreground
tail -f /dev/null