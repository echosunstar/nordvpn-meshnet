#!/bin/bash

# Create the runtime directory NordVPN expects
mkdir -p /run/nordvpn

# Start the NordVPN daemon in the background
echo "Starting nordvpnd..."
nordvpnd > /var/log/nordvpnd.log 2>&1 &

# Give the daemon a few seconds to fully initialize
sleep 5

# Check if the user provided a token
if [ -z "$NORDVPN_TOKEN" ]; then
    echo "Error: NORDVPN_TOKEN environment variable is not set."
    exit 1
fi

# Log in using the token - no analytics
echo "Logging in to NordVPN..."
echo "no" | nordvpn login --token "$NORDVPN_TOKEN"

nordvpn set analytics off

# Let the daemon sync with API servers post-login to prevent connection errors
sleep 3

# Conditional Custom DNS
if [ -n "$CUSTOM_DNS" ]; then
    echo "Applying custom DNS: $CUSTOM_DNS..."
    # NordVPN requires disabling Threat Protection to use custom DNS
    nordvpn set threatprotectionlite off
    nordvpn set dns $CUSTOM_DNS
else
    echo "Using default NordVPN DNS servers."
fi

# Conditional Meshnet Configuration with Retry Logic
if [ "$CONNECT_MESHNET" = "on" ]; then
    echo "Enabling Meshnet..."
    
    MAX_RETRIES=5
    RETRY_COUNT=0
    MESHNET_SUCCESS=false

    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        # Attempt to enable meshnet
        nordvpn set meshnet on
        
        # Check if it successfully turned on
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
    fi
else
    echo "Meshnet option disabled or not set to 'on'. Skipping..."
    nordvpn set meshnet off
fi

# Conditional VPN Country Routing
if [ -n "$VPN_COUNTRY" ]; then
    echo "Connecting to $VPN_COUNTRY servers..."
    nordvpn connect "$VPN_COUNTRY"
    
    # Give the tunnel a couple of seconds to fully route traffic
    sleep 2
    
    # Fetch new IP and Owner Info
    echo "Verifying secure routing..."
    PUBLIC_IP=$(curl -s ipinfo.io/ip)
    ISP_ORG=$(curl -s ipinfo.io/org)
    CITY=$(curl -s ipinfo.io/city)
else
    echo "No VPN country specified. Container will operate in Meshnet-only mode."
fi

# Read the actual DNS servers the container is currently using
# Extract the first DNS IP and check who owns it
ACTIVE_DNS=$(grep nameserver /etc/resolv.conf | awk '{print $2}' | paste -sd "," -)
FIRST_DNS=$(echo "$ACTIVE_DNS" | cut -d',' -f1)
DNS_OWNER=$(curl -s "ipinfo.io/$FIRST_DNS/org")

echo "----------------------------------------"
echo "Current Settings Summary:"
nordvpn settings | grep -E "Meshnet|Technology"

if [ -n "$VPN_COUNTRY" ]; then
    echo "Masked IP:  $PUBLIC_IP"
    echo "Location:   $CITY"
    echo "ISP/Owner:  $ISP_ORG"

    # Run a quick ping test to the active DNS server
    PING_AVG=$(ping -c 3 "$FIRST_DNS" | tail -1 | awk -F '/' '{print $5}')
    echo "Latency:    ${PING_AVG} ms (to $FIRST_DNS)"

fi

echo "Active DNS: $ACTIVE_DNS"
echo "DNS Owner:  $DNS_OWNER"
echo "----------------------------------------"

# Keep the container running in the foreground
echo "Setup complete! Keeping container alive..."
tail -f /dev/null
