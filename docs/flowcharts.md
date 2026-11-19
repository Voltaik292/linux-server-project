
# Flowcharts

One chart for each script, then one big chart for the whole project. They are drawn from the real scripts in this repo.

**How to read them**

- **Rounded box** = start or end
- **Diamond** = a question (the script checks first, then decides)
- **Red border** = the script stops with an error
- Every script is safe to run again: the diamonds are the reason.

Contents: [run.sh](#runsh) · [Step 1](#step-1-setup_private_reposh) · [Step 2](#step-2-install_apachesh) · [Step 3](#step-3-configure_httpssh) · [Step 4](#step-4-mount_diskssh) · [Step 5](#step-5-setup_cronssh) · [Step 5a](#step-5a-generate_reportsh) · [Step 5b](#step-5b-archive_reportssh) · [Step 6](#step-6-verifysh) · [The big picture](#the-big-picture)

---

## run.sh

Runs the six steps in order. Everything it prints goes to the screen **and** to `install.log`.

```mermaid
flowchart TD
    A(["sudo ./run.sh"]) --> B{"running as root?"}
    B -- no --> X1["Run this script as root"]:::stop
    B -- yes --> C["make the log folder"]
    C --> D["run steps 1 to 6 in order"]
    D --> E{"a step failed?"}
    E -- yes --> X2["Step N failed. See install.log"]:::stop
    E -- no --> F(["last line: Site ready"])
    classDef stop stroke:#d9534f,stroke-width:3px
```

---

## Step 1 setup_private_repo.sh

Builds the server's **own** dnf repository. This is the only step that uses the internet.

```mermaid
flowchart TD
    A(["start"]) --> B{"build tools installed?"}
    B -- no --> C["install them from the normal repos"]
    B -- yes --> D
    C --> D{"repo already built and the only enabled one?"}
    D -- yes --> G
    D -- no --> E["download all packages<br/>with their dependencies"]
    E --> F["createrepo_c: make the repo metadata"]
    F --> G{"distribution GPG key found?"}
    G -- no --> X["stop: key not found"]:::stop
    G -- yes --> H["write private-local.repo<br/>with gpgcheck=1"]
    H --> I["set enabled=0 in every other repo file"]
    I --> J["dnf clean all"]
    J --> K(["only private-local is enabled"])
    classDef stop stroke:#d9534f,stroke-width:3px
```

---

## Step 2 install_apache.sh

Installs Apache **from the private repo** and makes it run as its own user.

```mermaid
flowchart TD
    A(["start"]) --> B["install httpd"]
    B --> C{"user webreport exists?"}
    C -- no --> D["create system user<br/>no home, no login"]
    C -- yes --> E
    D --> E["set User and Group = webreport<br/>in httpd.conf"]
    E --> F["tmpfiles rule: web root stays<br/>owned by webreport after reboot"]
    F --> G{"index.html exists?"}
    G -- no --> H["write a temporary page"]
    G -- yes --> I
    H --> I["chown webreport + restorecon<br/>on the web root"]
    I --> J{"apachectl configtest OK?"}
    J -- no --> X["stop"]:::stop
    J -- yes --> K["enable and restart httpd"]
    K --> L(["Apache runs as webreport"])
    classDef stop stroke:#d9534f,stroke-width:3px
```

---

## Step 3 configure_https.sh

HTTPS with our own certificate, the redirect, `/repo/`, and the firewall.

```mermaid
flowchart TD
    A(["start"]) --> B["install mod_ssl, openssl, firewalld"]
    B --> C{"found the server IP?"}
    C -- no --> X1["stop: no IP address"]:::stop
    C -- yes --> D{"certificate missing, expiring<br/>or without this IP?"}
    D -- yes --> E["create a self-signed certificate<br/>(hostname + IP inside)"]
    D -- no --> F
    E --> F["add it to the system trust store"]
    F --> G["point the default ssl.conf<br/>to our certificate"]
    G --> H["write the site config:<br/>port 80 redirects to https<br/>port 443 serves the page and /repo/"]
    H --> I{"apachectl configtest OK?"}
    I -- no --> X2["stop: the old site stays up"]:::stop
    I -- yes --> J["restart httpd"]
    J --> K["firewalld on, open http and https"]
    K --> L(["https works"])
    classDef stop stroke:#d9534f,stroke-width:3px
```

---

## Step 4 mount_disks.sh

Two disks. The script uses the **free real disks** it finds (any name: `sdb`, `vdb`, `nvme0n2`...). If there is no free disk, it makes an **image file** and uses that instead. The part inside the loop runs once for `/mnt/metrics` and once for `/backup`.

```mermaid
flowchart TD
    A(["start"]) --> B["install xfsprogs<br/>make the folders"]
    B --> B2["look for free disks<br/>(whole disk, nothing written on it)"]
    B2 --> C["next disk<br/>(metrics first, then backup)"]
    C --> D{"line in /etc/fstab?"}
    D -- "yes, done in an earlier run" --> J
    D -- no --> E{"a free disk left?"}

    E -- yes --> F1["use the free disk"]
    F1 --> F2["format as xfs, only if empty"]
    F2 --> F3["add its UUID line to /etc/fstab"]
    F3 --> J

    E -- no --> G1["create the image file<br/>(sparse, only root can read)"]
    G1 --> G2["format as xfs, only if empty"]
    G2 --> G3["add the image line to /etc/fstab"]
    G3 --> J

    F2 -- "blkid error" --> X1["stop: never format by mistake"]:::stop
    G2 -- "blkid error" --> X1

    J{"mounted?"} -- no --> K["mount it"]
    J -- yes --> L
    K --> L{"really mounted now?"}
    L -- no --> X2["stop: the disk is missing"]:::stop
    L -- yes --> M["owner webreport, mode 0700"]
    M --> N{"both disks done?"}
    N -- no --> C
    N -- yes --> O["findmnt --verify"]
    O --> P(["both disks mounted"])
    classDef stop stroke:#d9534f,stroke-width:3px
```

---

## Step 5 setup_crons.sh

Installs the two jobs and runs them once. The jobs run as `webreport`, not as root.

```mermaid
flowchart TD
    A(["start"]) --> B["install jq, cronie, logrotate"]
    B --> C["copy the scripts to<br/>/usr/local/bin/linux-server-project"]
    C --> D["create cron.log<br/>owned by webreport"]
    D --> E["write /etc/cron.d/linux-server-project<br/>report every minute<br/>archive every 10 minutes"]
    E --> F["write the logrotate file<br/>daily, 7 copies"]
    F --> G["enable and start crond<br/>and logrotate.timer"]
    G --> H["run once as webreport:<br/>report, archive, report"]
    H --> I(["cron works, the page has data"])
```

---

## Step 5a generate_report.sh

Run by cron **every minute**.

```mermaid
flowchart TD
    A(["cron: every minute"]) --> B["collect the values<br/>host, IP, OS, kernel, uptime, load<br/>CPU, memory, 3 disks<br/>users, ports, top 5, services, archives"]
    B --> C["jq: write the JSON to a temp file"]
    C --> D["mv to /mnt/metrics/report_TIME.json"]
    D --> E["write the HTML to a temp file<br/>inside the web root"]
    E --> F["mv to /var/www/html/index.html"]
    F --> G(["the page is new"])
```

---

## Step 5b archive_reports.sh

Run by cron **every 10 minutes**.

```mermaid
flowchart TD
    A(["cron: every 10 minutes"]) --> B{"any report_*.json?"}
    B -- no --> Z(["nothing to do, exit 0"])
    B -- yes --> C["tar: pack them into<br/>/backup/reports_DATE.tar.gz"]
    C --> D{"tar -t test OK?"}
    D -- no --> X["delete the archive, keep the reports, stop"]:::stop
    D -- yes --> E["sha256sum into a .sha256 file"]
    E --> F["delete the packed JSON files"]
    F --> G{"more than 48 archives?"}
    G -- yes --> H["delete the oldest<br/>and their .sha256 files"]
    G -- no --> I
    H --> I(["done"])
    classDef stop stroke:#d9534f,stroke-width:3px
```

---

## Step 6 verify.sh

Looks at everything, **changes nothing**. It runs all 20 checks, even after one fails.

```mermaid
flowchart TD
    A(["sudo ./verify.sh"]) --> B["repo: 2 checks<br/>only private-local, httpd came from it"]
    B --> C["services: 6 checks<br/>httpd, firewalld, crond: enabled and running"]
    C --> D["Apache workers run as webreport"]
    D --> E["web: 3 checks<br/>https 200, http 301, /repo/ 200"]
    E --> F["disks: 5 checks<br/>mounted, in fstab, fstab is valid"]
    F --> G["index.html is less than 3 minutes old"]
    G --> H["an archive exists and its checksum matches"]
    H --> I["SELinux is Enforcing"]
    I --> J{"any FAIL?"}
    J -- yes --> X["N check/checks failed<br/>exit 1"]:::stop
    J -- no --> K(["Site ready: https://IP/<br/>exit 0"])
    classDef stop stroke:#d9534f,stroke-width:3px
```

---

## The big picture

The whole project, from the four commands to a server that keeps reporting after a reboot.

```mermaid
flowchart TD
    A(["fresh Rocky Linux 9 server"]) --> B["4 commands from the README:<br/>install git, clone, cd, sudo ./run.sh"]

    subgraph RUN ["run.sh (everything is also written to install.log)"]
        direction TB
        S1["1 private repo<br/>download packages, build the repo<br/>only private-local stays enabled"]
        S2["2 Apache<br/>install httpd from the repo<br/>runs as webreport"]
        S3["3 HTTPS<br/>own certificate, redirect, /repo/<br/>firewall open"]
        S4["4 disks<br/>/mnt/metrics and /backup<br/>free disks, or image files if none<br/>formatted once, in fstab, mounted"]
        S5["5 cron<br/>installs the two jobs and log rotation<br/>runs them once"]
        S6["6 verify<br/>20 checks, PASS or FAIL"]
        S1 --> S2 --> S3 --> S4 --> S5 --> S6
    end

    B --> S1
    S6 --> OK(["Site ready: https://IP/"])
    OK --> LIVE

    subgraph LIVE ["from now on, all the time"]
        direction TB
        C1["cron, every minute<br/>generate_report.sh"]
        C2["cron, every 10 minutes<br/>archive_reports.sh"]
        P["status page<br/>/var/www/html/index.html"]
        J["JSON report<br/>/mnt/metrics"]
        T["archive and .sha256<br/>/backup, newest 48"]
        C1 --> P
        C1 --> J
        J --> C2
        C2 --> T
    end

    LIVE --> R["reboot"]
    R --> R2["fstab mounts the disks<br/>services start<br/>cron keeps running"]
    R2 --> V(["sudo ./verify.sh<br/>works at any time"])
```

