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

* Kill Switch enablement -- for further protection see also below
* Meshnet enablement
* Threat Protection Lite enablement switch
* Custom DNS Support enablement
* Disables NordVPN telemetry/analytics (and that will not be parametrised sorry)
* Docker named volumes to persist the Meshnet identity to avoid proliferation
* ping test to Nord  DNS servers to check things
* Optional Kernel-Level Killswitch (HARDEN_FIREWALL): Beyond application-layer kills, enforces native Linux iptables drop rules on the primary container interface
* Double VPN Routing (DOUBLE_VPN): Route your outbound traffic across two chained VPN servers.
* LAN Discovery & Local Subnet Whitelisting: Keeps local networks (RFC 1918) open so web user interfaces (e.g., qBittorrent WebUI on port 8080) and local media stacks remain accessible.
* Soft Restarts: Cleans lingering virtual devices and stale sockets automatically on container restarts.

# Prerequisites

You must generate a **NordVPN Access Token** to authenticate the container without a password.

# Deployment Setup

## create a .env file 

<pre>

# NordVPN Access Token (Required - generate in Nord Account Dashboard)
NORDVPN_TOKEN=your_token_here

# Meshnet: Toggle "on" or "off"
CONNECT_MESHNET=on

# Meshnet Nickname (Optional - human-readable name in your Nord apps)
MESHNET_NICKNAME=my-docker-node

# Standard VPN Country Routing (e.g., US, UK, CH, or leave blank to disable outbound VPN)
VPN_COUNTRY=US

# Double VPN Routing: Set to "on" to route through two chained VPN servers
# compatible with VPN_COUNTRY (that is, you can also set VPN_COUNTRY=us or whatever)
DOUBLE_VPN=off

# Built-in NordVPN Daemon Kill Switch: Set to "on" or "off"
KILL_SWITCH=on

# Advanced Kernel-Level Firewall (Optional, default "off"):
# Set to "on" to enforce strict iptables drop rules on the primary network interface
HARDEN_FIREWALL=off

# Threat Protection Lite: Set to "on" or "off" (cannot be used with CUSTOM_DNS)
THREAT_PROTECTION=on

# Custom DNS (Optional - comma-separated, e.g., 1.1.1.1,1.0.0.1)
CUSTOM_DNS=

</pre>

## create a `docker-compose.yml` file next to the .env file :

<pre>
services:
  nordvpn:
    image: alainc67/nordvpn-meshnet:latest
    container_name: dedicated_nordvpn
    cap_add:
      - NET_ADMIN
      - NET_RAW
    devices:
      - /dev/net/tun
    environment:
      - NORDVPN_TOKEN=${NORDVPN_TOKEN}
      - CONNECT_MESHNET=${CONNECT_MESHNET:-on}
      - MESHNET_NICKNAME=${MESHNET_NICKNAME:-}
      - VPN_COUNTRY=${VPN_COUNTRY:-}
      - DOUBLE_VPN=${DOUBLE_VPN:-off}
      - KILL_SWITCH=${KILL_SWITCH:-on}
      - HARDEN_FIREWALL=${HARDEN_FIREWALL:-off}
      - THREAT_PROTECTION=${THREAT_PROTECTION:-on}
      - CUSTOM_DNS=${CUSTOM_DNS:-}
    volumes:
      - nordvpn_data:/var/lib/nordvpn
    ports:
      # Expose any ports for downstream containers routed through this network stack
      - "8080:8080" # Example: qBittorrent WebUI
    restart: unless-stopped

volumes:
  nordvpn_data:
    name: nordvpn_persistent_identity

</pre>


# Secondary routing

To route another service entirely through this VPN tunnel, configure the child container to use `network_mode: service:nordvpn` (or `network_mode: container:dedicated_nordvpn`)

<pre>
services:
  nordvpn:
    image: alainc67/nordvpn-meshnet:latest
    container_name: nordvpn
    cap_add:
      - NET_ADMIN
      - NET_RAW
    devices:
      - /dev/net/tun
    ports:
      - "8080:8080" # WebUI port must be exposed on the VPN container
    environment:
      - NORDVPN_TOKEN=${NORDVPN_TOKEN}
      - CONNECT_MESHNET=${CONNECT_MESHNET:-on}
      - MESHNET_NICKNAME=${MESHNET_NICKNAME:-}
      - VPN_COUNTRY=${VPN_COUNTRY:-}
      - DOUBLE_VPN=${DOUBLE_VPN:-off}
      - KILL_SWITCH=${KILL_SWITCH:-on}
      - HARDEN_FIREWALL=${HARDEN_FIREWALL:-off}
      - THREAT_PROTECTION=${THREAT_PROTECTION:-on}
      - CUSTOM_DNS=${CUSTOM_DNS:-}
    volumes:
      - nordvpn_data:/var/lib/nordvpn
    restart: unless-stopped

  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:latest
    container_name: qbittorrent
    network_mode: service:nordvpn
    depends_on:
      - nordvpn
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=Etc/UTC
      - WEBUI_PORT=8080
    volumes:
      - /path/to/qbittorrent/config:/config
      - /path/to/downloads:/downloads
    restart: unless-stopped

volumes:
  nordvpn_data:
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

# checks
(change eth0 if necessary)

```
docker exec -it nordvpn curl -s https://ifconfig.me
docker logs nordvpn
docker exec -it nordvpn nordvpn settings
docker exec -it nordvpn nordvpn status
docker exec -it nordvpn curl --interface eth0 --connect-timeout 3 https://ifconfig.me || echo "PASS: Plaintext egress blocked"
docker exec -it nordvpn ip route get 1.1.1.1
docker exec -it nordvpn vpn_trace
```

# Troubleshooting

## Meshnet Activation Fails
Personal NordVPN accounts have a strict limit on Meshnet devices. 
If you spun up this container previously without a persistent volume, you may have proliferated nodes that exceeded your limit.
If Meshnet fails to activate, the container log will print a warning box detailing your current peer count:


