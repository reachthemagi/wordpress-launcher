#!/bin/bash
set -euo pipefail

echo "=== WordPress Codespaces Dynamic Setup ==="

# Wait for database
echo "Waiting for database..."
sleep 15

# Install WP-CLI if missing
if ! command -v wp &> /dev/null; then
  echo "Installing WP-CLI..."
  curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
  chmod +x wp-cli.phar
  mv wp-cli.phar /usr/local/bin/wp
fi

# Build dynamic Codespaces URL
if [ -n "${CODESPACE_NAME:-}" ] && [ -n "${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-}" ]; then
  SITE_URL="https://${CODESPACE_NAME}-80.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
  echo "Detected Codespaces environment"
else
  SITE_URL="http://localhost"
  echo "WARNING: Not running in Codespaces – falling back to localhost"
fi

echo "Using SITE_URL = $SITE_URL"

cd /var/www/html

# Install WordPress if needed
if ! wp core is-installed --allow-root 2>/dev/null; then
  echo "Running wp core install..."
  wp core install \
    --url="$SITE_URL" \
    --title="WordPress Codespaces" \
    --admin_user="admin" \
    --admin_password="password" \
    --admin_email="admin@example.com" \
    --skip-email \
    --allow-root
else
  echo "WordPress already installed – forcing correct URLs..."
fi

# Always force the correct URLs (critical)
wp option update siteurl "$SITE_URL" --allow-root
wp option update home "$SITE_URL" --allow-root
wp rewrite flush --allow-root

# Fix permissions so the web server can still write
chown -R www-data:www-data /var/www/html/wp-content || true
chmod -R 755 /var/www/html/wp-content || true

echo "=== Setup complete ==="
echo "Site URL : $SITE_URL"
echo "Admin    : $SITE_URL/wp-admin"
echo "Login    : admin / password"