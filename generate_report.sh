#!/usr/bin/env bash
set -euo pipefail


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

# info
host="$(hostname)"
ip_addr="$(hostname -I | awk '{print $1}')"
os_name="$(grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2 | tr -d '"')"
kernel="$(uname -r)"
up_text="$(uptime -p)"
load_avg="$(cut -d' ' -f1-3 /proc/loadavg)"


# CPU, mem, disks data
cpu_pct="$(vmstat 1 2 | tail -n 1 | awk '{print 100-$15}')"
mem_pct="$(free | awk '/^Mem:/ {print int($3/$2*100)}')"
disk_root="$(df --output=pcent / | tail -n 1 | tr -dc '0-9')"
disk_metrics="$(df --output=pcent "${METRICS_MOUNT}" | tail -n 1 | tr -dc '0-9')"
disk_backup="$(df --output=pcent "${BACKUP_MOUNT}" | tail -n 1 | tr -dc '0-9')"


# users, ports, processes, services, archives
users_count="$(who | wc -l)"
ports="$(ss -tln | awk 'NR>1 {print $4}' | sed 's/.*://' | sort -nu | xargs)"
top5="$(ps -eo comm,%mem --sort=-%mem --no-headers | sed -n 1,5p)"

svc_httpd="$(systemctl is-active httpd || true)"
svc_crond="$(systemctl is-active crond || true)"
svc_firewalld="$(systemctl is-active firewalld || true)"

archive_count="$(find "${BACKUP_MOUNT}" -name "${ARCHIVE_PREFIX}*.tar.gz" | wc -l)"
archive_newest="$(find "${BACKUP_MOUNT}" -name "${ARCHIVE_PREFIX}*.tar.gz" -printf '%f\n' | sort | tail -n 1)"


# writing json file
now="$(date '+%Y-%m-%d %H:%M:%S')"
json_file="${METRICS_MOUNT}/${REPORT_PREFIX}$(date +%s).json"

jq -n \
    --arg time "$now" \
    --arg hostname "$host" \
    --arg ip "$ip_addr" \
    --arg os "$os_name" \
    --arg kernel "$kernel" \
    --arg uptime "$up_text" \
    --arg load "$load_avg" \
    --arg cpu_percent "$cpu_pct" \
    --arg memory_percent "$mem_pct" \
    --arg disk_root "$disk_root" \
    --arg disk_metrics "$disk_metrics" \
    --arg disk_backup "$disk_backup" \
    --arg users "$users_count" \
    --arg ports "$ports" \
    --arg top_processes "$top5" \
    --arg httpd "$svc_httpd" \
    --arg crond "$svc_crond" \
    --arg firewalld "$svc_firewalld" \
    --arg archive_count "$archive_count" \
    --arg archive_newest "$archive_newest" \
    '$ARGS.named' > "${json_file}.tmp"

mv "${json_file}.tmp" "${json_file}"


# HTML Page (Claude generated)
tmp="${WEB_INDEX}.tmp"

cat > "${tmp}" <<HTML
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta http-equiv="refresh" content="60">
<title>Server status: ${host}</title>
<style>body { font-family: sans-serif; margin: 2em; }</style>
</head>
<body>
<h1>Server status: ${host}</h1>
<p>Made at ${now}. Refreshes every 60 seconds. <a href="/repo/">Package repository</a></p>

<h2>System</h2>
<ul>
<li>IP address: ${ip_addr}</li>
<li>OS: ${os_name}</li>
<li>Kernel: ${kernel}</li>
<li>Uptime: ${up_text}</li>
<li>Load average: ${load_avg}</li>
<li>Logged-in users: ${users_count}</li>
</ul>

<h2>Usage</h2>
<ul>
<li>CPU: ${cpu_pct}%</li>
<li>Memory: ${mem_pct}%</li>
<li>Disk /: ${disk_root}%</li>
<li>Disk ${METRICS_MOUNT}: ${disk_metrics}%</li>
<li>Disk ${BACKUP_MOUNT}: ${disk_backup}%</li>
</ul>

<h2>Listening TCP ports</h2>
<p>${ports}</p>

<h2>Top 5 processes by memory</h2>
<pre>${top5}</pre>

<h2>Services</h2>
<ul>
<li>httpd: ${svc_httpd}</li>
<li>crond: ${svc_crond}</li>
<li>firewalld: ${svc_firewalld}</li>
</ul>

<h2>Archives</h2>
<ul>
<li>Number of archives: ${archive_count}</li>
<li>Newest archive: ${archive_newest}</li>
</ul>
</body>
</html>
HTML

mv "${tmp}" "${WEB_INDEX}"
