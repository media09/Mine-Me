FROM node:22-alpine

ENV NODE_ENV=production
WORKDIR /app

COPY package.json package-lock.json ./
COPY services/pool-gateway/package.json ./services/pool-gateway/package.json

RUN npm ci --omit=dev --workspace=@mine-me/pool-gateway --include-workspace-root=false

COPY services/pool-gateway ./services/pool-gateway

USER node
EXPOSE 8081
CMD ["npm", "run", "start", "--workspace=@mine-me/pool-gateway"]
