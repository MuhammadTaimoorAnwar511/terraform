#!/usr/bin/env bash
set -euo pipefail

# Load .env if present
if [ -f .env ]; then
  export $(grep -v '^\s*#' .env | xargs)
fi

: "${PACKAGE_MANAGER:="npm"}"
: "${CONTAINER_PORT:=3000}"
: "${START_COMMAND:=index.js}"
: "${HOST_PORT:=3000}"
: "${DOCKER_IMAGE_NAME:=npm-node-app}"
: "${CONTAINER_NAME:=npm-node-container}"

if [ -z "$PACKAGE_MANAGER" ]; then
  if [ -f yarn.lock ]; then
    PACKAGE_MANAGER="yarn"
  else
    PACKAGE_MANAGER="npm"
  fi
  echo "ℹ️  Auto-detected PACKAGE_MANAGER=${PACKAGE_MANAGER}"
fi

cat > Dockerfile <<EOF
# Multi-stage Dockerfile for backend 

# Builder stage: install all dependencies.
FROM node:18-alpine AS builder
WORKDIR /app

COPY package*.json ./
EOF

if [ "$PACKAGE_MANAGER" = "yarn" ]; then
cat >> Dockerfile <<EOF
COPY yarn.lock ./
RUN yarn install
EOF
else
cat >> Dockerfile <<EOF
RUN npm install
EOF
fi

cat >> Dockerfile <<EOF

COPY . .

# Project dependencies + source code
FROM node:18-alpine AS production
WORKDIR /app

COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app .

EXPOSE ${CONTAINER_PORT}

CMD ["node", "${START_COMMAND}"]
EOF

echo
echo "✅ Multi-stage Dockerfile generated for backend."


# —————————————————————————————————————————————————————————————————————————
# Show build & run commands
# —————————————————————————————————————————————————————————————————————————
echo
echo "🔧 To build your image:"
echo "    docker build -t ${DOCKER_IMAGE_NAME} ."
echo
echo "🔧 To run your container:"
echo "    docker run -d -p ${HOST_PORT}:${CONTAINER_PORT} \\
          --name ${CONTAINER_NAME} ${DOCKER_IMAGE_NAME}"
