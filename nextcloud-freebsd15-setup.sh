#!/bin/sh
#
# install-nextcloud-freebsd15.sh
#
# FreeBSD 15.x Nextcloud internal installer
#
# FreeBSD-native only:
#   - /bin/sh
#   - pkg
#   - sysrc
#   - service
#   - FreeBSD rc service names
#
# Stack:
#   - Apache 2.4
#   - PHP-FPM
#   - MariaDB
#   - Redis
#   - Latest Nextcloud release
#
# Features:
#   - Fully automated
#   - No user prompts
#   - Generates Nextcloud admin password
#   - Generates database password
#   - Generates self-signed SSL certificate
#   - Enables HTTP and HTTPS
#   - Optional HTTP-to-HTTPS redirect
#   - Logs to install_YYYYMMDD_HHMM.log in script directory
#   - Writes credentials to nextcloud_credentials_YYYYMMDD_HHMM.txt
#
# Basic usage:
#   sh install-nextcloud-freebsd15.sh
#
# Custom hostname:
#   SERVER_NAME=cloud.internal.podcom.nz sh install-nextcloud-freebsd15.sh
#
# Force HTTP to HTTPS:
#   FORCE_HTTPS_REDIRECT=1 sh install-nextcloud-freebsd15.sh
#
# Force reinstall of an existing install:
#   FORCE_REINSTALL=1 sh install-nextcloud-freebsd15.sh
#

set -eu

###############################################################################
# Logging setup
###############################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
RUN_STAMP="$(date '+%Y%m%d_%H%M')"

LOG_FILE="${SCRIPT_DIR}/install_${RUN_STAMP}.log"
CREDENTIAL_FILE="${SCRIPT_DIR}/nextcloud_credentials_${RUN_STAMP}.txt"

touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

exec >> "$LOG_FILE" 2>&1

###############################################################################
# Config
###############################################################################

SERVER_NAME="${SERVER_NAME:-nextcloud.internal}"

SERVER_IP="${SERVER_IP:-$(ifconfig | awk '
    /inet / && $2 != "127.0.0.1" {
        print $2
        exit
    }
')}"

TIMEZONE="${TIMEZONE:-Pacific/Auckland}"

NEXTCLOUD_ADMIN_USER="${NEXTCLOUD_ADMIN_USER:-admin}"
NEXTCLOUD_ADMIN_PASS="${NEXTCLOUD_ADMIN_PASS:-$(openssl rand -hex 24)}"

NEXTCLOUD_ROOT="${NEXTCLOUD_ROOT:-/usr/local/www/nextcloud}"
NEXTCLOUD_DATA="${NEXTCLOUD_DATA:-/var/db/nextcloud/data}"
NEXTCLOUD_ARCHIVE_URL="${NEXTCLOUD_ARCHIVE_URL:-https://download.nextcloud.com/server/releases/latest.tar.bz2}"

NEXTCLOUD_DB_NAME="${NEXTCLOUD_DB_NAME:-nextcloud}"
NEXTCLOUD_DB_USER="${NEXTCLOUD_DB_USER:-nextcloud}"
NEXTCLOUD_DB_PASS="${NEXTCLOUD_DB_PASS:-$(openssl rand -hex 24)}"
NEXTCLOUD_DB_HOST="${NEXTCLOUD_DB_HOST:-127.0.0.1}"

PHP_MEMORY_LIMIT="${PHP_MEMORY_LIMIT:-512M}"
PHP_UPLOAD_LIMIT="${PHP_UPLOAD_LIMIT:-10240M}"

ENABLE_SELF_SIGNED_SSL="${ENABLE_SELF_SIGNED_SSL:-1}"
FORCE_HTTPS_REDIRECT="${FORCE_HTTPS_REDIRECT:-0}"
SELF_SIGNED_CERT_DAYS="${SELF_SIGNED_CERT_DAYS:-3650}"

SSL_CERT_DIR="${SSL_CERT_DIR:-/usr/local/etc/ssl/nextcloud}"
SSL_CERT_FILE="${SSL_CERT_FILE:-${SSL_CERT_DIR}/nextcloud-selfsigned.crt}"
SSL_KEY_FILE="${SSL_KEY_FILE:-${SSL_CERT_DIR}/nextcloud-selfsigned.key}"
SSL_OPENSSL_CNF="${SSL_OPENSSL_CNF:-${SSL_CERT_DIR}/nextcloud-openssl.cnf}"

FORCE_REINSTALL="${FORCE_REINSTALL:-0}"

HTTPD_CONF="/usr/local/etc/apache24/httpd.conf"
APACHE_NC_CONF="/usr/local/etc/apache24/Includes/nextcloud.conf"
PHP_INI="/usr/local/etc/php.ini"
PHP_FPM_POOL="/usr/local/etc/php-fpm.d/nextcloud.conf"
MARIADB_NC_CONF="/usr/local/etc/mysql/conf.d/nextcloud.cnf"

MYSQL_RESET_REQUIRED="0"

###############################################################################
# Helpers
###############################################################################

log() {
    printf '%s\n' "[INFO] $*"
}

warn() {
    printf '%s\n' "[WARN] $*" >&2
}

die() {
    printf '%s\n' "[ERROR] $*" >&2
    printf '%s\n' "[ERROR] See log: ${LOG_FILE}" >&2
    exit 1
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        die "Run this script as root."
    fi
}

shell_quote() {
    printf "'"
    printf "%s" "$1" | sed "s/'/'\\\\''/g"
    printf "'"
}

sql_escape() {
    printf "%s" "$1" | sed "s/'/''/g"
}

valid_sql_name() {
    case "$1" in
        *[!A-Za-z0-9_]*|'')
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

pkg_available() {
    pkg rquery "%n" "$1" 2>/dev/null | grep -qx "$1"
}

add_pkg_if_available() {
    _pkg="$1"

    if pkg_available "$_pkg"; then
        PKGS="$PKGS $_pkg"
        return 0
    fi

    return 1
}

set_php_ini() {
    _key="$1"
    _value="$2"

    if grep -Eq "^[;[:space:]]*${_key}[[:space:]]*=" "$PHP_INI"; then
        sed -i '' -E "s|^[;[:space:]]*${_key}[[:space:]]*=.*|${_key} = ${_value}|" "$PHP_INI"
    else
        printf '%s = %s\n' "$_key" "$_value" >> "$PHP_INI"
    fi
}

ensure_loadmodule() {
    _module="$1"
    _path="$2"

    if grep -Eq "^[#[:space:]]*LoadModule[[:space:]]+${_module}[[:space:]]+" "$HTTPD_CONF"; then
        sed -i '' -E "s|^[#[:space:]]*LoadModule[[:space:]]+${_module}[[:space:]]+.*|LoadModule ${_module} ${_path}|" "$HTTPD_CONF"
    else
        printf '\nLoadModule %s %s\n' "$_module" "$_path" >> "$HTTPD_CONF"
    fi
}

comment_loadmodule() {
    _module="$1"

    if grep -Eq "^[[:space:]]*LoadModule[[:space:]]+${_module}[[:space:]]+" "$HTTPD_CONF"; then
        sed -i '' -E "s|^[[:space:]]*LoadModule[[:space:]]+${_module}[[:space:]]+|#LoadModule ${_module} |" "$HTTPD_CONF"
    fi
}

ensure_listen() {
    _port="$1"

    if ! grep -Eq "^[[:space:]]*Listen[[:space:]]+([^[:space:]]+:)?${_port}([[:space:]]|$)" "$HTTPD_CONF"; then
        printf '\nListen %s\n' "$_port" >> "$HTTPD_CONF"
    fi
}

run_as_www() {
    _cmd="$1"
    su -m www -c "/bin/sh -c $(shell_quote "$_cmd")"
}

occ_cmd() {
    _occ_args="$1"
    run_as_www "cd $(shell_quote "$NEXTCLOUD_ROOT") && /usr/local/bin/php occ ${_occ_args}"
}

select_php_version() {
    PHP_VER="${PHP_VER:-}"

    if [ -n "$PHP_VER" ]; then
        if ! pkg_available "php${PHP_VER}"; then
            die "PHP_VER=${PHP_VER} was requested, but php${PHP_VER} is not available."
        fi
        return
    fi

    for _ver in 85 84 83; do
        if pkg_available "php${_ver}"; then
            PHP_VER="$_ver"
            return
        fi
    done

    die "Could not find php85, php84, or php83 in the configured FreeBSD pkg repository."
}

select_mariadb_version() {
    MARIADB_FLAVOUR="${MARIADB_FLAVOUR:-}"

    if [ -n "$MARIADB_FLAVOUR" ]; then
        if ! pkg_available "${MARIADB_FLAVOUR}-server"; then
            die "MARIADB_FLAVOUR=${MARIADB_FLAVOUR} was requested, but ${MARIADB_FLAVOUR}-server is not available."
        fi
        return
    fi

    for _mdb in mariadb118 mariadb114 mariadb1011 mariadb106; do
        if pkg_available "${_mdb}-server"; then
            MARIADB_FLAVOUR="$_mdb"
            return
        fi
    done

    die "Could not find a supported MariaDB server package in pkg."
}

write_credentials_file() {
    HTTPS_URL="disabled"

    if [ "$ENABLE_SELF_SIGNED_SSL" = "1" ]; then
        HTTPS_URL="https://${SERVER_NAME}/"
    fi

    cat > "$CREDENTIAL_FILE" <<EOF
Nextcloud FreeBSD 15 Install Credentials
Generated: ${RUN_STAMP}

URLs:
  HTTP URL:  http://${SERVER_NAME}/
  HTTPS URL: ${HTTPS_URL}

IP URLs:
  HTTP IP URL:  http://${SERVER_IP}/
  HTTPS IP URL: https://${SERVER_IP}/

Nextcloud Admin:
  Username: ${NEXTCLOUD_ADMIN_USER}
  Password: ${NEXTCLOUD_ADMIN_PASS}

Database:
  Database Name: ${NEXTCLOUD_DB_NAME}
  Database User: ${NEXTCLOUD_DB_USER}
  Database Password: ${NEXTCLOUD_DB_PASS}
  Database Host: ${NEXTCLOUD_DB_HOST}

Paths:
  Web Root: ${NEXTCLOUD_ROOT}
  Data Directory: ${NEXTCLOUD_DATA}
  Install Log: ${LOG_FILE}

SSL:
  Certificate: ${SSL_CERT_FILE}
  Private Key: ${SSL_KEY_FILE}

Reverse proxy notes:
  This install can run direct HTTP or direct HTTPS using a self-signed certificate.

  After placing Nextcloud behind an HTTPS reverse proxy, run:

  su -m www -c "/bin/sh -c 'cd ${NEXTCLOUD_ROOT} && php occ config:system:set overwriteprotocol --value=https'"

  If your reverse proxy IP is 10.0.0.5, run:

  su -m www -c "/bin/sh -c 'cd ${NEXTCLOUD_ROOT} && php occ config:system:set trusted_proxies 0 --value=10.0.0.5'"
EOF

    chmod 600 "$CREDENTIAL_FILE"
}

generate_self_signed_certificate() {
    if [ "$ENABLE_SELF_SIGNED_SSL" != "1" ]; then
        log "Self-signed SSL disabled."
        return
    fi

    log "Generating self-signed SSL certificate."

    mkdir -p "$SSL_CERT_DIR"
    chmod 700 "$SSL_CERT_DIR"

    {
        printf '%s\n' "[req]"
        printf '%s\n' "default_bits = 4096"
        printf '%s\n' "prompt = no"
        printf '%s\n' "default_md = sha256"
        printf '%s\n' "distinguished_name = dn"
        printf '%s\n' "x509_extensions = v3_req"
        printf '%s\n' ""
        printf '%s\n' "[dn]"
        printf '%s\n' "C = NZ"
        printf '%s\n' "ST = Auckland"
        printf '%s\n' "L = Auckland"
        printf '%s\n' "O = Internal"
        printf '%s\n' "OU = IT"
        printf '%s\n' "CN = ${SERVER_NAME}"
        printf '%s\n' ""
        printf '%s\n' "[v3_req]"
        printf '%s\n' "basicConstraints = critical, CA:FALSE"
        printf '%s\n' "keyUsage = critical, digitalSignature, keyEncipherment"
        printf '%s\n' "extendedKeyUsage = serverAuth"
        printf '%s\n' "subjectAltName = @alt_names"
        printf '%s\n' ""
        printf '%s\n' "[alt_names]"
        printf '%s\n' "DNS.1 = ${SERVER_NAME}"
        printf '%s\n' "DNS.2 = localhost"
        printf '%s\n' "IP.1 = 127.0.0.1"

        if [ -n "$SERVER_IP" ]; then
            printf '%s\n' "IP.2 = ${SERVER_IP}"
        fi
    } > "$SSL_OPENSSL_CNF"

    openssl req \
        -x509 \
        -nodes \
        -days "$SELF_SIGNED_CERT_DAYS" \
        -newkey rsa:4096 \
        -keyout "$SSL_KEY_FILE" \
        -out "$SSL_CERT_FILE" \
        -config "$SSL_OPENSSL_CNF" \
        -extensions v3_req

    chmod 600 "$SSL_KEY_FILE"
    chmod 644 "$SSL_CERT_FILE"

    log "Self-signed SSL certificate created."
    log "Certificate: ${SSL_CERT_FILE}"
    log "Private key: ${SSL_KEY_FILE}"
}

prepare_install_paths() {
    if [ -d "$NEXTCLOUD_ROOT" ]; then
        if [ -f "${NEXTCLOUD_ROOT}/config/config.php" ] && [ "$FORCE_REINSTALL" != "1" ]; then
            die "${NEXTCLOUD_ROOT} already contains config.php. Refusing to overwrite an existing install. Use FORCE_REINSTALL=1 if this is intentional."
        fi

        if [ "$FORCE_REINSTALL" = "1" ]; then
            warn "FORCE_REINSTALL=1 set. Removing existing Nextcloud web root and data directory."
            rm -rf "$NEXTCLOUD_ROOT"
            rm -rf "$NEXTCLOUD_DATA"
            MYSQL_RESET_REQUIRED="1"
            return
        fi

        warn "Existing ${NEXTCLOUD_ROOT} found but no config.php exists."
        warn "Treating this as an incomplete failed install and removing it."
        rm -rf "$NEXTCLOUD_ROOT"
        MYSQL_RESET_REQUIRED="1"
    fi
}

###############################################################################
# Start
###############################################################################

require_root

log "============================================================"
log "Starting FreeBSD 15 Nextcloud internal install"
log "============================================================"
log "Script directory: ${SCRIPT_DIR}"
log "Log file: ${LOG_FILE}"
log "Credentials file: ${CREDENTIAL_FILE}"

FREEBSD_VERSION_DETECTED="$(freebsd-version -u 2>/dev/null || true)"
FREEBSD_MAJOR="$(printf '%s' "$FREEBSD_VERSION_DETECTED" | cut -d. -f1)"

if [ "$FREEBSD_MAJOR" != "15" ]; then
    warn "This script was written for FreeBSD 15.x."
    warn "Detected version: ${FREEBSD_VERSION_DETECTED}"
fi

if ! valid_sql_name "$NEXTCLOUD_DB_NAME"; then
    die "NEXTCLOUD_DB_NAME must only contain letters, numbers, and underscores."
fi

if ! valid_sql_name "$NEXTCLOUD_DB_USER"; then
    die "NEXTCLOUD_DB_USER must only contain letters, numbers, and underscores."
fi

write_credentials_file
prepare_install_paths

log "Generated credentials have been written to:"
log "${CREDENTIAL_FILE}"

###############################################################################
# Package bootstrap and install
###############################################################################

log "Bootstrapping pkg if required."
env ASSUME_ALWAYS_YES=yes pkg bootstrap -f || true

log "Updating FreeBSD package catalogue."
pkg update -f

select_php_version
select_mariadb_version

log "Selected PHP branch: php${PHP_VER}"
log "Selected MariaDB branch: ${MARIADB_FLAVOUR}"

PKGS="apache24 ${MARIADB_FLAVOUR}-server ${MARIADB_FLAVOUR}-client redis ca_root_nss curl unzip bzip2 php${PHP_VER}"

for _mod in \
    pdo_mysql ctype curl dom filter gd mbstring posix session simplexml \
    xml xmlreader xmlwriter zip zlib bz2 intl bcmath gmp exif pcntl \
    phar opcache fileinfo sodium sysvsem iconv
do
    add_pkg_if_available "php${PHP_VER}-${_mod}" || true
done

HAVE_APCU="no"
if add_pkg_if_available "php${PHP_VER}-pecl-APCu"; then
    HAVE_APCU="yes"
elif add_pkg_if_available "php${PHP_VER}-pecl-apcu"; then
    HAVE_APCU="yes"
fi

HAVE_REDIS_PHP="no"
if add_pkg_if_available "php${PHP_VER}-pecl-redis"; then
    HAVE_REDIS_PHP="yes"
fi

HAVE_IMAGICK="no"
if add_pkg_if_available "php${PHP_VER}-pecl-imagick"; then
    HAVE_IMAGICK="yes"
fi

log "Installing packages."
pkg install -y $PKGS

###############################################################################
# PHP configuration
###############################################################################

log "Configuring PHP."

if [ ! -f "$PHP_INI" ]; then
    cp /usr/local/etc/php.ini-production "$PHP_INI"
fi

set_php_ini "date.timezone" "$TIMEZONE"
set_php_ini "memory_limit" "$PHP_MEMORY_LIMIT"
set_php_ini "upload_max_filesize" "$PHP_UPLOAD_LIMIT"
set_php_ini "post_max_size" "$PHP_UPLOAD_LIMIT"
set_php_ini "max_execution_time" "3600"
set_php_ini "max_input_time" "3600"
set_php_ini "output_buffering" "0"

set_php_ini "opcache.enable" "1"
set_php_ini "opcache.enable_cli" "1"
set_php_ini "opcache.memory_consumption" "256"
set_php_ini "opcache.interned_strings_buffer" "64"
set_php_ini "opcache.max_accelerated_files" "10000"
set_php_ini "opcache.revalidate_freq" "60"
set_php_ini "opcache.save_comments" "1"
set_php_ini "opcache.jit" "0"

if [ "$HAVE_APCU" = "yes" ]; then
    set_php_ini "apc.enable_cli" "1"
fi

mkdir -p /usr/local/etc/php-fpm.d

cat > "$PHP_FPM_POOL" <<EOF
[nextcloud]
user = www
group = www

listen = /tmp/php-fpm-nextcloud.sock
listen.owner = www
listen.group = www
listen.mode = 0660

pm = dynamic
pm.max_children = 32
pm.start_servers = 4
pm.min_spare_servers = 2
pm.max_spare_servers = 8
pm.max_requests = 500

env[HOSTNAME] = \$HOSTNAME
env[PATH] = /sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
env[TMP] = /tmp
env[TMPDIR] = /tmp
env[TEMP] = /tmp

php_admin_value[memory_limit] = ${PHP_MEMORY_LIMIT}
php_admin_value[upload_max_filesize] = ${PHP_UPLOAD_LIMIT}
php_admin_value[post_max_size] = ${PHP_UPLOAD_LIMIT}
php_admin_value[max_execution_time] = 3600
php_admin_value[max_input_time] = 3600
EOF

###############################################################################
# MariaDB configuration
###############################################################################

log "Configuring MariaDB."

mkdir -p /usr/local/etc/mysql/conf.d

cat > "$MARIADB_NC_CONF" <<EOF
[mysqld]
transaction-isolation = READ-COMMITTED
binlog_format = ROW
innodb_file_per_table = 1
character-set-server = utf8mb4
collation-server = utf8mb4_general_ci
EOF

sysrc mysql_enable=YES >/dev/null

service mysql-server restart >/dev/null 2>&1 || service mysql-server start

MYSQL_BIN="$(command -v mariadb || command -v mysql || true)"

if [ -z "$MYSQL_BIN" ]; then
    die "Could not find mariadb/mysql client binary after install."
fi

DB_PASS_SQL="$(sql_escape "$NEXTCLOUD_DB_PASS")"

log "Creating Nextcloud database and database user."

if [ "$FORCE_REINSTALL" = "1" ] || [ "$MYSQL_RESET_REQUIRED" = "1" ]; then
    log "Resetting Nextcloud database and database users for clean install."

    "$MYSQL_BIN" -uroot <<SQL
DROP DATABASE IF EXISTS \`${NEXTCLOUD_DB_NAME}\`;
DROP USER IF EXISTS '${NEXTCLOUD_DB_USER}'@'localhost';
DROP USER IF EXISTS '${NEXTCLOUD_DB_USER}'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL
fi

"$MYSQL_BIN" -uroot <<SQL
CREATE DATABASE IF NOT EXISTS \`${NEXTCLOUD_DB_NAME}\`
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_general_ci;

CREATE USER IF NOT EXISTS '${NEXTCLOUD_DB_USER}'@'localhost'
  IDENTIFIED BY '${DB_PASS_SQL}';

CREATE USER IF NOT EXISTS '${NEXTCLOUD_DB_USER}'@'127.0.0.1'
  IDENTIFIED BY '${DB_PASS_SQL}';

ALTER USER '${NEXTCLOUD_DB_USER}'@'localhost'
  IDENTIFIED BY '${DB_PASS_SQL}';

ALTER USER '${NEXTCLOUD_DB_USER}'@'127.0.0.1'
  IDENTIFIED BY '${DB_PASS_SQL}';

GRANT ALL PRIVILEGES ON \`${NEXTCLOUD_DB_NAME}\`.* TO '${NEXTCLOUD_DB_USER}'@'localhost';
GRANT ALL PRIVILEGES ON \`${NEXTCLOUD_DB_NAME}\`.* TO '${NEXTCLOUD_DB_USER}'@'127.0.0.1';

FLUSH PRIVILEGES;
SQL

###############################################################################
# SSL certificate
###############################################################################

generate_self_signed_certificate

###############################################################################
# Apache configuration
###############################################################################

log "Configuring Apache."

comment_loadmodule "mpm_prefork_module"
comment_loadmodule "mpm_worker_module"
ensure_loadmodule "mpm_event_module" "libexec/apache24/mod_mpm_event.so"

ensure_loadmodule "rewrite_module" "libexec/apache24/mod_rewrite.so"
ensure_loadmodule "headers_module" "libexec/apache24/mod_headers.so"
ensure_loadmodule "env_module" "libexec/apache24/mod_env.so"
ensure_loadmodule "dir_module" "libexec/apache24/mod_dir.so"
ensure_loadmodule "mime_module" "libexec/apache24/mod_mime.so"
ensure_loadmodule "proxy_module" "libexec/apache24/mod_proxy.so"
ensure_loadmodule "proxy_fcgi_module" "libexec/apache24/mod_proxy_fcgi.so"
ensure_loadmodule "setenvif_module" "libexec/apache24/mod_setenvif.so"

if [ "$ENABLE_SELF_SIGNED_SSL" = "1" ]; then
    ensure_loadmodule "ssl_module" "libexec/apache24/mod_ssl.so"
    ensure_loadmodule "socache_shmcb_module" "libexec/apache24/mod_socache_shmcb.so"
    ensure_listen "443"
fi

if ! grep -Eq "^[[:space:]]*Include(Optional)?[[:space:]]+etc/apache24/Includes/[*][.]conf" "$HTTPD_CONF"; then
    printf '\nIncludeOptional etc/apache24/Includes/*.conf\n' >> "$HTTPD_CONF"
fi

if ! grep -Eq "^[[:space:]]*ServerName[[:space:]]+" "$HTTPD_CONF"; then
    printf '\nServerName %s\n' "$SERVER_NAME" >> "$HTTPD_CONF"
fi

mkdir -p /usr/local/etc/apache24/Includes

HTTP_REDIRECT_LINE=""

if [ "$ENABLE_SELF_SIGNED_SSL" = "1" ] && [ "$FORCE_HTTPS_REDIRECT" = "1" ]; then
    HTTP_REDIRECT_LINE="    Redirect permanent / https://${SERVER_NAME}/"
fi

if [ "$ENABLE_SELF_SIGNED_SSL" = "1" ]; then
    cat > "$APACHE_NC_CONF" <<EOF
<IfModule ssl_module>
    SSLSessionCache "shmcb:/var/run/ssl_scache(512000)"
    SSLSessionCacheTimeout 300
</IfModule>

<VirtualHost *:80>
    ServerName ${SERVER_NAME}
    DocumentRoot "${NEXTCLOUD_ROOT}"

    ErrorLog "/var/log/nextcloud-http-error.log"
    CustomLog "/var/log/nextcloud-http-access.log" combined

${HTTP_REDIRECT_LINE}

    DirectoryIndex index.php index.html

    <Directory "${NEXTCLOUD_ROOT}/">
        Require all granted
        AllowOverride All
        Options FollowSymLinks MultiViews

        <IfModule mod_dav.c>
            Dav off
        </IfModule>
    </Directory>

    <FilesMatch \\.php$>
        SetHandler "proxy:unix:/tmp/php-fpm-nextcloud.sock|fcgi://localhost/"
    </FilesMatch>

    <FilesMatch "remote\\.php$">
        SetEnvIf Authorization "(.*)" HTTP_AUTHORIZATION=\$1
    </FilesMatch>

    RewriteEngine On
    RewriteRule ^/\\.well-known/carddav /remote.php/dav/ [R=301,L]
    RewriteRule ^/\\.well-known/caldav /remote.php/dav/ [R=301,L]

    Header always set Referrer-Policy "no-referrer"
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
</VirtualHost>

<VirtualHost *:443>
    ServerName ${SERVER_NAME}
    DocumentRoot "${NEXTCLOUD_ROOT}"

    ErrorLog "/var/log/nextcloud-ssl-error.log"
    CustomLog "/var/log/nextcloud-ssl-access.log" combined

    SSLEngine on
    SSLCertificateFile "${SSL_CERT_FILE}"
    SSLCertificateKeyFile "${SSL_KEY_FILE}"

    SSLProtocol all -SSLv3 -TLSv1 -TLSv1.1
    SSLCipherSuite HIGH:!aNULL:!MD5

    DirectoryIndex index.php index.html

    <Directory "${NEXTCLOUD_ROOT}/">
        Require all granted
        AllowOverride All
        Options FollowSymLinks MultiViews

        <IfModule mod_dav.c>
            Dav off
        </IfModule>
    </Directory>

    <FilesMatch \\.php$>
        SetHandler "proxy:unix:/tmp/php-fpm-nextcloud.sock|fcgi://localhost/"
    </FilesMatch>

    <FilesMatch "remote\\.php$">
        SetEnvIf Authorization "(.*)" HTTP_AUTHORIZATION=\$1
    </FilesMatch>

    RewriteEngine On
    RewriteRule ^/\\.well-known/carddav /remote.php/dav/ [R=301,L]
    RewriteRule ^/\\.well-known/caldav /remote.php/dav/ [R=301,L]

    Header always set Referrer-Policy "no-referrer"
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
</VirtualHost>
EOF
else
    cat > "$APACHE_NC_CONF" <<EOF
<VirtualHost *:80>
    ServerName ${SERVER_NAME}
    DocumentRoot "${NEXTCLOUD_ROOT}"

    ErrorLog "/var/log/nextcloud-http-error.log"
    CustomLog "/var/log/nextcloud-http-access.log" combined

    DirectoryIndex index.php index.html

    <Directory "${NEXTCLOUD_ROOT}/">
        Require all granted
        AllowOverride All
        Options FollowSymLinks MultiViews

        <IfModule mod_dav.c>
            Dav off
        </IfModule>
    </Directory>

    <FilesMatch \\.php$>
        SetHandler "proxy:unix:/tmp/php-fpm-nextcloud.sock|fcgi://localhost/"
    </FilesMatch>

    <FilesMatch "remote\\.php$">
        SetEnvIf Authorization "(.*)" HTTP_AUTHORIZATION=\$1
    </FilesMatch>

    RewriteEngine On
    RewriteRule ^/\\.well-known/carddav /remote.php/dav/ [R=301,L]
    RewriteRule ^/\\.well-known/caldav /remote.php/dav/ [R=301,L]

    Header always set Referrer-Policy "no-referrer"
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
</VirtualHost>
EOF
fi

###############################################################################
# Download and install Nextcloud
###############################################################################

log "Downloading latest Nextcloud release."

WORKDIR="$(mktemp -d /tmp/nextcloud-install.XXXXXX)"

cleanup() {
    if [ -n "${WORKDIR:-}" ] && [ -d "$WORKDIR" ]; then
        rm -rf "$WORKDIR"
    fi
}

trap cleanup EXIT

fetch -o "$WORKDIR/nextcloud.tar.bz2" "$NEXTCLOUD_ARCHIVE_URL"

log "Extracting Nextcloud."
tar -xjf "$WORKDIR/nextcloud.tar.bz2" -C "$WORKDIR"

mv "$WORKDIR/nextcloud" "$NEXTCLOUD_ROOT"

mkdir -p "$NEXTCLOUD_DATA"
chown -R www:www "$NEXTCLOUD_ROOT" "$NEXTCLOUD_DATA"

###############################################################################
# Enable and start services
###############################################################################

log "Enabling and starting services."

sysrc apache24_enable=YES >/dev/null
sysrc php_fpm_enable=YES >/dev/null
sysrc redis_enable=YES >/dev/null

service redis restart >/dev/null 2>&1 || service redis start
service php_fpm restart >/dev/null 2>&1 || service php_fpm start

apachectl configtest
service apache24 restart >/dev/null 2>&1 || service apache24 start

###############################################################################
# Nextcloud automated install
###############################################################################

log "Running automated Nextcloud install."

INSTALL_CMD="maintenance:install"
INSTALL_CMD="${INSTALL_CMD} --database mysql"
INSTALL_CMD="${INSTALL_CMD} --database-host $(shell_quote "$NEXTCLOUD_DB_HOST")"
INSTALL_CMD="${INSTALL_CMD} --database-name $(shell_quote "$NEXTCLOUD_DB_NAME")"
INSTALL_CMD="${INSTALL_CMD} --database-user $(shell_quote "$NEXTCLOUD_DB_USER")"
INSTALL_CMD="${INSTALL_CMD} --database-pass $(shell_quote "$NEXTCLOUD_DB_PASS")"
INSTALL_CMD="${INSTALL_CMD} --admin-user $(shell_quote "$NEXTCLOUD_ADMIN_USER")"
INSTALL_CMD="${INSTALL_CMD} --admin-pass $(shell_quote "$NEXTCLOUD_ADMIN_PASS")"
INSTALL_CMD="${INSTALL_CMD} --data-dir $(shell_quote "$NEXTCLOUD_DATA")"

occ_cmd "$INSTALL_CMD"

log "Applying Nextcloud baseline configuration."

occ_cmd "config:system:set trusted_domains 0 --value=$(shell_quote "$SERVER_NAME")"

if [ -n "$SERVER_IP" ]; then
    occ_cmd "config:system:set trusted_domains 1 --value=$(shell_quote "$SERVER_IP")"
fi

if [ "$ENABLE_SELF_SIGNED_SSL" = "1" ]; then
    occ_cmd "config:system:set overwrite.cli.url --value=$(shell_quote "https://${SERVER_NAME}")"
    occ_cmd "config:system:set overwriteprotocol --value=https"
else
    occ_cmd "config:system:set overwrite.cli.url --value=$(shell_quote "http://${SERVER_NAME}")"
fi

occ_cmd "config:system:set default_phone_region --value=NZ"
occ_cmd "config:system:set maintenance_window_start --type=integer --value=2"
occ_cmd "config:system:set mysql.utf8mb4 --type=boolean --value=true"

if [ "$HAVE_APCU" = "yes" ]; then
    occ_cmd "config:system:set memcache.local --value=$(shell_quote '\OC\Memcache\APCu')"
fi

if [ "$HAVE_REDIS_PHP" = "yes" ]; then
    occ_cmd "config:system:set memcache.locking --value=$(shell_quote '\OC\Memcache\Redis')"
    occ_cmd "config:system:set redis host --value=127.0.0.1"
    occ_cmd "config:system:set redis port --type=integer --value=6379"
fi

occ_cmd "background:cron"
occ_cmd "maintenance:update:htaccess"

###############################################################################
# Cron
###############################################################################

CRON_LINE="*/5 * * * * www /usr/local/bin/php -f ${NEXTCLOUD_ROOT}/cron.php"

if ! grep -Fq "$CRON_LINE" /etc/crontab; then
    log "Adding Nextcloud cron job to /etc/crontab."
    printf '\n%s\n' "$CRON_LINE" >> /etc/crontab
fi

###############################################################################
# Final permissions and restart
###############################################################################

log "Applying final permissions."

chown -R www:www "$NEXTCLOUD_ROOT" "$NEXTCLOUD_DATA"

log "Restarting services."

service php_fpm restart
service apache24 restart

###############################################################################
# Final status
###############################################################################

log "Nextcloud status:"
occ_cmd "status" || true

log "============================================================"
log "Nextcloud install complete"
log "============================================================"
log "HTTP URL:         http://${SERVER_NAME}/"

if [ "$ENABLE_SELF_SIGNED_SSL" = "1" ]; then
    log "HTTPS URL:        https://${SERVER_NAME}/"
fi

if [ -n "$SERVER_IP" ]; then
    log "HTTP IP URL:      http://${SERVER_IP}/"

    if [ "$ENABLE_SELF_SIGNED_SSL" = "1" ]; then
        log "HTTPS IP URL:     https://${SERVER_IP}/"
    fi
fi

log "Admin username:   ${NEXTCLOUD_ADMIN_USER}"
log "Admin password:   ${NEXTCLOUD_ADMIN_PASS}"
log "Web root:         ${NEXTCLOUD_ROOT}"
log "Data directory:   ${NEXTCLOUD_DATA}"
log "Database name:    ${NEXTCLOUD_DB_NAME}"
log "Database user:    ${NEXTCLOUD_DB_USER}"
log "Database pass:    ${NEXTCLOUD_DB_PASS}"
log "PHP branch:       php${PHP_VER}"
log "MariaDB branch:   ${MARIADB_FLAVOUR}"
log "Log file:         ${LOG_FILE}"
log "Credentials file: ${CREDENTIAL_FILE}"

if [ "$ENABLE_SELF_SIGNED_SSL" = "1" ]; then
    log "SSL certificate:  ${SSL_CERT_FILE}"
    log "SSL private key:  ${SSL_KEY_FILE}"
    log ""
    log "Browser note:"
    log "Because this is self-signed, browsers will warn unless you trust/import the certificate."
fi

log "============================================================"
log "Reverse proxy note:"
log "After placing this behind HTTPS reverse proxy, run:"
log "su -m www -c \"/bin/sh -c 'cd ${NEXTCLOUD_ROOT} && php occ config:system:set overwriteprotocol --value=https'\""
log ""
log "If your reverse proxy IP is 10.0.0.5, also run:"
log "su -m www -c \"/bin/sh -c 'cd ${NEXTCLOUD_ROOT} && php occ config:system:set trusted_proxies 0 --value=10.0.0.5'\""
log "============================================================"

printf '%s\n' "============================================================"
printf '%s\n' "Nextcloud install complete"
printf '%s\n' "Log file: ${LOG_FILE}"
printf '%s\n' "Credentials file: ${CREDENTIAL_FILE}"
printf '%s\n' "HTTP URL: http://${SERVER_NAME}/"

if [ "$ENABLE_SELF_SIGNED_SSL" = "1" ]; then
    printf '%s\n' "HTTPS URL: https://${SERVER_NAME}/"
fi

if [ -n "$SERVER_IP" ]; then
    printf '%s\n' "HTTP IP URL: http://${SERVER_IP}/"

    if [ "$ENABLE_SELF_SIGNED_SSL" = "1" ]; then
        printf '%s\n' "HTTPS IP URL: https://${SERVER_IP}/"
    fi
fi

printf '%s\n' "Admin username: ${NEXTCLOUD_ADMIN_USER}"
printf '%s\n' "Admin password: ${NEXTCLOUD_ADMIN_PASS}"
printf '%s\n' "============================================================"
