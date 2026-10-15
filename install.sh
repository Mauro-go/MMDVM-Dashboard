#!/usr/bin/env bash
# MMDVM Dashboard — Debian installer; run on a TEST host first.
set -Eeuo pipefail
umask 027

APP_DIR=/opt/mmdvm-dashboard
STATE_DIR=/var/lib/mmdvm-dashboard
APP_USER=mmdvm-dashboard
SERVICE=mmdvm-dashboard
SITE=mmdvm-dashboard
PORT=8088
SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ACME_ROOT=/var/lib/mmdvm-dashboard-acme
OLD_SERVICE=''
OLD_WAS_ACTIVE=0
OLD_WAS_ENABLED=0
OLD_STOPPED=0
MIGRATION_COMMITTED=0

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
info() { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
rollback() {
    local status=$?
    if (( status != 0 )); then
        warn "Installation did not complete. Inspect any newly created files/services before retrying."
        if [[ -n "$OLD_SERVICE" && "$OLD_STOPPED" == 1 && "$MIGRATION_COMMITTED" == 0 ]]; then
            warn "Attempting to restart previously active service: $OLD_SERVICE"
            if [[ "$OLD_WAS_ENABLED" == 1 ]]; then systemctl enable "$OLD_SERVICE" || true; fi
            systemctl start "$OLD_SERVICE" || warn "Manual restart required: systemctl start $OLD_SERVICE"
        fi
    fi
}
trap rollback EXIT

[[ $EUID -eq 0 ]] || fail 'Run as root (sudo bash install.sh).'
[[ -r /etc/os-release ]] || fail 'Cannot identify operating system.'
# shellcheck disable=SC1091
. /etc/os-release
[[ ${ID:-} == debian ]] || fail 'Only Debian is currently supported.'
[[ ${VERSION_ID:-} =~ ^(11|12|13)$ ]] || fail 'Supported Debian releases: 11, 12, 13.'
[[ -d /run/systemd/system ]] || fail 'A running systemd installation is required.'
[[ ! -e "$APP_DIR" && ! -e "$STATE_DIR" ]] || fail 'Existing dashboard directory/state found. Refusing to overwrite.'
[[ ! -e "/etc/systemd/system/$SERVICE.service" && ! -e "/lib/systemd/system/$SERVICE.service" && ! -e "/usr/lib/systemd/system/$SERVICE.service" ]] || fail 'Service name mmdvm-dashboard is already in use. Manual migration is required.'
[[ ! -e "/etc/apache2/sites-available/$SITE.conf" ]] || fail 'Apache site mmdvm-dashboard.conf already exists.'

required=(backend/app.py backend/admin_api.py backend/auth.py backend/config.py backend/config_writer.py backend/parser.py admin/admin.html frontend/index.html frontend/about.html frontend/lang/it.json frontend/lang/en.json config/dashboard.ini.example)
for f in "${required[@]}"; do [[ -f "$SOURCE_DIR/$f" ]] || fail "Missing $f"; done

cat <<'INTRO'
MMDVM Dashboard — Debian 11/12/13 installer (public HTTPS deployment).
It will NOT modify MMDVM.ini, MMDVMHost, DMRGateway, YSFGateway or other radio services.
It will NOT overwrite /var/www/html/index.html or an existing dashboard installation.
A public DNS name and inbound TCP 80/443 are required for Let's Encrypt.
For LAN-only installations or an existing mmdvm-dashboard.service, stop and use
manual migration; this installer intentionally refuses unsafe replacement.
INTRO
if [[ -f /var/www/html/index.html ]]; then
    warn 'Existing /var/www/html/index.html detected; it will be left untouched.'
fi

# A legacy logtailer is NOT necessarily owned by the old dashboard.
# Only allow explicit selection, never automatically infer ownership.
if systemctl list-unit-files --type=service --no-legend 2>/dev/null | awk '{print $1}' | grep -Fxq 'logtailer.service'; then
    printf '\nExisting logtailer.service detected. It may be shared with other software.\n'
    read -r -p 'Is this service EXCLUSIVELY for the dashboard you want to replace? [yes/NO] ' OWNED
    if [[ "$OWNED" == yes ]]; then
        read -r -p 'Stop it after the new dashboard passes checks, then disable at boot? [yes/NO] ' MIGRATE
        if [[ "$MIGRATE" == yes ]]; then
            OLD_SERVICE=logtailer.service
            if systemctl is-active --quiet "$OLD_SERVICE"; then OLD_WAS_ACTIVE=1; fi
            if systemctl is-enabled --quiet "$OLD_SERVICE"; then OLD_WAS_ENABLED=1; fi
        fi
    fi
fi

read -r -p 'Public dashboard hostname (e.g. dashboard.example.org): ' DOMAIN
DOMAIN=${DOMAIN,,}
[[ $DOMAIN =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ && $DOMAIN == *.* && $DOMAIN != *..* ]] || fail 'Invalid hostname.'
read -r -p "Email for Let's Encrypt notices: " EMAIL
[[ $EMAIL == *@*.* && $EMAIL != *' '* ]] || fail 'Invalid email.'

# Refuse a hostname already configured elsewhere. Do not touch other virtual hosts.
if [[ -d /etc/apache2/sites-available ]] && grep -RhiE '^[[:space:]]*Server(Name|Alias)[[:space:]]+' /etc/apache2/sites-available/*.conf 2>/dev/null | awk '{for (i=2;i<=NF;i++) print tolower($i)}' | grep -Fxq "$DOMAIN"; then
    fail "Hostname $DOMAIN already appears in an Apache virtual host. Resolve conflict manually."
fi
if command -v ss >/dev/null 2>&1 && ss -ltnH "( sport = :$PORT )" | grep -q .; then
    fail "Local TCP port $PORT is occupied. Resolve conflict manually."
fi
read -r -p 'Proceed with package installation and Apache/HTTPS configuration? [yes/NO] ' ANSWER
[[ "$ANSWER" == yes ]] || fail 'Cancelled.'

info 'Installing Debian dependencies'
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y apache2 iproute2 curl certbot python3-flask python3-werkzeug python3-psutil openssl ca-certificates
ss -ltnH "( sport = :$PORT )" | grep -q . && fail "Port $PORT is occupied." || true

info 'Creating service account and application files'
if ! id -u "$APP_USER" >/dev/null 2>&1; then
    useradd --system --user-group --home-dir "$STATE_DIR" --shell /usr/sbin/nologin "$APP_USER"
fi
install -d -o root -g root -m 755 "$APP_DIR" "$APP_DIR/backend" "$APP_DIR/frontend" "$APP_DIR/frontend/lang" "$APP_DIR/admin"
install -d -o "$APP_USER" -g "$APP_USER" -m 750 "$APP_DIR/config"
for f in backend/app.py backend/admin_api.py backend/auth.py backend/config.py backend/config_writer.py backend/parser.py admin/admin.html frontend/index.html frontend/about.html frontend/lang/it.json frontend/lang/en.json; do
    install -o root -g root -m 644 "$SOURCE_DIR/$f" "$APP_DIR/$f"
done
install -o "$APP_USER" -g "$APP_USER" -m 640 "$SOURCE_DIR/config/dashboard.ini.example" "$APP_DIR/config/dashboard.ini"
install -d -o "$APP_USER" -g "$APP_USER" -m 700 "$STATE_DIR"
install -d -o root -g root -m 755 "$APP_DIR/frontend/images"

info 'Generating first-run secrets'
install -o "$APP_USER" -g "$APP_USER" -m 600 /dev/null "$STATE_DIR/session-secret"
install -o "$APP_USER" -g "$APP_USER" -m 600 /dev/null "$STATE_DIR/setup-token"
openssl rand -hex 32 > "$STATE_DIR/session-secret"
openssl rand -hex 24 > "$STATE_DIR/setup-token"
chown "$APP_USER:$APP_USER" "$STATE_DIR/session-secret" "$STATE_DIR/setup-token"
chmod 600 "$STATE_DIR/session-secret" "$STATE_DIR/setup-token"

info 'Creating systemd service'
cat > "/etc/systemd/system/$SERVICE.service" <<UNIT
[Unit]
Description=MMDVM Dashboard
After=network.target

[Service]
Type=simple
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$APP_DIR/backend
Environment=MMDVM_DASHBOARD_STATE_DIR=$STATE_DIR
ExecStart=/usr/bin/python3 $APP_DIR/backend/app.py
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$STATE_DIR $APP_DIR/config

[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now "$SERVICE.service"
sleep 2
systemctl is-active --quiet "$SERVICE.service" || fail 'Dashboard backend failed to start.'
curl -fsS --max-time 10 "http://127.0.0.1:$PORT/api/status" >/dev/null || fail 'Dashboard backend health check failed.'

info 'Configuring Apache and ACME challenge'
a2enmod proxy proxy_http ssl headers rewrite >/dev/null
install -d -o root -g root -m 755 "$ACME_ROOT/.well-known/acme-challenge"
cat > "/etc/apache2/sites-available/$SITE.conf" <<APACHE_HTTP
<VirtualHost *:80>
    ServerName $DOMAIN
    DocumentRoot $ACME_ROOT
    Alias /.well-known/acme-challenge/ $ACME_ROOT/.well-known/acme-challenge/
    <Directory $ACME_ROOT>
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/mmdvm-dashboard-error.log
    CustomLog \${APACHE_LOG_DIR}/mmdvm-dashboard-access.log combined
</VirtualHost>
APACHE_HTTP
a2ensite "$SITE.conf" >/dev/null
apache2ctl configtest
systemctl reload apache2

info 'Requesting TLS certificate'
certbot certonly --webroot -w "$ACME_ROOT" -d "$DOMAIN" --email "$EMAIL" \
    --agree-tos --non-interactive --no-eff-email || fail 'Certificate request failed; inspect DNS and port 80. Existing dashboard services were not stopped.'

info 'Enabling HTTPS reverse proxy'
cat > "/etc/apache2/sites-available/$SITE.conf" <<APACHE_HTTPS
<VirtualHost *:80>
    ServerName $DOMAIN
    DocumentRoot $ACME_ROOT
    Alias /.well-known/acme-challenge/ $ACME_ROOT/.well-known/acme-challenge/
    <Directory $ACME_ROOT>
        Require all granted
    </Directory>
    RewriteEngine On
    RewriteCond %{REQUEST_URI} !^/\.well-known/acme-challenge/
    RewriteRule ^ https://$DOMAIN%{REQUEST_URI} [R=301,L,NE]
</VirtualHost>
<VirtualHost *:443>
    ServerName $DOMAIN
    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/$DOMAIN/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/$DOMAIN/privkey.pem
    ProxyPreserveHost On
    ProxyRequests Off
    ProxyPass / http://127.0.0.1:$PORT/
    ProxyPassReverse / http://127.0.0.1:$PORT/
    RequestHeader set X-Forwarded-Proto "https"
    ErrorLog \${APACHE_LOG_DIR}/mmdvm-dashboard-error.log
    CustomLog \${APACHE_LOG_DIR}/mmdvm-dashboard-access.log combined
</VirtualHost>
APACHE_HTTPS
apache2ctl configtest
systemctl reload apache2
curl -fsS --max-time 15 --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN/api/status" >/dev/null || fail 'HTTPS/API health check failed. Legacy service remains unchanged.'

if [[ -n "$OLD_SERVICE" ]]; then
    info "Migrating explicitly confirmed legacy service $OLD_SERVICE"
    if systemctl is-active --quiet "$OLD_SERVICE"; then
        OLD_WAS_ACTIVE=1
        systemctl stop "$OLD_SERVICE"
        OLD_STOPPED=1
    fi
    if systemctl is-enabled --quiet "$OLD_SERVICE"; then
        OLD_WAS_ENABLED=1
        systemctl disable "$OLD_SERVICE"
    fi
    # Recheck after stopping the legacy service.
    if ! curl -fsS --max-time 15 --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN/api/status" >/dev/null; then
        if [[ "$OLD_WAS_ENABLED" == 1 ]]; then systemctl enable "$OLD_SERVICE" || true; fi
        fail 'Post-migration health check failed.'
    fi
    MIGRATION_COMMITTED=1
fi

printf '\nInstallation complete: https://%s/\n' "$DOMAIN"
printf 'One-time admin setup token (store securely):\n'
cat "$STATE_DIR/setup-token"
printf '\nThe token is deleted after initial admin setup.\n'
printf 'Configure MMDVM paths in Admin and grant the dashboard user READ access to relevant logs.\n'
printf 'Existing /var/www/html/index.html and all radio services were left untouched.\n'
