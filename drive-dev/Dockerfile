FROM node:22-bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends git python3 python3-pip ripgrep ca-certificates tar && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY tsconfig.json ./
COPY src ./src
RUN npm run build
RUN mkdir -p /workspaces
ENV DRIVE_DEV_TRANSPORT=http HOST=0.0.0.0 PORT=3000 DRIVE_DEV_ROOT=/workspaces
EXPOSE 3000
CMD ["node", "dist/src/index.js", "--http"]
