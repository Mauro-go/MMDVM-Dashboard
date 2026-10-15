#!/usr/bin/env bash
# Optional LAN-only HTTP mode for MMDVM Dashboard.
# Run only after install.sh has completed successfully.
set -Eeuo pipefail
umask 077
MODE=${1:-}
APP=/opt/mmdvm-dashboard/backend/admin_api.py
SITE=/etc/apache2/sites-available/mmdvm-dashboard.conf
BACKUP=/var/lib/mmdvm-dashboard-http-switch
SERVICE=mmdvm-dashboard.service
fail(){ echo "ERROR: $*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || fail 'Run as root.'
[[ $MODE == http || $MODE == https ]] || fail 'Usage: sudo bash switch-http.sh http|https'
[[ -f $APP && -f $SITE ]] || fail 'Expected dashboard files not found.'
command -v python3 >/dev/null && command -v apache2ctl >/dev/null || fail 'Missing python3 or Apache.'

if [[ $MODE == http ]]; then
    [[ ! -e $BACKUP ]] || fail "Backup already exists at $BACKUP. Use https to restore before switching again."
    echo 'WARNING: HTTP exposes admin credentials and cookies to LAN eavesdropping.'
    echo 'HTTP will be restricted by Apache to private IPv4 networks and loopback.'
    echo 'Do NOT forward TCP port 80 from your router or expose it to the Internet.'
    read -r -p 'Type YES to enable LAN-only HTTP: ' OK
    [[ $OK == YES ]] || fail 'Cancelled.'
    install -d -m 700 "$BACKUP"
    cp -p "$APP" "$BACKUP/admin_api.py"
    cp -p "$SITE" "$BACKUP/mmdvm-dashboard.conf"
    python3 - "$APP" "$SITE" <<'PY'
from pathlib import Path
import re, sys
app, site = map(Path, sys.argv[1:])
s = app.read_text()
old = 'SESSION_COOKIE_SECURE=True'
assert s.count(old) == 1, 'Expected secure cookie setting not found uniquely'
s = s.replace(old, 'SESSION_COOKIE_SECURE=False', 1)
old = 'return parsed.scheme == "https" and parsed.netloc.lower() == host.lower()'
assert s.count(old) == 1, 'Expected same-origin validation not found uniquely'
s = s.replace(old, 'return parsed.scheme == "http" and parsed.netloc.lower() == host.lower()', 1)
compile(s, str(app), 'exec')
original = site.read_text()
match = re.search(r'(?m)^\s*ServerName\s+(\S+)', original)
assert match, 'Cannot determine original ServerName'
host = match.group(1)
assert re.fullmatch(r'[a-zA-Z0-9.-]+', host), 'Unsafe ServerName'
assert '<VirtualHost *:443>' in original, 'Expected HTTPS virtual host missing'
new = f'''# Temporary LAN-only HTTP mode; restore using switch-http.sh https
<VirtualHost *:80>
    ServerName {host}
    ProxyPreserveHost On
    ProxyRequests Off
    <Location />
        Require ip 127.0.0.1 ::1 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16
    </Location>
    ProxyPass / http://127.0.0.1:8088/
    ProxyPassReverse / http://127.0.0.1:8088/
    RequestHeader set X-Forwarded-Proto "http"
    ErrorLog ${{APACHE_LOG_DIR}}/mmdvm-dashboard-error.log
    CustomLog ${{APACHE_LOG_DIR}}/mmdvm-dashboard-access.log combined
</VirtualHost>
'''
app.write_text(s)
site.write_text(new)
PY
else
    [[ -f $BACKUP/admin_api.py && -f $BACKUP/mmdvm-dashboard.conf ]] || fail 'Original backup not found; refusing to guess HTTPS configuration.'
    cp -p "$BACKUP/admin_api.py" "$APP"
    cp -p "$BACKUP/mmdvm-dashboard.conf" "$SITE"
fi

# If validation or restart fails, return to the last known configuration.
if ! python3 - "$APP" <<'PY'
import ast,sys
ast.parse(open(sys.argv[1]).read())
PY
then
    echo 'Python validation failed.' >&2
    if [[ $MODE == http ]]; then cp -p "$BACKUP/admin_api.py" "$APP"; cp -p "$BACKUP/mmdvm-dashboard.conf" "$SITE"; fi
    exit 1
fi
if ! apache2ctl configtest; then
    echo 'Apache validation failed; restoring prior configuration.' >&2
    if [[ $MODE == http ]]; then cp -p "$BACKUP/admin_api.py" "$APP"; cp -p "$BACKUP/mmdvm-dashboard.conf" "$SITE"; fi
    exit 1
fi
if ! systemctl restart "$SERVICE" || ! systemctl reload apache2; then
    echo 'Service reload failed; check services and restore using https mode if needed.' >&2
    if [[ $MODE == http ]]; then cp -p "$BACKUP/admin_api.py" "$APP"; cp -p "$BACKUP/mmdvm-dashboard.conf" "$SITE"; systemctl restart "$SERVICE" || true; systemctl reload apache2 || true; fi
    exit 1
fi
if [[ $MODE == http ]]; then
    echo 'LAN-only HTTP enabled. The original HTTPS configuration is backed up.'
else
    rm -rf -- "$BACKUP"
    echo 'Original HTTPS configuration restored.'
fi
