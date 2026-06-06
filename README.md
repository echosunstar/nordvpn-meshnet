# NordVPN Client with Meshnet & Privacy Auditing

A Docker image that bundles the official NordVPN Linux CLI client. 
This image  supports multi-architecture deployments (**standard PCs/Servers `amd64`** and **Raspberry Pi `arm64`**) 

# code build - provenance 

The image is built in the cloud via GitHub Actions using Docker BuildKit SLSA provenance tracking. 

The code is stored here: https://github.com/echosunstar/nordvpn-meshnet

To verify the build provenance of the image, and verify the exact source repository and Git commit hash that generated this image, run the following command in your terminal:

```
docker buildx imagetools inspect alainc67/nordvpn-meshnet:latest --format "{{json .Provenance}}" | python3 -m json.tool | egrep "vcs:|invocationId"
```

# Key Features

* Kill Switch enablement
* Meshnet enablement
* Threat Protection Lite enablement switch
* Custom DNS Support enablement
* Disables NordVPN telemetry/analytics (and that cannot be parametrised changed sorry)
* Docker named volumes to persist the Meshnet identity to avoid proliferation
* ping test to Nord  DNS servers to check things

# Prerequisites

You must generate a **NordVPN Access Token** to authenticate the container without a password.

# Deployment Setup

## create a .env file 

<pre>
# Nord login token
NORDVPN_TOKEN=your_token_here

# Toggle Meshnet: set to "on" or "off"
CONNECT_MESHNET=on

# Toggle standard VPN routing: set a country code (e.g., US, UK, CA) or leave empty "" to disable
VPN_COUNTRY=US

# Custom DNS Servers (Optional - leave blank for Nord's default)
# Example: 1.1.1.1 or 1.1.1.1, 1.0.0.1
CUSTOM_DNS=

# kill switch
KILL_SWITCH=on

# Note: Threat Protection cannot be used simultaneously with CUSTOM_DNS
THREAT_PROTECTION=on

# Meshnet Nickname (Optional - Makes the node easy to identify in  Nord app)
MESHNET_NICKNAME=my-docker-node

</pre>

## create a `docker-compose.yml` file next to the .env file :

<pre>
services:
  nordvpn-client:
    image: alainc67/nordvpn-meshnet:latest
    container_name: my-nordvpn
    cap_add:
      - NET_ADMIN
      - NET_RAW
    devices:
      - /dev/net/tun
    environment:
      - NORDVPN_TOKEN=${NORDVPN_TOKEN}
      - CONNECT_MESHNET=${CONNECT_MESHNET:-on}
      - VPN_COUNTRY=${VPN_COUNTRY:-}
      - KILL_SWITCH=${KILL_SWITCH:-on}
      - THREAT_PROTECTION=${THREAT_PROTECTION:-on}
    volumes:
      - nordvpn_config:/var/lib/nordvpn
    restart: unless-stopped

volumes:
  nordvpn_config:
    name: nordvpn_persistent_identity
</pre>


# Start the Container

To pull the pre-built image from Docker Hub and start the container:

```docker compose up -d```

# Soft Restarts
The entrypoint script is designed to handle soft restarts  (flushes lingering sockets and virtual interfaces)

```docker compose restart```

# Verifying Status & Privacy Audits
Once initialized, inspect the container logs to review the privacy receipt. 
The script runs audits confirming your traffic is successfully masked and encrypted

```docker logs my-nordvpn```

# Managing Meshnet Permissions

Meshnet permissions (such as allowing other devices to route traffic through this container, file-sharing, or local LAN access) are managed directly from your main NordVPN app or Nord Web Dashboard.

# Troubleshooting

## Meshnet Activation Fails
Personal NordVPN accounts have a strict limit on Meshnet devices. 
If you spun up this container previously without a persistent volume, you may have proliferated nodes that exceeded your limit.
If Meshnet fails to activate, the container log will print a warning box detailing your current peer count:


