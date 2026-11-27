FROM node:22-bookworm-slim

ENV NODE_ENV=production
WORKDIR /app

# Install the signed HashVault APT package for the Stratum proxy.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl gnupg; \
    curl -fsSL https://hashvault.github.io/apt/KEY.gpg | gpg --dearmor -o /usr/share/keyrings/hashvault.gpg; \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/hashvault.gpg] https://hashvault.github.io/apt stable main" > /etc/apt/sources.list.d/hashvault.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends vltrig-proxy; \
    rm -rf /var/lib/apt/lists/*

COPY package.json package-lock.json ./
COPY services/pool-gateway/package.json ./services/pool-gateway/package.json
RUN npm ci --omit=dev --workspace=@mine-me/pool-gateway --include-workspace-root=false

COPY services/pool-gateway ./services/pool-gateway
COPY services/pool-proxy/config.example.json ./services/pool-proxy/config.example.json
RUN chmod 755 services/pool-gateway/start.sh && chown -R node:node /app

USER node
ENV GATEWAY_BIND_HOST=0.0.0.0
ENV GATEWAY_WS_PATH=/ws
ENV POOL_PROXY_HOST=127.0.0.1
ENV POOL_PROXY_PORT=3333
EXPOSE 10000
ENTRYPOINT ["bash", "services/pool-gateway/start.sh"]
