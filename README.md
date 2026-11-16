# linux-server-project

One command turns a fresh Rocky Linux 9 server into a **self-reporting web server**.

## What it does

- Builds its **own private dnf repository** on the machine. Every package comes from it (GPG check on, no other repo enabled).
- Runs Apache as its own user (`webreport`) with **HTTPS** (self-signed certificate). HTTP redirects to HTTPS.
- Keeps SELinux on **Enforcing** and firewalld **on**.
- Makes two disks (`/mnt/metrics` and `/backup`) and mounts them again after every reboot.
- **Every minute** it writes a status page and a JSON report.
- **Every 10 minutes** it packs the reports into a compressed archive with a SHA-256 checksum. Only the newest 48 archives are kept.
- The cron jobs run as `webreport`, not as root. The cron log is rotated every day.
- A self-test checks everything and prints PASS or FAIL.

## Requirements

- Made for Rocky Linux 9. Tested on AlmaLinux 10.2.
- A user with `sudo`.
- Internet during the first run only. After that the server installs everything from its own repo.

## Run it

```
sudo dnf install -y git
git clone https://github.com/Voltaik292/linux-server-project.git
cd linux-server-project
sudo ./run.sh
```

The first run takes a few minutes. Running it again is safe: it does not duplicate or break anything.

## What you get

- `https://<server-ip>/` is the live status page. The browser warns about the certificate because it is self-signed.
- `https://<server-ip>/repo/` is the private repository.
- The last line of the run is `Site ready: https://<server-ip>/`. You can run the self-test again at any time with `sudo ./verify.sh`.

## Files

| File | What it does |
|---|---|
| `run.sh` | runs steps 1 to 6 in order, writes everything to the install log, stops with a message if a step fails |
| `config.sh` | all settings and the shared functions |
| `setup_private_repo.sh` | step 1: builds the private dnf repository |
| `install_apache.sh` | step 2: installs Apache and runs it as `webreport` |
| `configure_https.sh` | step 3: certificate, HTTPS, redirect, `/repo/`, firewall |
| `mount_disks.sh` | step 4: creates, formats and mounts the two disks |
| `setup_crons.sh` | step 5: installs the jobs, the cron file and log rotation |
| `generate_report.sh` | run by cron every minute: status page and JSON report |
| `archive_reports.sh` | run by cron every 10 minutes: archive and checksum |
| `verify.sh` | step 6: the self-test |

## Where things are

| What | Where |
|---|---|
| Install log | `/var/log/linux-server-project/install.log` |
| Cron log | `/var/log/linux-server-project/cron.log` |
| Cron jobs | `/etc/cron.d/linux-server-project` |
| Status page | `/var/www/html/index.html` |
| JSON reports | `/mnt/metrics` |
| Archives and checksums | `/backup` |
| Private repository | `/var/www/repo` |

## Flowcharts

A flowchart of every script and one of the whole project: [docs/flowcharts.md](docs/flowcharts.md)
