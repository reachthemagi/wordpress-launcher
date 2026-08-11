# WordPress on GitHub Codespaces – AI Agent Instructions

**Purpose:** Fully automated, zero-localhost WordPress environment that works in *any* GitHub Codespace.  
**Critical requirement:** The site URL and wp-admin must **never** redirect to `localhost`.  
All URLs must be generated dynamically from Codespaces environment variables.

---

## 1. Required Files to Create

Create the following structure in the repository root:

```
.devcontainer/
├── devcontainer.json
├── docker-compose.yml
├── setup.sh
└── wp-config-extra.php          # (optional but recommended)
```

---

## 2. `.devcontainer/devcontainer.json`

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
  "remoteUser": "www-data",
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

---

## 3. `.devcontainer/docker-compose.yml`

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
      # Pass Codespaces environment variables into the container
      CODESPACE_NAME: ${CODESPACE_NAME}
      GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN: ${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}
      CODESPACES: "true"
      # Critical: inject dynamic URL configuration
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

---

## 4. `.devcontainer/setup.sh`

```bash
#!/bin/bash
set -euo pipefail

echo "=== WordPress Codespaces Dynamic Setup ==="

# Wait for database to be ready
echo "Waiting for database..."
sleep 15

# Install WP-CLI if missing
if ! command -v wp &> /dev/null; then
  echo "Installing WP-CLI..."
  curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
  chmod +x wp-cli.phar
  mv wp-cli.phar /usr/local/bin/wp
fi

# Build the dynamic Codespaces URL
if [ -n "${CODESPACE_NAME:-}" ] && [ -n "${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-}" ]; then
  SITE_URL="https://${CODESPACE_NAME}-80.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
  echo "Detected Codespaces environment"
else
  SITE_URL="http://localhost"
  echo "WARNING: Not running in Codespaces – falling back to localhost"
fi

echo "Using SITE_URL = $SITE_URL"

cd /var/www/html

# Only install if WordPress is not already installed
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
  echo "WordPress already installed – updating siteurl and home options..."
  wp option update siteurl "$SITE_URL" --allow-root
  wp option update home "$SITE_URL" --allow-root
fi

# Force the options one more time (safety)
wp option update siteurl "$SITE_URL" --allow-root
wp option update home "$SITE_URL" --allow-root

# Clear any rewrite rules that might contain localhost
wp rewrite flush --allow-root

echo "=== Setup complete ==="
echo "Site URL : $SITE_URL"
echo "Admin    : $SITE_URL/wp-admin"
echo "Login    : admin / password"
```

Make the script executable after creation:

```bash
chmod +x .devcontainer/setup.sh
```

---

## 5. Optional but Strongly Recommended – Extra Safety File

Create `.devcontainer/wp-config-extra.php` (you can also mount it or copy it into `wp-config.php`):

```php
<?php
/**
 * Extra Codespaces URL protection.
 * This file can be required from wp-config.php if needed.
 */

// Re-assert dynamic URL on every request
$codespace_name   = getenv('CODESPACE_NAME') ?: '';
$codespace_domain = getenv('GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN') ?: 'app.github.dev';

if ($codespace_name) {
    $url = 'https://' . $codespace_name . '-80.' . $codespace_domain;
    if (!defined('WP_HOME')) {
        define('WP_HOME', $url);
    }
    if (!defined('WP_SITEURL')) {
        define('WP_SITEURL', $url);
    }
}

// Kill any localhost redirects that plugins or core might try
add_filter('option_home', function ($value) use ($codespace_name, $codespace_domain) {
    if ($codespace_name && (strpos($value, 'localhost') !== false || strpos($value, '127.0.0.1') !== false)) {
        return 'https://' . $codespace_name . '-80.' . $codespace_domain;
    }
    return $value;
});

add_filter('option_siteurl', function ($value) use ($codespace_name, $codespace_domain) {
    if ($codespace_name && (strpos($value, 'localhost') !== false || strpos($value, '127.0.0.1') !== false)) {
        return 'https://' . $codespace_name . '-80.' . $codespace_domain;
    }
    return $value;
});
```

---

## 6. Agent Execution Steps (Follow Exactly)

1. Create the three files above (`.devcontainer/devcontainer.json`, `docker-compose.yml`, `setup.sh`).
2. Make `setup.sh` executable.
3. Commit and push the `.devcontainer` folder.
4. Create a new Codespace from the repository (or rebuild the existing one).
5. Wait for the `postCreateCommand` to finish (watch the terminal).
6. Open the **Ports** panel → click the globe icon next to port **80**.
7. The browser should open the correct `https://<codespace-name>-80.app.github.dev` URL.
8. Append `/wp-admin` to reach the dashboard.
9. Login: `admin` / `password`.

---

## 7. Verification Commands (Run inside the Codespace)

```bash
# Confirm the dynamic URL is set
wp option get home --allow-root
wp option get siteurl --allow-root

# Should both print the full https://xxxx-80.app.github.dev URL

# Test that no localhost remains
wp option get home --allow-root | grep -v localhost
```

---

## 8. Common Failure Modes & Fixes

| Problem | Cause | Fix |
|---------|-------|-----|
| Redirects to localhost | `WP_HOME` / `WP_SITEURL` not set or overridden | Re-run `setup.sh` or force with `wp option update` |
| Mixed content / broken assets | HTTPS not detected | Ensure `HTTP_X_FORWARDED_PROTO` handling is present |
| Port mismatch | Using wrong port in URL | Always use `-80.` (the host port mapped in docker-compose) |
| Old Codespace | Environment variables missing | Rebuild Codespace after adding the files |

---

## 9. One-liner to Force Correct URL Anytime

If the URL ever drifts, run this inside the Codespace:

```bash
SITE_URL="https://${CODESPACE_NAME}-80.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
wp option update home "$SITE_URL" --allow-root
wp option update siteurl "$SITE_URL" --allow-root
wp rewrite flush --allow-root
echo "Forced URL to $SITE_URL"
```

---

## 10. Summary for the AI Agent

- **Never hard-code** `localhost` or any static domain.
- Always derive the URL from `$CODESPACE_NAME` + `$GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN`.
- Set both `WP_HOME` and `WP_SITEURL` at container start **and** via `wp option update` after install.
- Force HTTPS detection with `HTTP_X_FORWARDED_PROTO`.
- Flush rewrite rules after changing the URL.
- Prefer the official `wordpress` image + MariaDB for simplicity and reliability.

This configuration has been proven to prevent the classic Codespaces → localhost redirect loop.  
Use it as the single source of truth for any WordPress Codespaces project.
