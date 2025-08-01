#!/usr/bin/env bash
# for node backend deployment
# Usage: . script.sh [GIT_URL] [BRANCH] [PM2_NAME] [DOMAIN] [ATTACH_DOMAIN] [PAT_TOKEN] [REPO_PRIVATE] [PACKAGE_MANAGER]
# Note: errors are trapped and reported without killing your shell
# online web: https://www.jdoodle.com/test-bash-shell-script-online
# chmod 755 <script.sh>

set -u -o pipefail
STEP="Initialization"
error_handler() {
  echo "❌ Error during: $STEP" >&2
  return 1
}
trap error_handler ERR

# ─── Defaults ─────────────────────────────────────────────────────────────────
STEP="Setting defaults"
DEFAULT_GIT_URL="" #git repo url
DEFAULT_BRANCH=""  #branch name
DEFAULT_PM2_NAME="" #pm2 process name
DEFAULT_ATTACH_DOMAIN=false      # true = nginx+certbot, false = skip, if you want to attach domain
DEFAULT_DOMAIN="" # domain name
DEFAULT_REPO_PRIVATE=false        # true=private repo (use PAT-Token), false=public repo
DEFAULT_GIT_PAT_TOKEN=""         #"ghp_YourPersonalAccessTokenHere"
DEFAULT_NODE_VERSION="22"  # 👈 Change this to whatever Node version you want (e.g., 18,20, 22, 24)
DEFAULT_PACKAGE_MANAGER="npm"    # "npm" or "yarn"
DEFAULT_PORT=3000
DEFAULT_FRONTEND_TYPE="react" #react ,vite, nextjs
DEFAULT_FORCE_BUILD=flase
# Your .env content (here-doc)
DEFAULT_ENV_CONTENT="$(cat <<'EOF'
# add more ENV vars here...
EOF
)"
# ────────────────────────────────────────────────────────────────────────────────

# ─── Parse args or fall back to defaults ──────────────────────────────────────
STEP="Parsing arguments"
GIT_URL="${1:-$DEFAULT_GIT_URL}"           
BRANCH="${2:-$DEFAULT_BRANCH}"             
PM2_NAME="${3:-$DEFAULT_PM2_NAME}"         
DOMAIN="${4:-$DEFAULT_DOMAIN}"             
ATTACH_DOMAIN="${5:-$DEFAULT_ATTACH_DOMAIN}" 
PAT_TOKEN="${6:-$DEFAULT_GIT_PAT_TOKEN}"  
REPO_PRIVATE="${7:-$DEFAULT_REPO_PRIVATE}"
PACKAGE_MANAGER="${8:-$DEFAULT_PACKAGE_MANAGER}"
PORT="${9:-$DEFAULT_PORT}"
FRONTEND_TYPE="${10:-$DEFAULT_FRONTEND_TYPE}"
FORCE_BUILD="${11:-$DEFAULT_FORCE_BUILD}"

# Validate package manager choice
if [[ "$PACKAGE_MANAGER" != "npm" && "$PACKAGE_MANAGER" != "yarn" ]]; then
  echo "⚠️  Invalid PACKAGE_MANAGER '$PACKAGE_MANAGER';"
  return 1
fi

# ─── Derive directory name ────────────────────────────────────────────────────
STEP="Deriving directory name"
DIR_NAME="$(basename "${GIT_URL%.git}")"

# ─── Install Node (with NVM) & npm ────────────────────────────────────────────
STEP="Installing Node via NVM"

echo "📦 Using Node.js version $DEFAULT_NODE_VERSION"

export NVM_DIR="$HOME/.nvm"
if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
  echo "ℹ️  NVM not found. Installing..."
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.4/install.sh | bash
fi
# shellcheck source=/dev/null
. "$NVM_DIR/nvm.sh"

if ! nvm ls "$DEFAULT_NODE_VERSION" | grep -q "$DEFAULT_NODE_VERSION"; then
  echo "🔧 Installing Node.js v$DEFAULT_NODE_VERSION"
  nvm install "$DEFAULT_NODE_VERSION"
fi

nvm use "$DEFAULT_NODE_VERSION"

# ─── Ensure npm works ────────────────────────────────────────────────────────
STEP="Verifying npm"
if ! command -v npm >/dev/null; then
  echo "❌ npm not found even after Node setup. Exiting..."
  return 1
fi
echo "✅ npm version: $(npm -v)"

# ─── Install Yarn globally if needed ─────────────────────────────────────────
if [[ "$PACKAGE_MANAGER" == "yarn" ]]; then
  STEP="Installing Yarn"
  if ! command -v yarn >/dev/null; then
    echo "ℹ️  Yarn not found. Installing globally via npm..."
    npm install -g yarn
  fi
  echo "✅ yarn version: $(yarn -v)"
fi

# ─── Install PM2 globally if needed ──────────────────────────────────────────
STEP="Installing PM2"
if ! command -v pm2 >/dev/null; then
  echo "ℹ️  PM2 not found. Installing globally..."
  npm install -g pm2
fi
echo "✅ pm2 version: $(pm2 -v)"

# ─── Install serve globally if needed ────────────────────────────────────────
STEP="Installing serve"
if ! command -v serve >/dev/null; then
  echo "ℹ️  serve not found. Installing globally via npm..."
  npm install -g serve
fi
echo "✅ serve version: $(serve --version)"

# ─── Clone the repository ────────────────────────────────────────────────────
STEP="Cloning repository"
if [[ -d "$DIR_NAME" ]]; then
  echo "❌ Error: directory '$DIR_NAME' already exists." >&2
  return 1
fi

# build auth URL for private repos
if [[ "$REPO_PRIVATE" == "true" ]]; then
  if [[ -z "$PAT_TOKEN" ]]; then
    echo "❌ Error: private repo specified but PAT_TOKEN is empty." >&2
    return 1
  fi
  BASE_URL="${GIT_URL#https://}"
  AUTH_GIT_URL="https://${PAT_TOKEN}@${BASE_URL}"
else
  AUTH_GIT_URL="$GIT_URL"
fi

echo "🔄 Cloning branch '$BRANCH' from '$GIT_URL' (private=$REPO_PRIVATE)..."
git clone --branch "$BRANCH" --single-branch "$AUTH_GIT_URL" || return 1

# ─── Enter project directory ──────────────────────────────────────────────────
STEP="Changing directory"
echo "📂 Entering directory '$DIR_NAME'..."
cd "$DIR_NAME" || return 1

# ─── Create/update .env ──────────────────────────────────────────────────────
STEP="Creating .env file"
#echo "$DEFAULT_ENV_CONTENT" > .env
echo "✅ .env created with the following content:"
#cat .env

# Strip whitespace, blank lines, and comment-only lines
# STRIPPED_CONTENT="$(echo "$DEFAULT_ENV_CONTENT" | sed '/^\s*$/d' | sed '/^\s*#/d')"

# if [[ -n "$STRIPPED_CONTENT" ]]; then
#   echo "$DEFAULT_ENV_CONTENT" > .env
#   echo "✅ .env created with the following content:"
#   cat .env
# else
#   echo "ℹ️ Skipping .env creation (DEFAULT_ENV_CONTENT is empty or only comments/whitespace)."
# fi

# ─── Install project dependencies ────────────────────────────────────────────
STEP="Installing dependencies"
echo "📦 Installing dependencies via $PACKAGE_MANAGER..."
if [[ "$PACKAGE_MANAGER" == "yarn" ]]; then
  yarn install || return 1
else
  npm install || return 1
fi

# ─── Build Project (React/Vite/Next.js) ───────────────────────────────────────
STEP="Checking and building frontend project"
echo "🔨 Preparing build for frontend type: $FRONTEND_TYPE using $PACKAGE_MANAGER"

if [[ "$PACKAGE_MANAGER" == "yarn" ]]; then
  BUILD_COMMAND="yarn build"
else
  BUILD_COMMAND="npm run build"
fi

SHOULD_BUILD=true

if [[ "$FORCE_BUILD" == "true" ]]; then
  echo "🔁 FORCE_BUILD=true: Rebuilding regardless of existing folders."
else
  # check if folder exists depending on FRONTEND_TYPE
  case "$FRONTEND_TYPE" in
    react)
      if [[ -d "build" ]]; then
        echo "✅ Skipping build: 'build/' folder already exists."
        SHOULD_BUILD=false
      fi
      ;;
    vite)
      if [[ -d "dist" ]]; then
        echo "✅ Skipping build: 'dist/' folder already exists."
        SHOULD_BUILD=false
      fi
      ;;
    nextjs)
      if [[ -d ".next" ]]; then
        echo "✅ Skipping build: '.next/' folder already exists."
        SHOULD_BUILD=false
      fi
      ;;
  esac
fi


if [[ "$SHOULD_BUILD" == true ]]; then
  echo "📦 Running build: $BUILD_COMMAND"
  $BUILD_COMMAND || { echo "❌ Build failed"; return 1; }
fi

# ─── Start application under PM2 ─────────────────────────────────────────────
STEP="Starting application with PM2"
echo "🚀 Starting app with PM2 as '$PM2_NAME' (Frontend: $FRONTEND_TYPE, Package: $PACKAGE_MANAGER)..."

case "$FRONTEND_TYPE" in
  react)
    pm2 start "serve -s build -l $PORT" --name "$PM2_NAME" || return 1
    ;;
  vite)
    pm2 start "serve -s dist -l $PORT" --name "$PM2_NAME" || return 1
    ;;
  nextjs)
    if [[ "$PACKAGE_MANAGER" == "yarn" ]]; then
      PORT=$PORT pm2 start "yarn start" --name "$PM2_NAME" || return 1
    else
      PORT=$PORT pm2 start "npm start" --name "$PM2_NAME" || return 1
    fi
    ;;
esac

# ─── Save PM2 process list for resurrect ────────────────────────────────────
STEP="Saving PM2 process list"
echo "💾 Saving PM2 process list..."
pm2 save || return 1

# ─── Optional: Setup nginx reverse proxy & TLS via Certbot ───────────────────
STEP="Configuring nginx + TLS"
if [[ "$ATTACH_DOMAIN" == "true" ]]; then
  # Install Nginx if needed
  STEP="Installing nginx"
  if ! command -v nginx >/dev/null; then
    echo "ℹ️  Installing Nginx..."
    sudo apt-get update && sudo apt-get install -y nginx || return 1
  fi

  # Install Certbot if needed
  STEP="Installing certbot"
  if ! command -v certbot >/dev/null; then
    echo "ℹ️  Installing Certbot..."
    sudo apt-get install -y certbot python3-certbot-nginx || return 1
  fi

  # Write Nginx site config
  STEP="Creating nginx site config"
  SITE_CONF="/etc/nginx/sites-available/$DOMAIN"
  echo "📝 Writing Nginx config for $DOMAIN..."
  sudo tee "$SITE_CONF" > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://localhost:$PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

  # Enable & reload
  STEP="Enabling nginx site"
  sudo rm -f /etc/nginx/sites-enabled/default || return 1
  sudo ln -sf "$SITE_CONF" /etc/nginx/sites-enabled/ || return 1
  STEP="Testing & reloading nginx"
  sudo nginx -t && sudo systemctl restart nginx || return 1

  # Obtain SSL cert
  STEP="Obtaining TLS certificate"
  sudo certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "admin@$DOMAIN" || return 1
  echo "✅ SSL certificate obtained for $DOMAIN."
fi

STEP="Complete"
echo "🎉 Setup complete! App is running under PM2 ('$PM2_NAME')."
