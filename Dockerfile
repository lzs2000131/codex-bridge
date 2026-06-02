# codex-bridge — minimal production image
#
# The proxy itself is dependency-free; the only thing `npm install` pulls is the
# optional `redis` client, so the REDIS_URL backend works out of the box in the
# bundled docker-compose stack. Without REDIS_URL the proxy runs purely in-memory
# and the redis client is simply never imported.

FROM node:20-alpine

ENV NODE_ENV=production \
    PROXY_PORT=4000

WORKDIR /app

# Install dependencies first for better layer caching. --omit=dev keeps
# optionalDependencies (redis) while skipping devDependencies. No lockfile is
# committed (single optional dep), so `npm install` is used rather than `npm ci`.
COPY package.json ./
RUN npm install --omit=dev --no-audit --no-fund \
    && npm cache clean --force

# Application code (single file + supporting assets).
COPY proxy.mjs ./
COPY proxy-models.example.json ./

# Drop privileges — the base image ships a non-root `node` user.
USER node

EXPOSE 4000

# Liveness probe hits the always-open /health endpoint using Node's global fetch
# (Node 20+), avoiding any extra tooling in the image.
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PROXY_PORT||4000)+'/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "proxy.mjs"]
