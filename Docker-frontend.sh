#!/usr/bin/env bash
set -euo pipefail

# Load .env if present
if [ -f .env ]; then
  export $(grep -v '^\s*#' .env | xargs)
fi

# Variables with defaults
: "${FRONTEND_TYPE:=react}"       # react, vite, or nextjs
: "${PACKAGE_MANAGER:="yarn"}"
: "${CONTAINER_PORT:=80}"    # change it if project is of next js 
: "${HOST_PORT:=3000}"       # Host port to map to
: "${DOCKER_IMAGE_NAME:=node-react-app}"
: "${CONTAINER_NAME:=node-react-container}"

# Auto-detect PACKAGE_MANAGER if not set in .env
if [ -z "$PACKAGE_MANAGER" ]; then
  if [ -f yarn.lock ]; then
    PACKAGE_MANAGER="yarn"
  else
    PACKAGE_MANAGER="npm"
  fi
  echo "ℹ️  Auto-detected PACKAGE_MANAGER=${PACKAGE_MANAGER}"
fi

# Auto-detect FRONTEND_TYPE if not provided
if [ -z "$FRONTEND_TYPE" ]; then
  if grep -q 'react-scripts' package.json; then
    FRONTEND_TYPE="react"
  elif grep -q 'vite' package.json; then
    FRONTEND_TYPE="vite"
  elif grep -q 'next' package.json; then
    FRONTEND_TYPE="nextjs"
  else
    echo "❌ Could not auto-detect FRONTEND_TYPE. Please set FRONTEND_TYPE=react|vite|nextjs in .env or as env var."
    exit 1
  fi
  echo "ℹ️  Auto-detected FRONTEND_TYPE=${FRONTEND_TYPE}"
fi

echo "🚀 Generating Dockerfile for ${FRONTEND_TYPE} frontend..."

cat > Dockerfile <<EOF
# Multi-stage Dockerfile for ${FRONTEND_TYPE} frontend

# Builder stage
FROM node:18-alpine AS builder
WORKDIR /app

# Copy manifest and lock files
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

# Copy all sources
COPY . .
EOF

if [ "$PACKAGE_MANAGER" = "yarn" ]; then
  cat >> Dockerfile <<EOF
RUN yarn build
EOF
else
  cat >> Dockerfile <<EOF
RUN npm run build
EOF
fi

case "$FRONTEND_TYPE" in
  react)
    BUILD_DIR="build"
    ;;
  vite)
    BUILD_DIR="dist"
    ;;
  nextjs)
    BUILD_DIR=".next"
    ;;
esac

# Production stage
if [ "$FRONTEND_TYPE" = "nextjs" ]; then
  cat >> Dockerfile <<EOF

FROM node:18-alpine AS production
WORKDIR /app

# Copy built code and production dependencies
COPY --from=builder /app/package*.json ./
EOF
  if [ "$PACKAGE_MANAGER" = "yarn" ]; then
    cat >> Dockerfile <<EOF
COPY --from=builder /app/yarn.lock ./
RUN yarn install
EOF
  else
    cat >> Dockerfile <<EOF
RUN npm install
EOF
  fi
  cat >> Dockerfile <<EOF
COPY --from=builder /app/.next ./.next
COPY --from=builder /app/public ./public

EXPOSE ${CONTAINER_PORT}    #for nextjs only
#CMD ["${PACKAGE_MANAGER}", "run", "start"]
CMD ["sh", "-c", "PORT=${CONTAINER_PORT} ${PACKAGE_MANAGER} run start"]
EOF
else
  cat >> Dockerfile <<EOF

FROM nginx:alpine AS production

# Copy static assets for serving
COPY --from=builder /app/${BUILD_DIR} /usr/share/nginx/html

# Optional: Copy custom nginx config if needed
# COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 80 # for react and vite only
CMD ["nginx", "-g", "daemon off;"]
EOF
fi

echo
cat Dockerfile | sed 's/^/   /'
echo

echo "✅ Multi-stage Dockerfile generated for ${FRONTEND_TYPE} frontend."

echo
# Build & Run instructions
echo "🔧 To build your image:"
echo "    docker build -t ${DOCKER_IMAGE_NAME} ."
echo
echo "🔧 To run your container:"
if [ "$FRONTEND_TYPE" = "nextjs" ]; then
  echo "    docker run -d -p ${HOST_PORT}:${CONTAINER_PORT} --name ${CONTAINER_NAME} ${DOCKER_IMAGE_NAME}"
else
  echo "    docker run -d -p ${HOST_PORT}:80 --name ${CONTAINER_NAME} ${DOCKER_IMAGE_NAME}" 
fi
