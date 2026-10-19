#!/bin/bash
# ============================================================================
# test - Run the Odoo tests of your modules on a throwaway database
# ============================================================================
# Usage: test [-t TAGS] [--on DB] [--keep] [--no-demo] [-v] [--coverage] MODULE[,MODULE2,...]
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh
PANE=always   # long: runs in a side pane of the utils terminal

show_help() {
    h_name "test" "Run the Odoo tests of your modules on a throwaway database"
    h_sec "USAGE"
    h_use "test [options] MODULE[,MODULE2,...]"
    h_sec "OPTIONS"
    h_opt "-t, --tags TAGS" "Odoo --test-tags (e.g. /my_module:TestX.test_y, :TestX, at_install)"
    h_opt "--on DB" "Test on a copy of DB with -u (default: fresh database with -i)"
    h_opt "--keep" "Keep the test database afterwards (inspect it with shell / psql)"
    h_opt "--no-demo" "Fresh database without demo data (default: demo installed)"
    h_opt "-v, --verbose" "Show the full Odoo log, not only tests and errors"
    h_opt "--coverage" "Line coverage of the tested modules (coverage.py); HTML report kept"
    h_sec "DESCRIPTION"
    h_text "Creates test_<module>_<time> (or a clone of --on DB), installs/updates the"
    h_text "modules with --test-enable --stop-after-init, prints the test lines and"
    h_text "the summary, then drops the database. The running Odoo is not touched."
    h_text "Full log: .data/volumes/shared/tests/<db>.log   Exit code 0 = all passed."
    h_sec "EXAMPLES"
    h_ex "test my_module" "Fresh DB with demo data"
    h_ex "test my_module,my_other" ""
    h_ex "test -t :TestInvoice my_module" "One test class"
    h_ex "test --on main --keep my_module" "On a copy of main, keep it"
    h_ex "test --coverage my_module" "With a coverage report"
    h_global
    h_end
}

parse_global_flags "$@"
set -- "${ARGS[@]}"
TAGS=""; ON_DB=""; KEEP=false; DEMO=true; VERBOSE=false; COVERAGE=false; MODULES=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_help; exit 0 ;;
        -t|--tags) TAGS="${2:-}"; [ -z "$TAGS" ] && die "--tags needs a value"; shift 2 ;;
        --on) ON_DB="${2:-}"; [ -z "$ON_DB" ] && die "--on needs a database name"; shift 2 ;;
        --keep) KEEP=true; shift ;;
        --no-demo) DEMO=false; shift ;;
        -v|--verbose) VERBOSE=true; shift ;;
        --coverage) COVERAGE=true; shift ;;
        -*) die "Unknown option: $1" "See: test --help" ;;
        *) MODULES="${MODULES:+$MODULES,}$1"; shift ;;
    esac
done
[ -z "$MODULES" ] && die "No module given" "Usage: test MODULE[,MODULE2,...]"

require_odoo_container
require_db_container
refresh_modules_cache "$(docker exec "$ODOO_CONTAINER" /usr/local/bin/generate_addons_path.sh 2>/dev/null)"
EXPANDED=$(expand_modules "$MODULES")
[ -z "$EXPANDED" ] && die "No matching module"
UNKNOWN=$(unknown_modules "$EXPANDED")
[ -n "$UNKNOWN" ] && die "Unknown module(s): $(echo "$UNKNOWN" | paste -sd, -)" "Module names are matched against addons + odoo + enterprise"
open_pane

FIRST="${EXPANDED%%,*}"
TEST_DB="test_${FIRST}_$(date +%H%M%S)"
valid_db_name "$TEST_DB" || die "Invalid test database name: $TEST_DB"
LOG_DIR="${_PROJECT_ROOT}/.data/volumes/shared/tests"
mkdir -p "$LOG_DIR"
LOG="${LOG_DIR}/${TEST_DB}.log"

cleanup() {
    if $KEEP; then
        ui_note "Database kept: ${TEST_DB}   (psql -d ${TEST_DB} · shell ${TEST_DB} · db drop ${TEST_DB})"
    else
        drop_db_force "$TEST_DB"; remove_filestore "$TEST_DB"
    fi
}

ui_title "Tests" "${EXPANDED} → ${TEST_DB}"

# --test-enable runs the tests of every installed module: scope them to ours.
# -t specs without a /module part are applied to each module (:TestX → /m1:TestX,/m2:TestX).
scoped_tags() {
    local spec out="" m
    [ -z "$TAGS" ] && { echo "/${EXPANDED//,/,/}"; return; }
    for spec in ${TAGS//,/ }; do
        if [[ "$spec" == */* ]]; then out="${out:+$out,}$spec"; continue; fi
        for m in ${EXPANDED//,/ }; do
            case "$spec" in
                -*) out="${out:+$out,}-${spec#-}" ;;      # exclusion tag: global
                :*|.*) out="${out:+$out,}/${m}${spec}" ;;  # :Class / .method
                *) out="${out:+$out,}${spec%%[:.]*}/${m}${spec#"${spec%%[:.]*}"}" ;;   # tag[:Class]
            esac
        done
    done
    echo "$out"
}
TEST_TAGS=$(scoped_tags)
# --test-enable always spawns the http server (HttpCase tests need it): use a free port.
ODOO_CMD=(odoo -c /etc/odoo/odoo.conf -d "$TEST_DB" --http-port 8099 --stop-after-init --test-enable --test-tags "$TEST_TAGS")
if [ -n "$ON_DB" ]; then
    db_exists "$ON_DB" || die "Database '$ON_DB' does not exist" "db list to see the databases"
    ui_step "Cloning ${ON_DB} → ${TEST_DB}..."
    clone_db "$ON_DB" "$TEST_DB" || die "Clone failed" "Another session holds '$ON_DB' — retry, or stop Odoo first"
    # -u only works on installed modules: install the others
    INSTALLED=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$TEST_DB" -tAc \
        "SELECT name FROM ir_module_module WHERE state = 'installed' AND name IN ('${EXPANDED//,/','}');" 2>/dev/null | paste -sd, -)
    TO_INSTALL=$(comm -23 <(tr ',' '\n' <<<"$EXPANDED" | sort) <(tr ',' '\n' <<<"$INSTALLED" | sort) | paste -sd, -)
    [ -n "$INSTALLED" ] && ODOO_CMD+=(-u "$INSTALLED")
    [ -n "$TO_INSTALL" ] && ODOO_CMD+=(-i "$TO_INSTALL") && ui_note "not installed on ${ON_DB}, installed for the test: ${TO_INSTALL}"
else
    ui_step "Creating ${TEST_DB}$($DEMO && echo ' (with demo data)')..."
    create_db "$TEST_DB" || die "Could not create ${TEST_DB}"
    if $DEMO; then
        # 19+: --with-demo ; older: --without-demo= (empty value re-enables demo over odoo.conf)
        if [ "$(odoo_major_version)" -ge 19 ] 2>/dev/null; then ODOO_CMD+=(--with-demo); else ODOO_CMD+=(--without-demo=); fi
    fi
    ODOO_CMD+=(-i "$EXPANDED")
fi
trap cleanup EXIT

# --coverage: same command under coverage.py, limited to the tested modules' folders
if $COVERAGE; then
    COV_SRC=$(docker exec "$ODOO_CONTAINER" bash -c 'for m in '"${EXPANDED//,/ }"'; do find /mnt/extra-addons -maxdepth 5 -type d -name "$m" -print -quit; done' 2>/dev/null | paste -sd, -)
    [ -z "$COV_SRC" ] && die "--coverage: none of the modules is under ADDONS_PATH" "Coverage only applies to your own modules"
    COV_DATA="/tmp/.coverage_${TEST_DB}"
    COV_HTML="/var/lib/odoo/coverage/${TEST_DB}"
    ODOO_CMD=(python -m coverage run --data-file="$COV_DATA" --source="$COV_SRC" /opt/venv/bin/odoo "${ODOO_CMD[@]:1}")
    ui_kv "Coverage" "$COV_SRC"
fi

ui_kv "Tags" "$TEST_TAGS"
ui_step "Running: ${CMUTED}${ODOO_CMD[*]}${RST}"
echo
SECONDS=0
# Full log to file; on screen only what matters (tests, errors, warnings),
# without the timestamp/pid/db prefix and with the level colored.
pretty() {
    sed -u -E 's/^[0-9-]+ [0-9:,]+ [0-9]+ (INFO|WARNING|ERROR|CRITICAL) [^ ]+ /\1 /; s/^INFO odoo\.addons\.//' \
        | awk -v e="$CERROR" -v w="$CWARN" -v m="$CMUTED" -v r="$RST" '
            /^(ERROR|CRITICAL) /   { print e $0 r; next }
            /^WARNING /            { print w $0 r; next }
            /: Starting .* \.\.\. $/ { print m $0 r; next }
            { print }'
}
if $VERBOSE; then
    docker exec "$ODOO_CONTAINER" "${ODOO_CMD[@]}" 2>&1 | tee "$LOG" | pretty
else
    # test lines + ERROR/WARNING records with their full continuation (tracebacks)
    docker exec "$ODOO_CONTAINER" "${ODOO_CMD[@]}" 2>&1 | tee "$LOG" | awk '
        /^[0-9-]+ [0-9:,]+ [0-9]+ / { show = ($0 ~ / (ERROR|CRITICAL|WARNING) / || $0 ~ /odoo\.tests|odoo\.addons\.[a-z_0-9.]+\.tests/) }
        show { print; fflush() }' | pretty
fi
RC=${PIPESTATUS[0]}
echo

cov_report() {
    $COVERAGE || return 0
    echo
    docker exec "$ODOO_CONTAINER" python -m coverage report --data-file="$COV_DATA" --skip-empty 2>/dev/null | sed 's#/mnt/extra-addons/##; s/^/  /'
    docker exec "$ODOO_CONTAINER" python -m coverage html --data-file="$COV_DATA" -d "$COV_HTML" >/dev/null 2>&1 \
        && ui_note "HTML report: .data/volumes/odoo-container/odoo/coverage/${TEST_DB}/index.html"
    docker exec "$ODOO_CONTAINER" rm -f "$COV_DATA" 2>/dev/null
}

SUMMARY=$(grep -oE '[0-9]+ failed, [0-9]+ error\(s\) of [0-9]+ tests' "$LOG" | tail -1)
RAN=$(grep -oE 'Ran [0-9]+ tests? in [0-9.]+s' "$LOG" | tail -1)
N_ERR=$(grep -cE ' (ERROR|CRITICAL) ' "$LOG")
if [ "$RC" -eq 0 ] && [ "${N_ERR:-0}" -eq 0 ]; then
    if [[ "$SUMMARY" == *" of 0 tests" ]]; then
        ui_warn "No test ran $(fmt_duration "$SECONDS")"
        ui_note "Check tests/__init__.py imports, the @tagged decorators and the tags: ${TEST_TAGS}"
        ui_note "Full log: ${LOG#${_PROJECT_ROOT}/}"
        exit 1
    fi
    ui_done "Tests passed — ${SUMMARY:-${RAN:-done}}"
else
    ui_err "Tests failed — ${SUMMARY:-exit $RC, ${N_ERR} error line(s)} $(fmt_duration "$SECONDS")"
    if [ -z "$SUMMARY" ] && [ "${N_ERR:-0}" -gt 0 ]; then
        grep -E ' (ERROR|CRITICAL) ' "$LOG" | head -3 | sed -E 's/^[0-9-]+ [0-9:,]+ [0-9]+ //; s/^/  /'
    fi
    ui_note "Full log: ${LOG#${_PROJECT_ROOT}/}"
    cov_report
    exit 1
fi
ui_note "Full log: ${LOG#${_PROJECT_ROOT}/}"
cov_report
exit 0
