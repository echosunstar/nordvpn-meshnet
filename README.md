# NordVPN Client with Meshnet & Privacy Auditing

A Docker image that bundles the official NordVPN Linux CLI client. 
This image natively supports multi-architecture deployments (**standard PCs/Servers `amd64`** and **Raspberry Pi `arm64`**) 

## Key Features

* Kill Switch enablement
* Meshnet enablement
* Threat Protection Lite enablement switch
* Custom DNS Support enablement
* Disables NordVPN telemetry/analytics (and that cannot be parametrised changed sorry)
* Docker named volumes to persist the Meshnet identity to avoid proliferation
* ping test to Nord  DNS servers to check things

---

## Prerequisites

You must generate a **NordVPN Access Token** to authenticate the container without a password.

---

## Deployment Setup

Create a `.env` file in your root folder - sample provided

# How to Run

## Local Up & Build
To build and spin up the container locally:

docker compose up -d --build

## Soft Restarts
The entrypoint script is designed to handle soft restarts seamlessl. 
If you run a soft restart, it safely flushes lingering sockets and virtual interfaces:

docker compose restart

## Verifying Status & Privacy Audits
Once initialized, inspect the container logs to review the privacy receipt. 
TheThe script runs audits confirming your traffic is successfully masked and encrypted

docker logs my-nordvpn
Example Logs Output
Plaintext
========================================
          PRIVACY & CONNECTION          
========================================
Technology: NORDLYNX
Kill Switch: enabled
Threat Protection Lite: enabled
Analytics: disabled
Meshnet: enabled
----------------------------------------
Masked IP:  2.56.191.84
Location:   Dallas
ISP/Owner:  AS62240 Clouvider
Latency:    13.84 ms (to 103.86.96.100)
----------------------------------------
Active DNS: 103.86.96.100,103.86.99.100
DNS Owner:  AS136787 TEFINCOM S.A.
========================================
Setup complete! Keeping container alive...
(Note: TEFINCOM S.A. is the formal corporate entity behind NordVPN, proving your DNS routing remains completely within their ecosystem).

# Managing Meshnet Permissions

Meshnet permissions (such as allowing other devices to route traffic through this container, file-sharing, or local LAN access) are managed directly from your main NordVPN app or Nord Web Dashboard.


# Troubleshooting

## Meshnet Activation Fails
Personal NordVPN accounts have a strict limit on Meshnet devices. 
If you spun up this container previously without a persistent volume, you may have proliferated nodes that exceeded your limit.

If Meshnet fails to activate, the container log will print a clear warning box detailing your current peer count:
