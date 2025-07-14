#!/usr/bin/env bash
# online web: https://www.jdoodle.com/test-bash-shell-script-online
# chmod 755 <certbot.sh>
# . certbot.sh  : to run

set -u -o pipefail
STEP="Initialization"
error_handler() {
  echo "❌ Error during: $STEP" >&2
  return 1
}
trap error_handler ERR

# ─── Defaults ─────────────────────────────────────────────────────────────────
STEP="Setting defaults"
# ───----------─────────────────────────────────────────────────────────────────

DOMAIN=""     # domain name (leave empty to skip nginx/certbot)
PORT=                       # application port

# ─── Optional: Setup nginx reverse proxy & TLS via Certbot ───────────────────

if [[ -n "$DOMAIN" ]]; then
  STEP="Installing nginx"
  if ! command -v nginx >/dev/null; then
    echo "ℹ️  Installing Nginx..."
    sudo apt-get update && sudo apt-get install -y nginx
  fi

  STEP="Installing certbot"
  if ! command -v certbot >/dev/null; then
    echo "ℹ️  Installing Certbot..."
    sudo apt-get install -y certbot python3-certbot-nginx
  fi

  STEP="Creating nginx site config"
  
  SITE_CONF="/etc/nginx/sites-available/$DOMAIN"
  echo "📝 Writing Nginx config for $DOMAIN (port $PORT)..."
  
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

  STEP="Enabling nginx site"
  
  sudo rm -f /etc/nginx/sites-enabled/default
  sudo ln -sf "$SITE_CONF" /etc/nginx/sites-enabled/

  STEP="Testing & reloading nginx"
  
  sudo nginx -t
  sudo systemctl restart nginx.service 

  STEP="Obtaining TLS certificate"
  sudo certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "admin@$DOMAIN"
  sudo systemctl restart nginx.service 
  
  echo "✅ SSL certificate obtained for $DOMAIN."
fi

STEP="Complete"
echo "🎉 $DOMAIN Configure Successfully "
