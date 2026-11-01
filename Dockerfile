FROM ubuntu:22.04

# Prevent interactive prompts during installation
ENV DEBIAN_FRONTEND=noninteractive

# Add build arguments for metadata tracking
ARG BUILD_DATE=unknown
ARG VCS_REF=unknown

LABEL org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}"

ENV IMAGE_BUILD_DATE="${BUILD_DATE}" \
    IMAGE_VCS_REF="${VCS_REF}"

# Install core networking dependencies
RUN apt-get update && apt-get install -y \
    curl \
    iptables \
    iproute2 \
    iputils-ping \
    && rm -rf /var/lib/apt/lists/*

# Add NordVPN GPG key and repository manually
RUN apt-get update && apt-get install -y gnupg && \
    curl -sS https://repo.nordvpn.com/gpg/nordvpn_public.asc | gpg --dearmor > /usr/share/keyrings/nordvpn-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/nordvpn-keyring.gpg] https://repo.nordvpn.com/deb/nordvpn/debian stable main" > /etc/apt/sources.list.d/nordvpn.list && \
    apt-get update && \
    apt-get install -y nordvpn && \
    apt-get clean

# Copy our startup script into the image
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set the script to run when the container starts
ENTRYPOINT ["/entrypoint.sh"]