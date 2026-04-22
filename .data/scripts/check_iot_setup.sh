#!/bin/bash

# ============================================================================
# IoT Box mode — ASYNC part (runs in separate tmux pane alongside Odoo)
#
# Handles:
#   - System deps (sudo, mtr, libcups2-dev, inotify-tools)
#   - Python deps (pyudev, zeroconf)
#   - CUPS virtual printers (office + ZPL label + receipt)
#   - DB setup (mark iot module for install, create iot.box record)
#   - Status dashboard + print job log watcher
#
# CUPS daemon and core Python deps are started in check_iot.sh (blocking).
# This script is non-blocking for Odoo startup.
# ============================================================================

if [ "${ODOO_IOT_BOX}" != "true" ]; then
    exit 0
fi

MAJOR_VERSION=$(echo "${ODOO_VERSION}" | cut -d'.' -f1)
if [ -z "$MAJOR_VERSION" ] || [ "$MAJOR_VERSION" -lt 19 ] 2>/dev/null; then
    exit 0
fi

ODOO_CONF="/etc/odoo/odoo.conf"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " IoT Box Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ============================================================================
# System dependencies
# ============================================================================
echo ""
echo "▸ System packages..."
APT_NEEDED=""
command -v sudo &>/dev/null || APT_NEEDED="$APT_NEEDED sudo"
command -v mtr &>/dev/null || APT_NEEDED="$APT_NEEDED mtr-tiny"
dpkg -s libcups2-dev &>/dev/null 2>&1 || APT_NEEDED="$APT_NEEDED libcups2-dev"
command -v inotifywait &>/dev/null || APT_NEEDED="$APT_NEEDED inotify-tools"
if [ -n "$APT_NEEDED" ]; then
    apt-get update -qq && apt-get install -y -qq $APT_NEEDED >/dev/null 2>&1
    echo "  installed:$APT_NEEDED"
else
    echo "  all present ✓"
fi

if ! command -v nmcli &>/dev/null; then
    printf '#!/bin/sh\nexit 1\n' > /usr/local/bin/nmcli
    chmod +x /usr/local/bin/nmcli
fi

# ============================================================================
# Python dependencies
# ============================================================================
echo ""
echo "▸ Python packages..."
uv pip install pyudev zeroconf 2>&1 | tail -2

IOT_REQ="/opt/odoo/odoo/addons/iot_box_image/configuration/requirements.txt"
if [ -f "$IOT_REQ" ]; then
    uv pip install -r "$IOT_REQ" 2>&1 | tail -2 || true
fi
echo "  done ✓"

# ============================================================================
# CUPS + virtual printers
# ============================================================================
echo ""
echo "▸ Virtual printers..."
VPRINT_DIR="/var/spool/virtual-printer"
VPRINT_BACKEND="/usr/lib/cups/backend/virtual-printer"

CUPS_CONF="/etc/cups/cupsd.conf"
if [ -f "$CUPS_CONF" ]; then
    sed -i 's/^LogLevel .*/LogLevel info/' "$CUPS_CONF"
    pidof cupsd &>/dev/null && kill -HUP "$(pidof cupsd)" 2>/dev/null
fi

mkdir -p "$VPRINT_DIR" 2>/dev/null
chmod 777 "$VPRINT_DIR" 2>/dev/null

if [ ! -x "$VPRINT_BACKEND" ]; then
    cat > "$VPRINT_BACKEND" << 'BACKEND_EOF'
#!/usr/bin/env python3
import os, sys, time
from urllib.request import Request, urlopen
from urllib.error import URLError

OUTPUT_DIR = "/var/spool/virtual-printer"

def main():
    if len(sys.argv) == 1:
        print('file virtual-printer "Unknown" "Virtual Printer Backend"')
        return 0

    job_id = sys.argv[1]
    title = sys.argv[3] if len(sys.argv) > 3 else "untitled"
    safe_title = "".join(c if c.isalnum() or c in "-_." else "_" for c in title)[:50]

    if len(sys.argv) > 6 and sys.argv[6]:
        with open(sys.argv[6], "rb") as f:
            data = f.read()
    else:
        data = sys.stdin.buffer.read()

    if not data:
        return 0

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    os.chmod(OUTPUT_DIR, 0o777)
    ts = time.strftime("%Y%m%d_%H%M%S")

    is_zpl = b"^XA" in data[:200]

    if is_zpl:
        try:
            req = Request(
                "http://api.labelary.com/v1/printers/8dpmm/labels/4x6/0/",
                data=data,
                headers={"Accept": "application/pdf"},
            )
            resp = urlopen(req, timeout=15)
            pdf_data = resp.read()
            out = os.path.join(OUTPUT_DIR, f"zpl_{ts}_{job_id}_{safe_title}.pdf")
            with open(out, "wb") as f:
                f.write(pdf_data)
            os.chmod(out, 0o666)
            sys.stderr.write(f"INFO: ZPL rendered to PDF → {out}\n")
            return 0
        except (URLError, OSError) as e:
            sys.stderr.write(f"WARNING: Labelary API failed ({e}), saving raw ZPL\n")
            out = os.path.join(OUTPUT_DIR, f"zpl_{ts}_{job_id}_{safe_title}.zpl")
            with open(out, "wb") as f:
                f.write(data)
            os.chmod(out, 0o666)
            return 0

    ext = "pdf" if data[:5] == b"%PDF-" else "ps" if data[:2] == b"%!" else "raw"
    out = os.path.join(OUTPUT_DIR, f"print_{ts}_{job_id}_{safe_title}.{ext}")
    with open(out, "wb") as f:
        f.write(data)
    os.chmod(out, 0o666)
    sys.stderr.write(f"INFO: saved {ext} → {out}\n")
    return 0

if __name__ == "__main__":
    sys.exit(main() or 0)
BACKEND_EOF
    chmod 700 "$VPRINT_BACKEND"
    echo "  created CUPS backend"
fi

if ! lpstat -p virtual-ipp-office 2>/dev/null; then
    lpadmin -p virtual-ipp-office \
        -v virtual-printer:/ \
        -E -m raw \
        -D "Virtual Office Printer" \
        -L "IoT Dev Emulator" \
        -o printer-is-shared=false 2>/dev/null
    cupsaccept virtual-ipp-office 2>/dev/null
    cupsenable virtual-ipp-office 2>/dev/null
    echo "  virtual-ipp-office (office_printer) ✓"
fi

if ! lpstat -p virtual-ipp-zpl 2>/dev/null; then
    lpadmin -p virtual-ipp-zpl \
        -v virtual-printer:/zpl \
        -E -m raw \
        -D "Virtual ZPL Label Printer" \
        -L "IoT Dev Emulator" \
        -o printer-is-shared=false 2>/dev/null
    cupsaccept virtual-ipp-zpl 2>/dev/null
    cupsenable virtual-ipp-zpl 2>/dev/null
    echo "  virtual-ipp-zpl (label_printer) ✓"
fi

if ! lpstat -p virtual-ipp-tm-m30 2>/dev/null; then
    lpadmin -p virtual-ipp-tm-m30 \
        -v virtual-printer:/receipt \
        -E -m raw \
        -D "Virtual Receipt Printer" \
        -L "IoT Dev Emulator" \
        -o printer-is-shared=false 2>/dev/null
    cupsaccept virtual-ipp-tm-m30 2>/dev/null
    cupsenable virtual-ipp-tm-m30 2>/dev/null
    echo "  virtual-ipp-tm-m30 (receipt_printer) ✓"
fi

echo ""
echo "  Status:"
lpstat -p 2>/dev/null | while read -r line; do echo "    $line"; done
echo "  Output → ${VPRINT_DIR}/"

# ============================================================================
# DB setup (wait for PostgreSQL first)
# ============================================================================
echo ""
echo "▸ Database setup..."

DB="${SELECTED_DB}"
if [ -z "$DB" ]; then
    echo "  no SELECTED_DB, skipping"
else
    until pg_isready -h "db" -p "5432" -U "odoo" -q 2>/dev/null; do
        sleep 2
    done

    export PGPASSWORD="odoo"
    PG="psql -h db -U odoo -d $DB"

    IOT_STATE=$($PG -tAc "SELECT state FROM ir_module_module WHERE name = 'iot' LIMIT 1" 2>/dev/null)
    if [ -z "$IOT_STATE" ]; then
        echo "  'iot' module not in DB (enterprise not loaded?)"
    elif [ "$IOT_STATE" = "installed" ] || [ "$IOT_STATE" = "to install" ] || [ "$IOT_STATE" = "to upgrade" ]; then
        echo "  iot module: ${IOT_STATE} ✓"
    else
        $PG -c "UPDATE ir_module_module SET state = 'to install' WHERE name = 'iot';" 2>/dev/null
        echo "  iot module: marked for install (was: ${IOT_STATE})"
    fi

    if $PG -tAc "SELECT 1 FROM information_schema.tables WHERE table_name = 'iot_box'" 2>/dev/null | grep -q 1; then
        IOT_IDENTIFIER="test_identifier"
        EXISTING=$($PG -tAc "SELECT id FROM iot_box WHERE identifier = '${IOT_IDENTIFIER}' LIMIT 1" 2>/dev/null)
        if [ -n "$EXISTING" ]; then
            echo "  iot.box record: id=${EXISTING} ✓"
        else
            $PG -c "
                INSERT INTO iot_box (identifier, name, ip, version, drivers_auto_update, create_uid, write_uid, create_date, write_date)
                VALUES ('${IOT_IDENTIFIER}', 'Virtual IoT Box', '127.0.0.1', 'T0.0', true, 1, 1, NOW(), NOW());
            " 2>/dev/null
            echo "  iot.box record: created ✓"
        fi
    else
        echo "  iot_box table not found (will be created after iot module install)"
    fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " IoT Box Ready"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ============================================================================
# Status dashboard (top pane) — refreshes every 2s, no flicker
# ============================================================================
cat > /tmp/_iot_status.sh << 'STATUS_EOF'
#!/bin/bash
tput civis 2>/dev/null
trap 'tput cnorm 2>/dev/null; exit 0' EXIT INT TERM

while true; do
    printf '\033[H'

    python3 -c "
import cups, os, sys, time

CL  = '\033[K'
RST = '\033[0m'
B   = '\033[1m'
D   = '\033[2m'
GRN = '\033[32m'
YLW = '\033[33m'
RED = '\033[31m'
CYN = '\033[36m'
WHT = '\033[97m'
MAG = '\033[35m'

def L(s=''):
    print(f'{s}{CL}')

try:
    c = cups.Connection()
    printers = c.getPrinters()
    jobs = c.getJobs()
except:
    L(f' {RED}✗ CUPS unavailable{RST}')
    sys.exit(0)

states  = {3: f'{GRN}●{RST}', 4: f'{YLW}◉{RST}', 5: f'{RED}■{RST}'}
stnames = {3: ('idle', GRN), 4: ('printing', YLW), 5: ('stopped', RED)}
icons   = {'zpl': ('label',   MAG, '🏷 '), 'tm-m30': ('receipt', YLW, '🧾'), '_default': ('office',  CYN, '📄')}

spool = '/var/spool/virtual-printer'
total_files = len([f for f in os.listdir(spool) if not f.startswith('.')])
total_jobs = len(jobs)
files = sorted([f for f in os.listdir(spool) if not f.startswith('.')], key=lambda f: os.path.getmtime(os.path.join(spool, f)), reverse=True)
last = files[0] if files else ''

name_w = max((len(n) for n in printers), default=20)
st_w = 8

L(f'{B}{CYN} 🖨  IoT Virtual Printers{RST}  {D}⏱ {time.strftime(\"%H:%M:%S\")}{RST}')
L(f'{D}─────────────────────────────────────────────────{RST}')

for name, info in printers.items():
    st = info.get('printer-state', 0)
    dot = states.get(st, f'{D}?{RST}')
    st_name, st_col = stnames.get(st, ('unknown', D))
    pad_name = name + ' ' * (name_w - len(name))
    pad_st = st_name + ' ' * (st_w - len(st_name))

    kind_name, kind_col, kind_icon = icons['_default']
    for k, v in icons.items():
        if k != '_default' and k in name.lower():
            kind_name, kind_col, kind_icon = v
            break

    active = [j for j, d in jobs.items() if d.get('job-state') == 5 and d.get('job-printer-uri','').endswith('/' + name)]
    job_txt = f'  {YLW}← #{active[0]}{RST}' if active else ''

    L(f' {dot} {B}{WHT}{pad_name}{RST}  {st_col}{pad_st}{RST}  {D}│{RST}  {kind_col}{kind_icon} {kind_name}{RST}{job_txt}')

L(f'{D}─────────────────────────────────────────────────{RST}')
L(f' {D}    📁 {total_files} file(s)      │      🗒 {total_jobs} job(s){RST}')
L(f' {D}last: {last[:30] if last else \"—\"}{RST}')
print(f'\033[J', end='')
" 2>/dev/null

    sleep 2
done
STATUS_EOF
chmod +x /tmp/_iot_status.sh
STATUS_PANE_HEIGHT=9
IOT_COLS="${IOT_PANE_WIDTH:-49}"
tmux resize-pane -t "$TMUX_PANE" -x "$IOT_COLS"
STATUS_PANE=$(tmux split-window -t "$TMUX_PANE" -b -v -l $STATUS_PANE_HEIGHT -P -F '#{pane_id}' "bash /tmp/_iot_status.sh")
LOG_PANE="$TMUX_PANE"

tmux select-pane -t "$STATUS_PANE" -d
tmux select-pane -t "$LOG_PANE" -d
tmux resize-pane -t "$STATUS_PANE" -y "$STATUS_PANE_HEIGHT"
tmux resize-pane -t "$STATUS_PANE" -x "$IOT_COLS"
tmux resize-pane -t "$LOG_PANE" -x "$IOT_COLS"

echo "$STATUS_PANE $LOG_PANE" > /tmp/.iot_locked_panes

tmux set-hook -t logs pane-focus-in \
    "run-shell 'P=\"#{pane_id}\"; read A B < /tmp/.iot_locked_panes 2>/dev/null; if [ \"\$P\" = \"\$A\" ] || [ \"\$P\" = \"\$B\" ]; then tmux select-pane -l -t logs; fi'"

# ============================================================================
# Log watcher (bottom pane — stays in current pane)
# ============================================================================
echo -e "\033[1m\033[36m 📋 Print Jobs Log\033[0m"
echo -e "\033[2m$(printf '─%.0s' $(seq 1 49))\033[0m"
echo ""

CUPS_LOG="/var/log/cups/error_log"
mkdir -p /var/log/cups 2>/dev/null
touch "$CUPS_LOG" 2>/dev/null

tail -n 0 -f "$CUPS_LOG" 2>/dev/null | grep --line-buffered -E "INFO|WARNING|ERROR" &
TAIL_PID=$!
trap 'kill $TAIL_PID 2>/dev/null; exit 0' EXIT INT TERM

inotifywait -m -e create -e moved_to --format '%T  ✓ %f' --timefmt '%H:%M:%S' "$VPRINT_DIR" 2>/dev/null || \
    while true; do
        BEFORE=$(ls "$VPRINT_DIR" 2>/dev/null | wc -l)
        sleep 3
        AFTER=$(ls "$VPRINT_DIR" 2>/dev/null | wc -l)
        if [ "$AFTER" -gt "$BEFORE" ]; then
            NEW=$(ls -t "$VPRINT_DIR" 2>/dev/null | head -1)
            echo "$(date '+%H:%M:%S')  ✓ $NEW"
        fi
    done
