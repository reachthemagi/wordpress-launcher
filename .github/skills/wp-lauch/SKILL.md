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

> **CRITICAL — `$$` escaping:** docker-compose interpolates `$var` in the
> `WORDPRESS_CONFIG_EXTRA` block. Every PHP `$` variable MUST be written as
> `$$` (e.g. `$$codespace_name`, `$$_SERVER`). If you forget this, compose
> silently blanks the PHP variables and the dynamic URL logic breaks. Validate
> with `docker compose -f .devcontainer/docker-compose.yml config` — it must
> show no `variable is not set` warnings.

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
        // === AGGRESSIVE CODESPACES URL FIX (DO NOT REMOVE) ===
        $$codespace_name   = getenv('CODESPACE_NAME') ?: '';
        $$codespace_domain = getenv('GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN') ?: 'app.github.dev';

        if (!empty($$codespace_name)) {
          $$dynamic_host = $$codespace_name . '-80.' . $$codespace_domain;
          $$dynamic_url  = 'https://' . $$dynamic_host;

          // Force the constants (highest priority)
          define('WP_HOME', $$dynamic_url);
          define('WP_SITEURL', $$dynamic_url);

          // Force server variables that WordPress uses for redirects.
          // UNCONDITIONAL: the Codespaces proxy does NOT reliably forward
          // Host/X-Forwarded-Host, so do NOT gate this on isset().
          $$_SERVER['HTTP_HOST']   = $$dynamic_host;
          $$_SERVER['SERVER_NAME'] = $$dynamic_host;
          $$_SERVER['HTTPS']       = 'on';

          // Also handle forwarded headers (fallback if present)
          if (isset($$_SERVER['HTTP_X_FORWARDED_PROTO']) && $$_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
            $$_SERVER['HTTPS'] = 'on';
          }
          if (isset($$_SERVER['HTTP_X_FORWARDED_HOST'])) {
            $$_SERVER['HTTP_HOST'] = $$_SERVER['HTTP_X_FORWARDED_HOST'];
          }
        }

        // Force SSL for admin
        define('FORCE_SSL_ADMIN', true);
        // === END FIX ===
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

# Also clean any leftover localhost references in the database
wp search-replace 'http://localhost' "$SITE_URL" --all-tables --precise --allow-root || true
wp search-replace 'https://localhost' "$SITE_URL" --all-tables --precise --allow-root || true
wp search-replace 'http://127.0.0.1' "$SITE_URL" --all-tables --precise --allow-root || true

wp rewrite flush --allow-root

# Fix permissions so the web server can still write
chown -R www-data:www-data /var/www/html/wp-content || true
chmod -R 755 /var/www/html/wp-content || true

echo "=== Setup complete ==="
echo "Site URL : $SITE_URL"
echo "Admin    : $SITE_URL/wp-admin"
echo "Login    : admin / password"
```

> **WP-CLI persistence gotcha:** `setup.sh` installs WP-CLI into `/usr/local/bin`
> inside the container, which lives on an anonymous volume. If you recreate the
> container (`docker compose up -d --force-recreate`), WP-CLI is wiped and must
> be reinstalled before running any `wp` command. Either re-run `setup.sh`
> (which reinstalls it) or reinstall manually:
> ```bash
> docker exec <container> bash -c 'curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar && chmod +x wp-cli.phar && mv wp-cli.phar /usr/local/bin/wp'
> ```

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

Then confirm the redirect target (must be the dynamic URL, never localhost):

```bash
curl -s -o /dev/null -w "%{http_code} -> %{redirect_url}\n" http://localhost/wp-admin/
# Expect: 302 -> https://<codespace>-80.app.github.dev/wp-login.php?redirect_to=...
```

Also confirm no `localhost` remains in the served HTML:

```bash
curl -s http://localhost/ | grep -io "localhost" | head
# Expect: no output
```

Also validate the compose interpolation (no `variable is not set` warnings):

```bash
docker compose -f .devcontainer/docker-compose.yml config
```

## Force Correct URL Anytime

```bash
SITE_URL="https://${CODESPACE_NAME}-80.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
wp option update home "$SITE_URL" --allow-root
wp option update siteurl "$SITE_URL" --allow-root
wp search-replace 'http://localhost' "$SITE_URL" --all-tables --precise --allow-root || true
wp search-replace 'https://localhost' "$SITE_URL" --all-tables --precise --allow-root || true
wp search-replace 'http://127.0.0.1' "$SITE_URL" --all-tables --precise --allow-root || true
wp rewrite flush --allow-root
echo "Forced URL to $SITE_URL"
```

## Common Failures

| Problem | Cause | Fix |
|---------|-------|-----|
| Workbench cannot connect | `remoteUser` set to `www-data` | Change to `"remoteUser": "root"` and recreate Codespace |
| `/wp-admin` redirects to `localhost` | Conditional proxy handling: `HTTP_HOST`/`HTTPS` only set when `X-Forwarded-*` headers arrive, but the Codespaces proxy does NOT reliably forward them | Use the **unconditional** normalization in `WORDPRESS_CONFIG_EXTRA` (always set `HTTP_HOST`/`SERVER_NAME`/`HTTPS` inside the `if (!empty($codespace_name))` guard) + `FORCE_SSL_ADMIN` + `wp search-replace` cleanup |
| Mixed content warnings | Missing HTTPS detection | Ensure `WORDPRESS_CONFIG_EXTRA` forces `$_SERVER['HTTPS'] = 'on'` unconditionally |
| Port mismatch | Wrong port in URL | Always use `-80.` (the published host port) |
| `wp: command not found` after recreate | WP-CLI lives on an anonymous volume that resets on `--force-recreate` | Re-run `setup.sh` or reinstall WP-CLI manually (see note above) |
| Browser still shows localhost after server is verified correct | Browser/HSTS cache or stale Codespace URL | Server is likely fine — hard-refresh, clear site data, or use a fresh Codespace URL. Incognito does not always bypass HSTS |

## Notes

- The official `wordpress` image + MariaDB is preferred for simplicity and reliability.
- Plugins and themes from wordpress.org can be installed normally via the admin or WP-CLI.
- Installed plugins/themes live in the container volume and are lost if the Codespace is deleted (unless committed elsewhere).