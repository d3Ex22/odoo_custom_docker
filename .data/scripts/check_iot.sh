#!/bin/bash

# ============================================================================
# IoT Box mode — BLOCKING part (runs before Odoo starts)
#
# Handles:
#   - server_wide_modules (add/remove iot_drivers)
#   - [iot.box] in a dedicated file (not the mounted odoo.conf — ConfigParser
#     rewrites would strip comments/formatting)
#   - odoo.conf symlink for iot_drivers path_file() → that dedicated file
#   - Core Python deps required at iot_drivers import time
#   - CUPS daemon startup (PrinterInterface needs it at init)
#   - Patch iot_drivers handler loader for dev mode
#   - Patch get_conf/update_conf so [options]/[devtools] stay on /etc/odoo/odoo.conf
#     with surgical edits (no full-file rewrite)
#
# Async work (virtual printers, DB setup) is in check_iot_setup.sh.
# ============================================================================

ODOO_CONF="/etc/odoo/odoo.conf"
IOT_LOCAL_CONF="/var/lib/odoo/iot-drivers-local.conf"

if [ ! -f "$ODOO_CONF" ]; then
    exit 0
fi

_iot_conf_link_path() {
    local ob
    ob=$(which odoo 2>/dev/null)
    if [ -n "$ob" ]; then
        python3 -c "from pathlib import Path; print(Path('${ob}').resolve().parent.parent / 'odoo.conf')"
    else
        echo "/opt/venv/odoo.conf"
    fi
}

_conf_edit() {
    _CONF_EDIT_PATH="${2:-$ODOO_CONF}" _CONF_EDIT_CODE="$1" python3 << 'PYEOF'
import re, os
conf = os.environ["_CONF_EDIT_PATH"]
code = os.environ["_CONF_EDIT_CODE"]
with open(conf, "r") as f:
    content = f.read()
exec(code)
with open(conf, "w") as f:
    f.write(content)
PYEOF
}

# ============================================================================
# ODOO_IOT_BOX=false → remove iot_drivers + [iot.box], then exit
# ============================================================================
if [ "${ODOO_IOT_BOX}" != "true" ]; then
    SWM_LINE=$(grep -E "^server_wide_modules\s*=" "$ODOO_CONF" 2>/dev/null | head -1)
    if [ -n "$SWM_LINE" ] && echo "$SWM_LINE" | grep -q "iot_drivers"; then
        _conf_edit "
content = re.sub(
    r'^(server_wide_modules\s*=\s*)(.*)',
    lambda m: m.group(1) + ','.join(x.strip() for x in m.group(2).split(',') if x.strip() != 'iot_drivers'),
    content,
    flags=re.MULTILINE,
)
"
        echo "IoT: removed iot_drivers from server_wide_modules"
    fi
    if grep -q "^\[iot\.box\]" "$ODOO_CONF" 2>/dev/null; then
        _conf_edit "content = re.sub(r'\n?\[iot\.box\][^\[]*', '', content)"
        echo "IoT: removed [iot.box] section from odoo.conf"
    fi
    IOT_CONF_LINK=$(_iot_conf_link_path)
    rm -f "$IOT_CONF_LINK" 2>/dev/null
    rm -f "$IOT_LOCAL_CONF" 2>/dev/null
    exit 0
fi

# ============================================================================
# ODOO_IOT_BOX=true → version check
# ============================================================================
MAJOR_VERSION=$(echo "${ODOO_VERSION}" | cut -d'.' -f1)
if [ -z "$MAJOR_VERSION" ] || [ "$MAJOR_VERSION" -lt 19 ] 2>/dev/null; then
    echo ""
    echo "============================================================"
    echo "  WARNING: ODOO_IOT_BOX=true but Odoo ${ODOO_VERSION} < 19.0"
    echo "  IoT Box mode requires Odoo 19.0 or higher."
    echo "  Skipping IoT setup."
    echo "============================================================"
    echo ""
    exit 0
fi

# ============================================================================
# Critical Python deps (imported at iot_drivers module load time)
# ============================================================================
uv pip install netifaces 2>&1 | tail -1
if ! python3 -c "import netifaces" 2>/dev/null; then
    uv pip install netifaces2 2>&1 | tail -1
fi
uv pip install schedule websocket-client python-escpos PyKCS11 evdev pycups 2>&1 | tail -1
echo "IoT: core Python deps ready"

# ============================================================================
# Start CUPS daemon (PrinterInterface needs it at init time)
# ============================================================================
if ! command -v cupsd &>/dev/null; then
    apt-get update -qq && apt-get install -y -qq cups >/dev/null 2>&1
fi
if ! pidof cupsd &>/dev/null; then
    cupsd
    sleep 1
fi

# ============================================================================
# Add iot_drivers to server_wide_modules
# ============================================================================
SWM_LINE=$(grep -E "^server_wide_modules\s*=" "$ODOO_CONF" 2>/dev/null | head -1)

if [ -n "$SWM_LINE" ]; then
    if echo "$SWM_LINE" | grep -q "iot_drivers"; then
        echo "IoT: iot_drivers already in server_wide_modules"
    else
        CURRENT=$(echo "$SWM_LINE" | sed 's/server_wide_modules\s*=\s*//' | tr -d '\n\r ')
        NEW="${CURRENT},iot_drivers"
        _conf_edit "content = re.sub(r'^server_wide_modules\s*=.*', 'server_wide_modules = ${NEW}', content, flags=re.MULTILINE)"
        echo "IoT: added iot_drivers to server_wide_modules (${NEW})"
    fi
else
    _conf_edit "content = re.sub(r'(\[options\])', r'\1\nserver_wide_modules = base,web,iot_drivers', content)"
    echo "IoT: added server_wide_modules = base,web,iot_drivers (under [options])"
fi

# ============================================================================
# Dedicated IoT config file (avoids configparser destroying mounted odoo.conf)
# ============================================================================
mkdir -p "$(dirname "$IOT_LOCAL_CONF")"
ODOO_CONF="$ODOO_CONF" IOT_LOCAL_CONF="$IOT_LOCAL_CONF" python3 << 'MIGRATE_EOF'
import configparser
import os
import re
from pathlib import Path

main = Path(os.environ["ODOO_CONF"])
local = Path(os.environ["IOT_LOCAL_CONF"])
if not main.is_file():
    raise SystemExit(0)
txt = main.read_text(encoding="utf-8")
if re.search(r"^\[iot\.box\]\s*$", txt, re.MULTILINE | re.IGNORECASE):
    mp = configparser.RawConfigParser(strict=False)
    mp.read(str(main), encoding="utf-8")
    if mp.has_section("iot.box"):
        lp = configparser.RawConfigParser(strict=False)
        if local.is_file():
            lp.read(str(local), encoding="utf-8")
        if not lp.has_section("iot.box"):
            lp.add_section("iot.box")
        for k, v in mp.items("iot.box"):
            lp.set("iot.box", k, v)
        local.parent.mkdir(parents=True, exist_ok=True)
        with local.open("w", encoding="utf-8") as f:
            lp.write(f)
        content = main.read_text(encoding="utf-8")
        content = re.sub(r"\n?# =+ *\n# IoT Box *\n# =+ *\n", "\n", content)
        content = re.sub(r"\n?\[iot\.box\][^\[]*", "\n", content, flags=re.DOTALL)
        main.write_text(content, encoding="utf-8")
        print("IoT: moved [iot.box] from odoo.conf to iot-drivers-local.conf")
MIGRATE_EOF
if grep -q "^\[iot\.box\]" "$ODOO_CONF" 2>/dev/null; then
    _conf_edit "content = re.sub(r'\n?\[iot\.box\][^\[]*', '', content)"
    echo "IoT: removed leftover [iot.box] from odoo.conf"
fi

IOT_DB="${SELECTED_DB}"

if ! grep -q "^\[iot\.box\]" "$IOT_LOCAL_CONF" 2>/dev/null; then
    {
        printf "[iot.box]\nremote_server = http://127.0.0.1:8069\n"
        [ -n "$IOT_DB" ] && printf "db_name = %s\n" "$IOT_DB"
    } >> "$IOT_LOCAL_CONF"
    echo "IoT: initialized iot-drivers-local.conf"
else
    if ! grep -A5 "^\[iot\.box\]" "$IOT_LOCAL_CONF" 2>/dev/null | grep -q "^remote_server"; then
        _conf_edit "content = re.sub(r'(\[iot\.box\])', r'\1\nremote_server = http://127.0.0.1:8069', content)" "$IOT_LOCAL_CONF"
        echo "IoT: added remote_server to [iot.box] (local)"
    fi
    if [ -n "$IOT_DB" ]; then
        CURRENT_DB=$(grep -A10 "^\[iot\.box\]" "$IOT_LOCAL_CONF" 2>/dev/null | grep "^db_name" | head -1 | sed 's/db_name\s*=\s*//')
        if [ "$CURRENT_DB" != "$IOT_DB" ]; then
            if [ -n "$CURRENT_DB" ]; then
                _conf_edit "content = re.sub(r'^db_name\s*=.*', 'db_name = ${IOT_DB}', content, flags=re.MULTILINE)" "$IOT_LOCAL_CONF"
            else
                _conf_edit "content = re.sub(r'(\[iot\.box\])', r'\1\ndb_name = ${IOT_DB}', content)" "$IOT_LOCAL_CONF"
            fi
            echo "IoT: updated db_name to ${IOT_DB} (local)"
        fi
    fi
fi

# ============================================================================
# Symlink for iot_drivers path_file("odoo.conf") → local state file only
# ============================================================================
IOT_CONF_LINK=$(_iot_conf_link_path)
ln -sfn "$IOT_LOCAL_CONF" "$IOT_CONF_LINK"
echo "IoT: odoo.conf helpers path → ${IOT_LOCAL_CONF}"

# ============================================================================
# Patch iot_drivers to load Linux handlers in TEST mode (non-RPI, non-Windows)
# By default get_handlers_files_to_load returns [] → no printers in dev
# Must run BEFORE Odoo starts (Manager thread calls load_iot_handlers early)
# ============================================================================
python3 << 'PATCH_EOF'
import importlib.util, pathlib
spec = importlib.util.find_spec("odoo.addons.iot_drivers.tools.helpers")
if not spec or not spec.origin:
    exit(0)
p = pathlib.Path(spec.origin)
content = p.read_text()
old = "    return []"
SKIP = {'usb_interface_L', 'display_interface_L', 'serial_interface'}
new = (
    "    skip = " + repr(SKIP) + "\n"
    "    return [x.name for x in Path(handler_path).glob(f'*[!{IOT_WINDOWS_CHAR}].*') if x.stem not in skip]  # patched for dev"
)
if old in content and "# patched for dev" not in content:
    p.write_text(content.replace(old, new, 1))
    print("IoT: patched handler loader (printer only)")
PATCH_EOF

# ============================================================================
# Patch get_conf / update_conf: iot.box on local file; options/devtools surgical
# ============================================================================
python3 << 'PATCH_HELPERS_EOF'
import importlib.util
import pathlib

spec = importlib.util.find_spec("odoo.addons.iot_drivers.tools.helpers")
if not spec or not spec.origin:
    raise SystemExit(0)
mod_path = pathlib.Path(spec.origin)
text = mod_path.read_text(encoding="utf-8")
if "# odoo_custom_docker: conf split patch" in text:
    raise SystemExit(0)

append = '''

# odoo_custom_docker: conf split patch — iot.box on LOCAL; options/devtools surgical on MAIN
import pathlib as _odcd_pathlib
import configparser as _odcd_configparser
import re as _odcd_re

_ODCD_MAIN = "/etc/odoo/odoo.conf"
_ODCD_LOCAL = "/var/lib/odoo/iot-drivers-local.conf"


def _odcd_update_ini_section_preserving_format(path, section, values):
    path = _odcd_pathlib.Path(path)
    raw = path.read_text(encoding="utf-8")
    if not raw.endswith("\\n"):
        raw += "\\n"
    lines = raw.splitlines(keepends=True)
    sec = f"[{section}]"
    si = None
    for i, ln in enumerate(lines):
        if ln.strip().lower() == sec.lower():
            si = i
            break
    if si is None:
        if lines and not lines[-1].endswith("\\n"):
            lines[-1] += "\\n"
        lines.append("\\n" + sec + "\\n")
        si = len(lines) - 1
    sj = len(lines)
    for j in range(si + 1, len(lines)):
        t = lines[j].strip()
        if t.startswith("[") and t.endswith("]"):
            sj = j
            break
    head = lines[: si + 1]
    body = lines[si + 1 : sj]
    tail = lines[sj:]
    key_pat = _odcd_re.compile(r"^(\\s*)([^#=\\s]+)\\s*=")
    touched = set(values.keys())
    new_body = []
    for ln in body:
        m = key_pat.match(ln)
        if m and m.group(2) in touched:
            continue
        new_body.append(ln)
    for k, v in values.items():
        if v is None or v == "":
            continue
        new_body.append(f"{k} = {v}\\n")
    path.write_text("".join(head + new_body + tail), encoding="utf-8")


_orig_get_conf = get_conf
_orig_update_conf = update_conf


def get_conf(key=None, section="iot.box"):
    if section in ("options", "devtools"):
        c = _odcd_configparser.RawConfigParser(strict=False)
        c.read(_ODCD_MAIN, encoding="utf-8")
        if key is None:
            return c
        if not c.has_section(section):
            return None
        return c.get(section, key, fallback=None)
    c = _odcd_configparser.RawConfigParser(strict=False)
    c.read(_ODCD_LOCAL, encoding="utf-8")
    if key is None:
        return c
    if not c.has_section("iot.box"):
        return None
    return c.get("iot.box", key, fallback=None)


def update_conf(values, section="iot.box"):
    if section == "iot.box":
        c = _odcd_configparser.RawConfigParser(strict=False)
        c.read(_ODCD_LOCAL, encoding="utf-8")
        if not c.has_section("iot.box"):
            c.add_section("iot.box")
        for k, v in values.items():
            if v:
                c.set("iot.box", k, str(v))
            else:
                if c.has_option("iot.box", k):
                    c.remove_option("iot.box", k)
        _odcd_pathlib.Path(_ODCD_LOCAL).parent.mkdir(parents=True, exist_ok=True)
        with open(_ODCD_LOCAL, "w", encoding="utf-8") as f:
            c.write(f)
        return
    if section in ("options", "devtools"):
        _odcd_update_ini_section_preserving_format(
            _ODCD_MAIN,
            section,
            {k: ("" if v is None else str(v)) for k, v in values.items()},
        )
        return
    _orig_update_conf(values, section=section)

'''
mod_path.write_text(text.rstrip() + append + "\n", encoding="utf-8")
print("IoT: patched helpers get_conf/update_conf (preserve odoo.conf layout)")
PATCH_HELPERS_EOF

echo "IoT: config ready"
