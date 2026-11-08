#!/usr/bin/env bash
set -euo pipefail


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

# Installing httpd:
need_root               # check for sudo as always.
log "Step 2: Apache"

log "Installing httpd"
dnf install -y httpd


# creating the user:
if id "${WEB_USER}" > /dev/null 2>&1; then
    log "User ${WEB_USER} already exits"
else
    log "Creating system user ${WEB_USER}"
    useradd --system --no-create-home --shell /usr/sbin/nologin "${WEB_USER}"
    # dedicated system user made for services,
    # no home folder for it,
    # nobody can open a terminal as this user.
fi

# now making apache run as webreport (The new system user)
# The 2 lines in /etc/httpds...... (the apaches config file) decide which user the worker processes run as
log "Setting apache to run as ${WEB_USER}"
sed -i "s/^User .*/User ${WEB_USER}/" "${HTTPD_CONF}"
sed -i "s/^Group .*/Group ${WEB_USER}/" "${HTTPD_CONF}"

# now we want to fix the on reboot reset,
# the web root should be owned by webreport, AND STAY OWNED BY IT ON REBOOT!!
# i will put a temporary page until the first report exists.

cat > "${TMPFILES_CONF}" << EOF
d ${WEB_ROOT} 0755 ${WEB_USER} ${WEB_USER} -
EOF
    # Expected the /etc/tmpfiles.d/${PROJECT_NAME}.conf to contain d /var/www/html 0755 webreport webreport -

systemd-tmpfiles --create "${TMPFILES_CONF}"

if [[ ! -f "${WEB_ROOT}/index.html" ]]; then
    log "Creating temporary index.html file only for now"
    echo "<h1>TMP HTML</h1>" > "${WEB_ROOT}/index.html"
fi

# 2 steps lock, first we want to change owner and group soo they are both webreport, even tho the file is made with sudo.
# then we want to change the file tag, which lets the httpd program interact with the file.
# webreport:webreport /var/www/html
chown -R ${WEB_USER}:${WEB_USER} ${WEB_ROOT}
restorecon -R ${WEB_ROOT}


log "Checking Apache config"
apachectl configtest

systemctl enable httpd
systemctl restart httpd
log "Apache is runnig as ${WEB_USER}"

