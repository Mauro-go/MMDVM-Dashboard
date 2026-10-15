# MMDVM Dashboard

An independent web dashboard for an MMDVM repeater, with a live activity view, repeater information, system statistics and a protected administration interface. Interface languages: **English and Italian**.

> **Status: preview / not yet validated on a clean Debian installation.** Read this document and test on a spare machine before deploying to an active repeater. This repository must not contain station-specific configuration, personal photos, tokens, passwords, or backup files.

Italian instructions: [README_IT.md](README_IT.md).

## Safety and scope

The dashboard **reads** MMDVM configuration and logs. The installer does **not** edit `MMDVM.ini`, stop or restart `MMDVMHost`, or modify `DMRGateway`, `YSFGateway`, or other radio gateways. It installs its own Flask backend on `127.0.0.1:8088` and its own Apache virtual host. It never replaces `/var/www/html/index.html`.

The installer supports **fresh installations only**. If `/opt/mmdvm-dashboard`, `/var/lib/mmdvm-dashboard`, the `mmdvm-dashboard.service` unit, or the reserved Apache site already exists, it refuses to overwrite them. An existing dashboard using the same name requires a separate, manual migration plan.

## Requirements

- Debian **11, 12 or 13**, with systemd and root/sudo access. These are targeted versions, **not yet all tested**.
- Public DNS hostname resolving to this machine and inbound **TCP 80/443** for Let's Encrypt. The installer does not support LAN-only, self-signed, or external-reverse-proxy setups yet.
- Available loopback TCP port **8088**; no Apache VirtualHost already claiming the chosen hostname.
- Read access to the actual MMDVM log files, `MMDVM.ini` and optional DMR ID / TalkGroup files. The installer **does not** grant extra log permissions automatically.
- An installation source containing all repository files, including `config/dashboard.ini.example`.

The installer uses Debian packages: Apache, Certbot, Python 3, Flask, Werkzeug, psutil, curl, OpenSSL and related utilities. No global `pip install` is required. `requirements.txt` documents Python dependencies.

## Installation (test machine recommended)

```bash
sudo apt-get update
sudo apt-get install -y git
sudo git clone https://github.com/Mauro-go/MMDVM-Dashboard.git /opt/mmdvm-dashboard-source
cd /opt/mmdvm-dashboard-source
sudo bash install.sh
```

**The GitHub repository must actually contain the files before these commands can work.** Do not run the installer on a host where the current dashboard uses `/opt/mmdvm-dashboard` or `mmdvm-dashboard.service`.

The installer asks for a public hostname, a Let's Encrypt email address and explicit confirmation. It installs dependencies, creates a dedicated `mmdvm-dashboard` service account, copies application files, creates a private state directory, generates a one-time setup token and a session secret, starts the service, configures Apache/HTTPS, and checks the API.

## First access: setup token and Admin page

At the end of installation, `install.sh` prints a **one-time setup token** in the terminal. If you did not save it, retrieve it **on the server** as `root`, before creating the administrator account:

```bash
sudo cat /var/lib/mmdvm-dashboard/setup-token
```

**Never publish or share the token**, and never commit it to GitHub. It is stored in a restricted file and deleted automatically once the first administrator is created.

Open the dashboard at `https://YOUR-HOSTNAME/`. The intended administration address is **`https://YOUR-HOSTNAME/api/admin/page`**: **verify this route in `backend/admin_api.py` before release**, since the published backend must explicitly serve `admin/admin.html` at that URL.

On the first Admin visit, enter the setup token, choose an **administrator username** and **password**, confirm the password, and select **Create administrator**. Then sign in with those credentials. Use Admin to configure the MMDVM.ini path, log directory, and other required paths.

After successful setup, `setup-token` no longer exists. Do not regenerate it to reset a forgotten password; credential recovery needs a separate secure procedure.

## Existing dashboard / migration

Two dashboards can coexist if they use different service names, backend ports and web addresses. This installer reserves the name `mmdvm-dashboard.service` and port 8088, so it **does not automatically rename or replace** an existing installation with those identifiers.

The installer checks for `logtailer.service`. **Only if you explicitly confirm that this service belongs exclusively to the old dashboard** can you opt to stop it. The script waits until the new HTTPS/API checks succeed, then stops it **only if active** and disables its automatic startup **only if enabled**. It does not delete the unit or its files. On a failure after stopping it, the script attempts to restore its enabled state and restart it. Never select this option if the logtailer is shared with other software.

Other legacy services are **not** automatically detected or stopped. Check your own installation manually, for example:

```bash
systemctl list-units --type=service --all | grep -Ei 'dashboard|logtailer'
systemctl status logtailer.service
sudo ss -ltnp
```

### Existing `index.html` and Apache sites

If `/var/www/html/index.html` exists, the installer warns and **leaves it untouched**. Since no replacement takes place, it does not create a backup of that file. It refuses to use a hostname already present in Apache site configuration and refuses to overwrite its own Apache site file. Existing Apache configuration is otherwise preserved, although installing/enabling Apache modules and reloading Apache affects the web server as a whole. Back up your Apache configuration before installing on a shared web host.

## Administration and images

The administration page supports dashboard identity, repeater data, hardware, station/organization details, links, image **paths**, and MMDVM file paths (subject to the version deployed). Radio modes are read from the actual MMDVM configuration and displayed read-only. Images are **not uploaded from the browser** in this release: place your own images under `frontend/images/` using appropriate file permissions, then enter relative paths such as `images/banner.jpg`. The installer does not copy personal images.

### Important permissions

Application code is owned by `root`; `config/dashboard.ini` and `/var/lib/mmdvm-dashboard/` are writable by the dedicated service user. The service reads MMDVM logs and configuration only if operating-system permissions permit it. Grant the **minimum read permissions necessary**; do not run the dashboard as root and do not make logs or credentials world-readable.

## Service management and diagnostics

```bash
sudo systemctl status mmdvm-dashboard.service
sudo journalctl -u mmdvm-dashboard.service -n 100 --no-pager
sudo apache2ctl configtest
sudo systemctl status apache2
curl -fsS http://127.0.0.1:8088/api/status
```

For TLS errors, check DNS, port 80 reachability and Certbot output. For missing data, verify MMDVM paths and permissions. Do not restart radio services just to troubleshoot the dashboard.

## Failure, rollback and uninstall

The installer **is not transactional**. Failures before migration leave the old dashboard service running, but may leave newly created files, packages, systemd units, Apache configuration or certificates. Inspect these before retrying. If it stopped a confirmed `logtailer.service` and a subsequent check fails, it attempts to restart that service; check its status manually.

To return to an old dashboard, verify the old service and web configuration, then explicitly start/re-enable the correct legacy service. **Do not** blindly delete `/var/www/html`, `/etc/apache2`, MMDVM directories or radio services. A fully automated uninstaller has **not** been implemented yet; remove only the files created for this dashboard after taking backups and checking dependencies.

## Repository privacy

Never commit `config/dashboard.ini`, `/var/lib/mmdvm-dashboard/`, passwords, session secrets, setup tokens, personal images, logs, database dumps or `*.bak*`. Review `git status` and `git diff --cached` before publishing. Only `config/dashboard.ini.example` with generic values belongs in the repository.

## License and attribution

MMDVM Dashboard by **IV3SCP** · [GitHub](https://github.com/Mauro-go/MMDVM-Dashboard). Confirm the project's license before publication.

## Experimental option: LAN-only HTTP

`install.sh` remains dedicated to **HTTPS** installation with a public hostname and Let's Encrypt. After a successful HTTPS installation, use the separate `switch-http.sh` script:

```bash
sudo bash switch-http.sh http
```

The script requests confirmation, backs up `backend/admin_api.py` and the Apache virtual host under `/var/lib/mmdvm-dashboard-http-switch/`, restricts HTTP access to private IPv4 networks and loopback, and adapts the Admin session cookie and origin check. The Admin path remains `/api/admin/page`, using HTTP. On hosts with multiple Apache sites, reaching the correct virtual host by IP address alone may require additional configuration.

To **restore the previous HTTPS configuration**, run:

```bash
sudo bash switch-http.sh https
```

**Warning:** HTTP does not encrypt passwords or session cookies. Never forward port 80 to the public Internet or use HTTP on untrusted networks. Apache access rules are not a substitute for firewall and router restrictions. This mode has not been tested on a clean Debian host; test it on a non-production machine first. It is not a standalone installer and requires a working HTTPS installation. Keep the backup directory until HTTPS is restored.
