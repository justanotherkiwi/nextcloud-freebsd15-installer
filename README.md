# Nextcloud FreeBSD 15 Installer

Automated FreeBSD 15 Nextcloud installer for internal deployments using Apache, PHP-FPM, MariaDB, Redis, and self-signed SSL.

This project provides a FreeBSD-native `/bin/sh` installer that builds a working Nextcloud instance with no interactive prompts. It is intended for internal lab, business, MSP, or self-hosted environments where Nextcloud will either be accessed internally or placed behind a reverse proxy later.

---

## Features

- FreeBSD 15 compatible
- FreeBSD-native `/bin/sh` script
- No Bash dependency
- No Linux service commands
- Fully automated install
- Generates the Nextcloud admin password
- Generates the MariaDB database password
- Generates a self-signed SSL certificate
- Enables both HTTP and HTTPS access
- Optional HTTP-to-HTTPS redirect
- Installs and configures:
  - Apache 2.4
  - PHP-FPM
  - MariaDB
  - Redis
  - Nextcloud latest release
- Creates a timestamped install log
- Creates a timestamped credentials file
- Can be rerun after a failed partial install
- Suitable for reverse-proxy use later

---

## Intended Use

This installer is designed for **internal-only deployments**.

Example use cases:

- Internal Nextcloud file server
- MSP client deployment
- Lab Nextcloud server
- Proof-of-concept environment
- Reverse-proxy-backed internal service
- FreeBSD-based self-hosted cloud storage

This script does **not** use Certbot or public Let's Encrypt certificates. Instead, it creates a local self-signed certificate so HTTPS can be used internally if desired.

---

## Tested Target Platform

This script is written for:

```text
FreeBSD 15.x
```

It may work on other FreeBSD versions, but FreeBSD 15.x is the intended target.

---

## Stack

The installer configures the following stack:

```text
FreeBSD 15
Apache 2.4
PHP-FPM
MariaDB
Redis
Nextcloud
Self-signed SSL
```

---

## Repository Name Suggestion

Recommended repository name:

```text
nextcloud-freebsd15-installer
```

Recommended repository description:

```text
Automated FreeBSD 15 Nextcloud installer for internal deployments with Apache, PHP-FPM, MariaDB, Redis, and self-signed SSL.
```

---

## Important Security Notes

Do **not** commit generated logs, credentials, private keys, or certificates to GitHub.

The script generates files such as:

```text
install_YYYYMMDD_HHMM.log
nextcloud_credentials_YYYYMMDD_HHMM.txt
nextcloud-selfsigned.key
nextcloud-selfsigned.crt
nextcloud-openssl.cnf
```

The credentials file contains sensitive passwords.

The private key file is sensitive and must remain private.

---

## Recommended `.gitignore`

Add the following `.gitignore` to the repository:

```gitignore
# Runtime logs
install_*.log

# Generated credentials
nextcloud_credentials_*.txt

# Certificates and private keys
*.key
*.crt
*.csr
*.pem
nextcloud-openssl.cnf

# Downloaded archives
*.tar
*.tar.bz2
*.tgz
*.zip

# Editor and OS files
.DS_Store
*.swp
*.swo
```

---

## What the Installer Does

The installer performs the following actions:

1. Verifies it is running as root
2. Creates a timestamped install log
3. Creates a timestamped credentials file
4. Generates a Nextcloud admin password
5. Generates a MariaDB database password
6. Bootstraps and updates FreeBSD `pkg`
7. Selects a supported PHP package branch
8. Selects a supported MariaDB package branch
9. Installs required packages
10. Configures PHP
11. Configures PHP-FPM
12. Configures MariaDB
13. Creates the Nextcloud database and database user
14. Generates a self-signed SSL certificate
15. Configures Apache HTTP and HTTPS virtual hosts
16. Downloads the latest Nextcloud release
17. Extracts Nextcloud to `/usr/local/www/nextcloud`
18. Creates the Nextcloud data directory
19. Starts and enables services
20. Runs the Nextcloud command-line installer
21. Applies baseline Nextcloud configuration
22. Enables Redis/APCu caching where available
23. Enables Nextcloud cron mode
24. Adds the Nextcloud cron job
25. Restarts services
26. Prints final URLs and credentials location

---

## Default Paths

| Item | Default Path |
|---|---|
| Script directory | Directory where the script is run from |
| Install log | `install_YYYYMMDD_HHMM.log` |
| Credentials file | `nextcloud_credentials_YYYYMMDD_HHMM.txt` |
| Nextcloud web root | `/usr/local/www/nextcloud` |
| Nextcloud data directory | `/var/db/nextcloud/data` |
| Apache vhost config | `/usr/local/etc/apache24/Includes/nextcloud.conf` |
| PHP config | `/usr/local/etc/php.ini` |
| PHP-FPM pool | `/usr/local/etc/php-fpm.d/nextcloud.conf` |
| MariaDB config | `/usr/local/etc/mysql/conf.d/nextcloud.cnf` |
| SSL directory | `/usr/local/etc/ssl/nextcloud` |
| SSL certificate | `/usr/local/etc/ssl/nextcloud/nextcloud-selfsigned.crt` |
| SSL private key | `/usr/local/etc/ssl/nextcloud/nextcloud-selfsigned.key` |

---

## Quick Start

Clone or copy the installer to the FreeBSD server.

```sh
cd /root
ee install-nextcloud-freebsd15.sh
chmod +x install-nextcloud-freebsd15.sh
sh /root/install-nextcloud-freebsd15.sh
```

After completion, read the generated credentials file:

```sh
cat /root/nextcloud_credentials_*.txt
```

Then open one of the URLs shown at the end of the install.

Example:

```text
http://nextcloud.internal/
https://nextcloud.internal/
```

Or use the server IP address shown in the credentials file.

---

## Custom Hostname

To set a custom internal hostname:

```sh
SERVER_NAME=cloud.internal.example.local sh /root/install-nextcloud-freebsd15.sh
```

Example:

```sh
SERVER_NAME=cloud.internal.podcom.nz sh /root/install-nextcloud-freebsd15.sh
```

Make sure your internal DNS points this hostname to the FreeBSD server.

---

## Force HTTPS Redirect

By default, both HTTP and HTTPS are enabled.

To force HTTP to redirect to HTTPS:

```sh
FORCE_HTTPS_REDIRECT=1 sh /root/install-nextcloud-freebsd15.sh
```

With a custom hostname:

```sh
SERVER_NAME=cloud.internal.example.local FORCE_HTTPS_REDIRECT=1 sh /root/install-nextcloud-freebsd15.sh
```

---

## Disable Self-Signed SSL

Self-signed SSL is enabled by default.

To disable SSL and only configure HTTP:

```sh
ENABLE_SELF_SIGNED_SSL=0 sh /root/install-nextcloud-freebsd15.sh
```

---

## Force Reinstall

If you need to wipe and reinstall Nextcloud:

```sh
FORCE_REINSTALL=1 sh /root/install-nextcloud-freebsd15.sh
```

With a custom hostname:

```sh
SERVER_NAME=cloud.internal.example.local FORCE_REINSTALL=1 sh /root/install-nextcloud-freebsd15.sh
```

Warning: `FORCE_REINSTALL=1` removes the existing Nextcloud web root and data directory configured by the script.

---

## Environment Variables

The script can be customised with environment variables.

| Variable | Default | Description |
|---|---:|---|
| `SERVER_NAME` | `nextcloud.internal` | Internal hostname for the Nextcloud site |
| `SERVER_IP` | Auto-detected | Server IP address used for trusted domains and certificate SAN |
| `TIMEZONE` | `Pacific/Auckland` | PHP timezone |
| `NEXTCLOUD_ADMIN_USER` | `admin` | Nextcloud admin username |
| `NEXTCLOUD_ADMIN_PASS` | Generated | Nextcloud admin password |
| `NEXTCLOUD_ROOT` | `/usr/local/www/nextcloud` | Nextcloud web root |
| `NEXTCLOUD_DATA` | `/var/db/nextcloud/data` | Nextcloud data directory |
| `NEXTCLOUD_ARCHIVE_URL` | Nextcloud latest tarball | Nextcloud download URL |
| `NEXTCLOUD_DB_NAME` | `nextcloud` | MariaDB database name |
| `NEXTCLOUD_DB_USER` | `nextcloud` | MariaDB database user |
| `NEXTCLOUD_DB_PASS` | Generated | MariaDB database password |
| `NEXTCLOUD_DB_HOST` | `127.0.0.1` | MariaDB host |
| `PHP_MEMORY_LIMIT` | `512M` | PHP memory limit |
| `PHP_UPLOAD_LIMIT` | `10240M` | PHP upload and post size limit |
| `ENABLE_SELF_SIGNED_SSL` | `1` | Enable self-signed HTTPS vhost |
| `FORCE_HTTPS_REDIRECT` | `0` | Redirect HTTP to HTTPS |
| `SELF_SIGNED_CERT_DAYS` | `3650` | Self-signed certificate validity |
| `SSL_CERT_DIR` | `/usr/local/etc/ssl/nextcloud` | SSL file directory |
| `SSL_CERT_FILE` | Auto-set | SSL certificate path |
| `SSL_KEY_FILE` | Auto-set | SSL private key path |
| `FORCE_REINSTALL` | `0` | Remove and reinstall existing Nextcloud paths |

---

## Example Install Commands

### Basic install

```sh
sh /root/install-nextcloud-freebsd15.sh
```

### Install with custom hostname

```sh
SERVER_NAME=cloud.internal.example.local sh /root/install-nextcloud-freebsd15.sh
```

### Install with HTTPS redirect

```sh
SERVER_NAME=cloud.internal.example.local FORCE_HTTPS_REDIRECT=1 sh /root/install-nextcloud-freebsd15.sh
```

### Install without SSL

```sh
ENABLE_SELF_SIGNED_SSL=0 sh /root/install-nextcloud-freebsd15.sh
```

### Force reinstall

```sh
FORCE_REINSTALL=1 sh /root/install-nextcloud-freebsd15.sh
```

### Use a custom data directory

```sh
NEXTCLOUD_DATA=/mnt/zdata/nextcloud-data sh /root/install-nextcloud-freebsd15.sh
```

---

## Generated Credentials

The installer creates a credentials file in the same directory as the script.

Example:

```text
nextcloud_credentials_20260624_2145.txt
```

It contains:

- Nextcloud URL
- Nextcloud admin username
- Nextcloud admin password
- Database name
- Database username
- Database password
- Web root
- Data directory
- SSL certificate location
- SSL private key location
- Reverse proxy notes

Example command:

```sh
cat /root/nextcloud_credentials_*.txt
```

---

## Install Logs

The installer creates a timestamped install log in the same directory as the script.

Example:

```text
install_20260624_2145.log
```

To view the latest log:

```sh
LATEST_LOG="$(ls -t /root/install_*.log | head -n 1)"
less "$LATEST_LOG"
```

To watch a running install:

```sh
LATEST_LOG="$(ls -t /root/install_*.log | head -n 1)"
tail -f "$LATEST_LOG"
```

---

## Services

The installer enables and starts the following FreeBSD services:

```sh
apache24
php_fpm
mysql-server
redis
```

Check service status:

```sh
service apache24 status
service php_fpm status
service mysql-server status
service redis status
```

Restart services:

```sh
service php_fpm restart
service apache24 restart
service mysql-server restart
service redis restart
```

---

## FreeBSD Service Name Notes

FreeBSD uses the service name:

```sh
php_fpm
```

Do not use:

```sh
php-fpm
```

If you see this error:

```text
php-fpm does not exist in /etc/rc.d or the local startup directories
```

then the script or command is using the wrong service name.

Correct command:

```sh
service php_fpm restart
```

---

## SSL Notes

The installer generates a self-signed SSL certificate.

Default certificate path:

```text
/usr/local/etc/ssl/nextcloud/nextcloud-selfsigned.crt
```

Default private key path:

```text
/usr/local/etc/ssl/nextcloud/nextcloud-selfsigned.key
```

Browsers will warn about the certificate unless it is imported into the client trust store.

For internal production use, consider replacing the self-signed certificate with a certificate from an internal CA.

---

## Reverse Proxy Notes

This installer can be used directly over HTTP/HTTPS or behind a reverse proxy.

If placing Nextcloud behind an HTTPS reverse proxy later, run:

```sh
su -m www -c "/bin/sh -c 'cd /usr/local/www/nextcloud && php occ config:system:set overwriteprotocol --value=https'"
```

Set the CLI URL:

```sh
su -m www -c "/bin/sh -c 'cd /usr/local/www/nextcloud && php occ config:system:set overwrite.cli.url --value=https://cloud.internal.example.local'"
```

Add your reverse proxy as a trusted proxy.

Example where reverse proxy IP is `10.0.0.5`:

```sh
su -m www -c "/bin/sh -c 'cd /usr/local/www/nextcloud && php occ config:system:set trusted_proxies 0 --value=10.0.0.5'"
```

If using a proxy that forwards client IP headers, review your proxy configuration and Nextcloud trusted proxy settings carefully.

---

## Nextcloud Cron

The script configures Nextcloud to use cron mode and adds the following line to `/etc/crontab`:

```cron
*/5 * * * * www /usr/local/bin/php -f /usr/local/www/nextcloud/cron.php
```

Verify the cron entry:

```sh
grep nextcloud /etc/crontab
```

---

## Post-Install Checks

After the install completes, run:

```sh
service apache24 status
service php_fpm status
service mysql-server status
service redis status
```

Check Apache config:

```sh
apachectl configtest
```

Check Nextcloud status:

```sh
su -m www -c "/bin/sh -c 'cd /usr/local/www/nextcloud && php occ status'"
```

Check trusted domains:

```sh
su -m www -c "/bin/sh -c 'cd /usr/local/www/nextcloud && php occ config:system:get trusted_domains'"
```

---

## Accessing Nextcloud

After installation, access Nextcloud using the generated hostname or IP address.

Examples:

```text
http://nextcloud.internal/
https://nextcloud.internal/
http://10.0.0.10/
https://10.0.0.10/
```

If using HTTPS with the generated self-signed certificate, your browser will display a warning until the certificate is trusted.

---

## Troubleshooting

### The terminal only shows a cursor and appears to wait

The script may be writing output to the log file.

Open another SSH session and run:

```sh
LATEST_LOG="$(ls -t /root/install_*.log | head -n 1)"
tail -f "$LATEST_LOG"
```

Check whether the installer is still running:

```sh
ps aux | egrep 'install-nextcloud|pkg|fetch|tar|php|mysql|apache|redis' | grep -v grep
```

### PHP-FPM service error

Error:

```text
php-fpm does not exist in /etc/rc.d or the local startup directories
```

Fix:

```sh
service php_fpm restart
```

FreeBSD uses `php_fpm`, not `php-fpm`.

### Apache config fails

Run:

```sh
apachectl configtest
```

Check the Nextcloud Apache config:

```sh
cat /usr/local/etc/apache24/Includes/nextcloud.conf
```

Check Apache logs:

```sh
tail -f /var/log/nextcloud-http-error.log
tail -f /var/log/nextcloud-ssl-error.log
```

### Nextcloud says domain is untrusted

Add the domain:

```sh
su -m www -c "/bin/sh -c 'cd /usr/local/www/nextcloud && php occ config:system:set trusted_domains 2 --value=cloud.internal.example.local'"
```

### Browser warns about SSL certificate

This is expected with a self-signed certificate.

Options:

- Continue through the browser warning
- Import the certificate into your trusted root store
- Replace the certificate with one from an internal CA
- Put Nextcloud behind a reverse proxy with a trusted certificate

### Redis or APCu warnings

Check PHP modules:

```sh
php -m | egrep 'apcu|redis|opcache'
```

Restart services:

```sh
service redis restart
service php_fpm restart
service apache24 restart
```

### Need to rerun after failed partial install

If the initial install failed before `config.php` was created, rerun:

```sh
sh /root/install-nextcloud-freebsd15.sh
```

If you want a clean reinstall:

```sh
FORCE_REINSTALL=1 sh /root/install-nextcloud-freebsd15.sh
```

---

## Updating Nextcloud

Use the built-in Nextcloud updater or `occ` commands.

Before updating, take backups of:

```text
/usr/local/www/nextcloud
/var/db/nextcloud/data
MariaDB nextcloud database
/usr/local/etc/apache24/Includes/nextcloud.conf
/usr/local/etc/php.ini
/usr/local/etc/php-fpm.d/nextcloud.conf
```

Example database backup:

```sh
mysqldump -uroot nextcloud > /root/nextcloud_db_backup.sql
```

---

## Backup Notes

Important paths to back up:

```text
/usr/local/www/nextcloud
/var/db/nextcloud/data
/usr/local/etc/apache24/Includes/nextcloud.conf
/usr/local/etc/php.ini
/usr/local/etc/php-fpm.d/nextcloud.conf
/usr/local/etc/mysql/conf.d/nextcloud.cnf
/usr/local/etc/ssl/nextcloud
```

Also back up the MariaDB database:

```sh
mysqldump -uroot nextcloud > /root/nextcloud_db_backup.sql
```

---

## Uninstall Notes

This script does not include an uninstall mode.

Manual removal example:

```sh
service apache24 stop
service php_fpm stop
service redis stop
service mysql-server stop

rm -rf /usr/local/www/nextcloud
rm -rf /var/db/nextcloud/data
rm -rf /usr/local/etc/ssl/nextcloud
rm -f /usr/local/etc/apache24/Includes/nextcloud.conf
rm -f /usr/local/etc/php-fpm.d/nextcloud.conf
rm -f /usr/local/etc/mysql/conf.d/nextcloud.cnf
```

Remove the database:

```sh
mysql -uroot
```

Then inside MariaDB:

```sql
DROP DATABASE IF EXISTS nextcloud;
DROP USER IF EXISTS 'nextcloud'@'localhost';
DROP USER IF EXISTS 'nextcloud'@'127.0.0.1';
FLUSH PRIVILEGES;
EXIT;
```

Remove the cron entry from:

```text
/etc/crontab
```

---

## GitHub Publishing Safety Checklist

Before pushing to GitHub:

- [ ] Commit only the installer script and documentation
- [ ] Do not commit `install_*.log`
- [ ] Do not commit `nextcloud_credentials_*.txt`
- [ ] Do not commit `.key` files
- [ ] Do not commit `.crt` files unless intentionally publishing a test/demo cert
- [ ] Do not commit internal client names
- [ ] Do not commit internal IP addresses
- [ ] Do not commit real hostnames if the repository is public
- [ ] Add the recommended `.gitignore`

---

## Suggested Repository Layout

```text
nextcloud-freebsd15-installer/
├── install-nextcloud-freebsd15.sh
├── README.md
├── .gitignore
└── LICENSE
```

---

## License

Choose a license that matches how you want others to use the project.

Common options:

- MIT License
- BSD 2-Clause License
- BSD 3-Clause License
- Apache License 2.0

For a FreeBSD-focused project, BSD 2-Clause or BSD 3-Clause is a good fit.

---

## Disclaimer

This script is provided as-is.

Review it before running in production.

Always test in a lab first.

Always take backups before reinstalling, upgrading, or modifying an existing Nextcloud deployment.

