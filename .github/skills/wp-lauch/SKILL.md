---
name: wordpress
description: Steps to create, configure, and run a standard (non-VIP) WordPress instance in a GitHub Codespace, from an empty or placeholder repository. Use when setting up a WordPress dev environment where wp-admin plugin/theme installs must behave like normal WordPress, when a repo only contains this skill and needs the full devcontainer scaffolded, or when WordPress is not running in the Codespace yet.
---

# Standard WordPress Codespace Setup (from scratch)

This skill provisions a **normal WordPress** installation inside a GitHub
Codespace so that plugins and themes can be added the standard way (via the
wp-admin dashboard, WP-CLI, or by dropping folders into `wp-content`). It does
**not** use the WordPress VIP platform conventions.

> **When to use this skill:** the target repository is meant to be a
> run-of-the-mill WordPress site (not VIP). The only requirement to begin is
> this skill file present in the repo; everything else is created by the agent
> below.

## Assumptions / prerequisites

- The workspace repo already exists and Codespaces can open it.
- Docker is available inside the devcontainer (GitHub Codespaces provides this
  when you use a `dockerComposeFile`-based devcontainer).
- The repo does not already contain a working WordPress install. If one exists,
  skip straight to **Step 5** once the devcontainer is running.

## End state

A browser-accessible WordPress site (default port **8080**) with:

- A `wordpress` database and user, running on MariaDB/MySQL.
- WP-CLI available inside the container.
- A mounted `src/` (or `app/`) folder so all WP core files are visible in the
  editor.
- Normal wp-admin where plugins/themes can be installed from the WordPress.org
  repository or uploaded directly.

---

## Step 1 — Decide the layout

Create the WordPress core inside the repo so it is version-controllable.
Use this layout:

```
repo-root/
├── .devcontainer/
│   ├── devcontainer.json
│   ├── Dockerfile
│   └── docker-compose.yml
└── src/                  # mount point for WP core (/var/www/html)
```

`src/` is where WordPress core files live. It is mounted from the container's
Apache docroot so you can edit themes/plugins from VS Code.

---

## Step 2 — Create the devcontainer configuration

Create these three files under `.devcontainer/`.

### `.devcontainer/devcontainer.json`

```jsonc
{
  "name": "WordPress",
  "dockerComposeFile": "docker-compose.yml",
  "service": "wordpress",
  "workspaceFolder": "/var/www/html",
  "shutdownAction": "stopCompose",
  "forwardPorts": [8080, 3306],
  "portsAttributes": {
    "8080": {
      "label": "Application",
      "onAutoForward": "notify",
      "elevateIfNeeded": true
    },
    "3306": {
      "label": "MySQL",
      "onAutoForward": "ignore"
    }
  },
  "remoteUser": "www-data",
  "mounts": [
    "source=${localWorkspaceFolder}/src,target=/var/www/html,type=bind,consistency=cached"
  ],
  "customizations": {
    "vscode": {
      "extensions": [
        "bmewburn.vscode-intelephense-client",
        "wordpresstoolbox.wordpress-toolbox",
        "dbaeumer.vscode-eslint",
        "esbenp.prettier-vscode",
        "ms-azuretools.vscode-docker"
      ]
    }
  }
}
```

Notes for the agent:

- `dockerComposeFile` + `service` + `dockerCompose` combination makes Codespaces
  run Compose; the `wordpress` service is the primary dev container.
- `workspaceFolder` is the Apache docroot so VS Code opens WP core.
- `remoteUser: www-data` matches the Apache user so file permissions work and
  wp-admin can handle auto-updates/installs without ownership errors.
- The bind mount in `mounts` maps `src/` to `/var/www/html`. **Do not use a
  named `./` volume for WP core** here — the workspace bind mount is what makes
  files editable from VS Code.

### `.devcontainer/docker-compose.yml`

```yaml
services:
  db:
    image: mariadb:11
    restart: unless-stopped
    environment:
      MYSQL_DATABASE: wordpress
      MYSQL_USER: wordpress
      MYSQL_PASSWORD: wordpress
      MYSQL_ROOT_PASSWORD: root
    volumes:
      - db_data:/var/lib/mysql
    ports:
      - "3306:3306"

  wordpress:
    build: .
    restart: unless-stopped
    depends_on:
      - db
    ports:
      - "8080:80"
    environment:
      WORDPRESS_DB_HOST: db:3306
      WORDPRESS_DB_USER: wordpress
      WORDPRESS_DB_PASSWORD: wordpress
      WORDPRESS_DB_NAME: wordpress
      # Allow dashboard plugin/theme installs and the WordPress.org API.
      WORDPRESS_CONFIG_EXTRA: |
        define( 'FS_METHOD', 'direct' );
        define( 'DISALLOW_FILE_EDIT', false );
    volumes:
      - ./../src:/var/www/html
      - ./../src/wp-content/uploads:/var/www/html/wp-content/uploads

volumes:
  db_data:
```

Notes for the agent:

- Use the `wordpress:php8.x-apache` runtime by building from the Dockerfile in
  the next step so WP-CLI is included. `build: .` refers to
  `.devcontainer/../.devcontainer`, i.e. this folder's Dockerfile.
- `FS_METHOD = 'direct'` lets WordPress write theme/plugin files directly,
  which is what makes wp-admin installs work.
- The `db` service uses MariaDB 11; MySQL 8 is also acceptable — pick one and
  stay consistent.
- If you need WordPress multisite or object caching, add those env vars here.

### `.devcontainer/Dockerfile`

```dockerfile
FROM wordpress:php8.3-apache

# Install WP-CLI for command-line operations.
RUN curl -o /usr/local/bin/wp https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x /usr/local/bin/wp

# Convenience: keep the container's www-data able to write to the mounted volume.
# (Bind mounts inherit host ownership; see Step 5 note about permissions.)
```

> If the environment needs the phpGD, mysqli, zip, or intl extensions, they come
> bundled with the official `wordpress:php8.3-apache` image. Only add extra PHP
> packages here if you run into missing-extension errors.

---

## Step 3 — Prepare the workspace folder

Before (re)building the Codespace:

```bash
mkdir -p src
```

Committing this empty folder ensures Git tracks the mount point. WP core will
be populated the first time the container starts (the official image copies
core into `/var/www/html` on first boot if the directory is empty).

Add a `.gitignore` at the repo root so generated/vendor content is not
committed accidentally:

```gitignore
# WP core content that's regenerated or user-uploaded
src/wp-content/uploads/*
!src/wp-content/uploads/.gitkeep
```

(If you prefer to keep uploads out of git but persist them, the
`WORDPRESS_DB_*` + named volume handles the DB; uploads live under the mounted
`src/wp-content/uploads`.)

---

## Step 4 — Rebuild the Codespace / launch the devcontainer

The agent must trigger a fresh build so Compose provisions the container
(Compose-based devcontainers are instantiated at container start):

1. If the Codespace is currently open, stop it and restart it, choosing
   **"Rebuild Container"** (or run the
   `Dev Containers: Rebuild Container` command). This is required when adding
   or changing `devcontainer.json`/Compose files.
2. Wait for the devcontainer to fully initialize (Docker pulls
   `wordpress:php8.3-apache` and `mariadb:11` on first run).
3. Confirm the services are up from a terminal inside the container:

```bash
docker ps
```

Expect two running containers: `wordpress` and `db`.

---

## Step 5 — Verify and wire up the database

Because `/var/www/html` is a bind mount, WP core may already be populated by
the image. Verify readiness:

1. From the container, wait for the DB to accept connections:

```bash
# Retry until it succeeds (the db container may take ~15s on first boot).
until nc -z db 3306; do sleep 2; done; echo "db ready"
```

2. Confirm the MySQL credentials are reachable with the values from the
   Compose env (`wordpress` / `wordpress` on database `wordpress`):

```bash
mysql -h db -u wordpress -pwordpress -e "SHOW DATABASES;"
```

3. Fix volume permissions so the `www-data` web user can write (installs,
   uploads):

```bash
sudo chown -R www-data:www-data /var/www/html
```

> Codespaces mounts the repo as `vscode` (UID 1000) while Apache runs as
> `www-data`. Changing ownership of the mounted `src/` fixes wp-admin install
> and upload errors. If you edited the deploy as `vscode`, run this again after
> making file changes, or set `remoteUser` accordingly.

---

## Step 6 — Set the Codespace URL and normalize the proxy host (important!)

This is the step that prevents the "everything redirects to `localhost`" bug
and it must be done **before** completing the install. Skip it and you'll need
to fight cached `301` redirects to `http://localhost:<port>`.

### Why it's needed

GitHub Codespaces serves your site through an HTTPS reverse proxy (the
`https://<codespace-name>-8080.app.github.dev` URL). That proxy does **not**
preserve the original `Host` header and does not always forward
`X-Forwarded-Host`. With the plain `wordpress`/Apache image, WordPress then
sees `HTTP_HOST=localhost:<port>` over an `http` scheme and generates every
canonical and redirect URL as `localhost:<port>` — so `/wp-admin` bounces to
`http://localhost:8080/` and you can't log in.

(For contrast, a VIP Codespaces skeleton built with the Automattic nginx image
handles this natively — that's why those repos don't have the problem.)

### 1. Determine the Codespace URL

In the Codespace terminal:

```bash
echo "Site URL: https://${CODESPACE_NAME}-8080.app.github.dev"
```

Use that value (e.g. `https://cuddly-space-umbrella-4qgjrq45rrxr2qpg4-8080.app.github.dev`)
everywhere below. It is unique per Codespace — a fresh Codespace gets a new one.

### 2. Normalize the proxy host in `wp-config.php`

Edit `src/wp-config.php` (created by the Docker entrypoint on first boot) and
replace the stock reverse-proxy block with an **unconditional** normalization.
Because the site is only ever reached through the Codespace proxy, it is safe
to hardcode the domain and HTTPS scheme:

```php
// GitHub Codespaces serves this instance through an HTTPS reverse proxy that
// does NOT preserve the Host header. Normalize the server identity here so
// WordPress always emits correct, canonical HTTPS URLs (homepage, wp-admin,
// wp-login). Only ever reached via the Codespace URL, so this is safe.
if ( isset( $_SERVER['HTTP_HOST'] ) ) {
    $_SERVER['HTTP_HOST']   = '<CODESPACE_NAME>-8080.app.github.dev';
    $_SERVER['SERVER_NAME'] = '<CODESPACE_NAME>-8080.app.github.dev';
}
$_SERVER['HTTPS'] = 'on';
```

Replace `<CODESPACE_NAME>` in the snippet with the Codespace name from step 1
(the bare hostname, e.g. `cuddly-space-umbrella-4qgjrq45rrxr2qpg4` — no
`https://` and no port).

> Also set the `WP_SITEURL` / `WP_HOME` constants in the "Add any custom values"
> block of `wp-config.php` to the same URL as a second layer of protection:
> ```php
> define( 'WP_SITEURL', 'https://<CODESPACE_NAME>-8080.app.github.dev' );
> define( 'WP_HOME',    'https://<CODESPACE_NAME>-8080.app.github.dev' );
> ```

Verify it with worst-case headers (no forwarded headers at all):

```bash
# Expect: / -> 200, /wp-admin -> 302 to https://<CODESPACE>-8080.../wp-login.php
curl -s -o /dev/null -w "root:      %{http_code} -> %{redirect_url}\n" -H "Host: localhost:8080" http://localhost:8080/
curl -s -o /dev/null -w "/wp-admin: %{http_code} -> %{redirect_url}\n" -H "Host: localhost:8080" http://localhost:8080/wp-admin/
```

---

## Step 7 — Finish the WordPress install

Open the forwarded **Application** port (`8080`) in the browser:

1. The standard 5-minute install screen appears. Fill in site title,
   admin username, password, and email, then **Install WordPress**.
2. Log in at `/wp-admin`.
3. Confirm plugins and themes can be installed the normal way:
   - **Plugins → Add New** should search the WordPress.org repository.
   - **Plugins → Add New → Upload Plugin** should accept a `.zip`.
   - **Appearance → Themes** and **Themes → Add New** likewise.

> If the install wizard fails to connect to the DB (`Error establishing a
> database connection`), re-check Step 5: the `wp-config.php` DB host must be
> `db` (the Compose service name), not `localhost`.

---

## Step 8 — (Optional) Install core via WP-CLI instead of the wizard

If you prefer scripting the install (no interactive browser wizard):

```bash
cd /var/www/html

# Use the Codespace URL (from Step 6), NOT localhost, so the DB stores the
# correct siteurl/home from the very start.
wp core install \
  --url="https://<CODESPACE_NAME>-8080.app.github.dev" \
  --title="My WordPress Site" \
  --admin_user=admin \
  --admin_password=admin \
  --admin_email=admin@example.com \
  --skip-email
```

> If you install with `--url="http://localhost:8080"` by mistake, fix the DB
> options afterwards (these are what wp-admin redirects honor, alongside the
> constants from Step 6):
> ```bash
> wp option update siteurl "https://<CODESPACE_NAME>-8080.app.github.dev"
> wp option update home    "https://<CODESPACE_NAME>-8080.app.github.dev"
> ```

Then create the `wp-config.php` if it is missing:

```bash
wp config create \
  --dbname=wordpress \
  --dbuser=wordpress \
  --dbpass=wordpress \
  --dbhost=db \
  --skip-check --force
```

> The web wizard in Step 7 is generally preferred because it sets salts and the
> admin user interactively, but either path is valid.

---

## Step 9 — Add themes and plugins (normal WordPress behavior)

Because this is standard WordPress (no VIP restrictions), any of these work:

1. **Dashboard:** Plugins/Themes → Add New → search & install, then **Activate**.
2. **Upload:** Plugins/Themes → Add New → Upload a `.zip`.
3. **WP-CLI:**
   ```bash
   wp plugin install advanced-custom-fields --activate
   wp theme install light-speed --activate
   ```
4. **Manual:** drop a folder directly into `src/wp-content/plugins/` or
   `src/wp-content/themes/` (visible in VS Code), then activate in wp-admin.

---

## Step 10 — Sanity checks for the agent

After setup, verify success with:

```bash
# WP core responds over HTTP
curl -sI http://localhost:8080 | head -1          # expect HTTP/1.1 200 OK

# Database is reachable from the web container
mysql -h db -u wordpress -pwordpress -e "USE wordpress; SELECT 1;"

# wp-cli works and reports the version
wp core version

# List installed plugins (should include defaults)
wp plugin list
```

If `curl` does not return 200:

- Confirm the container port mapping `8080:80` is intact (`docker ps`).
- Check the forwarded port in Codespaces is `8080`.
- View logs: `docker logs <wordpress_container_id>`.

---

## Common pitfalls (check these first when something breaks)

- **WP redirects to `http://localhost:<port>` (especially `/wp-admin`)** —
  the #1 cause is not doing Step 6 (Codespace URL + proxy normalization).
  The Codespaces proxy drops the real `Host` header, so without the
  `wp-config.php` normalization + `WP_SITEURL`/`WP_HOME` + correct
  `siteurl`/`home` options, WordPress generates `localhost` URLs. Fix:
  follow Step 6 and update the DB options, then hard-refresh / incognito to
  drop the cached 301.
- **Wrong DB host** — WP must connect to the Compose service name `db`, not
  `localhost`, unless nginx/Apache is in the same network namespace.
- **Port already in use** — use a different host port (e.g. `8081:80`) and
  update `forwardPorts` + the install URL.
- **Permission denied on install/upload** — run the `chown` in Step 5 after any
  repo file changes, or keep `remoteUser: www-data`.
- **`Error establishing a database connection`** — the `db` service wasn't
  ready; wait (Step 5) then recheck credentials.
- **WordPress.org installs blocked** — make sure `WP_DISABLE_...` style flags
  are not set and that the container has outbound internet (default is on in
  Codespaces).
- **Writable directories** for plugin/theme install: WP needs
  `wp-content/plugins`, `wp-content/themes`, and `wp-content/uploads` writable
  by the PHP user. Confirm ownership is `www-data`.

---

## Definition of done

- `.devcontainer/` (devcontainer.json, Dockerfile, docker-compose.yml) exists.
- The Codespace builds and two containers (`wordpress`, `db`) are running.
- The WordPress install wizard completes, or `wp core install` succeeds.
- **Step 6 was done**: `wp-config.php` normalizes the proxy host, and
  `siteurl`/`home` (or `WP_SITEURL`/`WP_HOME`) point at the Codespace URL.
- `/wp-admin` on the **Codespace URL** redirects to the Codespace login page
  (not `localhost`), and **Plugins/Add New** installs from the WordPress.org
  repo.
- A test plugin (e.g. `wp plugin install akismet`) installs and activates.