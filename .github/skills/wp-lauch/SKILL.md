# WordPress on GitHub Codespaces

Create a reliable WordPress development environment in GitHub Codespaces that uses the dynamic Codespaces URL and never redirects to localhost.

## Critical Requirements

- Never hard-code `localhost` or any static domain.
- Always derive the site URL from `CODESPACE_NAME` + `GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN`.
- Use `remoteUser: root` (required for the official WordPress image — `www-data` causes workbench connection failures).
- Force both `WP_HOME` and `WP_SITEURL` at container start and after install.
- Handle HTTPS correctly behind the Codespaces reverse proxy.

## Required Files

Create this structure in the repository root:

```
.devcontainer/
├── devcontainer.json
├── docker-compose.yml
└── setup.sh
```

### 1. `.devcontainer/devcontainer.json`

```json
{
  "name": "WordPress Codespaces (Dynamic URL)",
  "dockerComposeFile": "docker-compose.yml",
  "service": "wordpress",
  "workspaceFolder": "/var/www/html",
  "forwardPorts": [80],
  "portsAttributes": {
    "80": {
      "label": "WordPress",
      "onAutoForward": "notify"
    }
  },
  "postCreateCommand": "bash .devcontainer/setup.sh",
  "remoteUser": "root",
  "containerEnv": {
    "CODESPACES": "true"
  },
  "customizations": {
    "vscode": {
      "extensions": [
        "bmewburn.vscode-intelephense-client",
        "xdebug.php-debug",
        "wordpresstoolbox.wordpress-toolbox"
      ]
    }
  }
}
```

**Important:** Always use `"remoteUser": "root"`. Using `"www-data"` causes the workbench to fail connecting to the Codespace.

### 2. `.devcontainer/docker-compose.yml`

```yaml
services:
  wordpress:
    image: wordpress:latest
    restart: unless-stopped
    ports:
      - "80:80"
    environment:
      WORDPRESS_DB_HOST: db
      WORDPRESS_DB_USER: wordpress
      WORDPRESS_DB_PASSWORD: wordpress
      WORDPRESS_DB_NAME: wordpress
      CODESPACE_NAME: ${CODESPACE_NAME}
      GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN: ${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}
      CODESPACES: "true"
      WORDPRESS_CONFIG_EXTRA: |
        // === DYNAMIC CODESPACES URL CONFIG (DO NOT REMOVE) ===
        $codespace_name = getenv('CODESPACE_NAME') ?: '';
        $codespace_domain = getenv('GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN') ?: 'app.github.dev';

        if (!empty($codespace_name)) {
          $dynamic_url = 'https://' . $codespace_name . '-80.' . $codespace_domain;
          define('WP_HOME', $dynamic_url);
          define('WP_SITEURL', $dynamic_url);
        }

        // Force HTTPS detection behind Codespaces reverse proxy
        if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
          $_SERVER['HTTPS'] = 'on';
        }
        if (isset($_SERVER['HTTP_X_FORWARDED_HOST'])) {
          $_SERVER['HTTP_HOST'] = $_SERVER['HTTP_X_FORWARDED_HOST'];
        }
        // === END DYNAMIC CONFIG ===
    volumes:
      - ..:/var/www/html
      - wordpress_data:/var/www/html/wp-content
    depends_on:
      - db

  db:
    image: mariadb:10.11
    restart: unless-stopped
    environment:
      MYSQL_DATABASE: wordpress
      MYSQL_USER: wordpress
      MYSQL_PASSWORD: wordpress
      MYSQL_ROOT_PASSWORD: rootpassword
    volumes:
      - db_data:/var/lib/mysql

volumes:
  db_data:
  wordpress_data:
```

### 3. `.devcontainer/setup.sh`

```bash
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
```

After creating the file, make it executable:

```bash
chmod +x .devcontainer/setup.sh
```

## Execution Steps

1. Create the three files above.
2. Make `setup.sh` executable.
3. Commit and push the `.devcontainer` folder.
4. **Delete** any existing Codespace for this repo (do not just rebuild).
5. Create a brand new Codespace.
6. Wait for the `postCreateCommand` to finish.
7. Open the Ports panel → click the globe icon next to port 80.
8. Append `/wp-admin` to the URL.
9. Login with `admin` / `password`.

## Verification

Run inside the Codespace:

```bash
wp option get home --allow-root
wp option get siteurl --allow-root
```

Both commands must return the full `https://xxxx-80.app.github.dev` URL (never localhost).

## Force Correct URL Anytime

```bash
SITE_URL="https://${CODESPACE_NAME}-80.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
wp option update home "$SITE_URL" --allow-root
wp option update siteurl "$SITE_URL" --allow-root
wp rewrite flush --allow-root
echo "Forced URL to $SITE_URL"
```

## Common Failures

| Problem | Cause | Fix |
|---------|-------|-----|
| Workbench cannot connect | `remoteUser` set to `www-data` | Change to `"remoteUser": "root"` and recreate Codespace |
| Redirects to localhost | WP_HOME / WP_SITEURL not forced | Re-run setup.sh or use the force URL one-liner |
| Mixed content warnings | Missing HTTPS detection | Ensure WORDPRESS_CONFIG_EXTRA contains the X-Forwarded-Proto block |
| Port mismatch | Wrong port in URL | Always use `-80.` (the published host port) |

## Notes

- The official `wordpress` image + MariaDB is preferred for simplicity and reliability.
- Plugins and themes from wordpress.org can be installed normally via the admin or WP-CLI.
- Installed plugins/themes live in the container volume and are lost if the Codespace is deleted (unless committed elsewhere).