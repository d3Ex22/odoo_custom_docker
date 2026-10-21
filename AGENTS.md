# Odoo dev environment — guide for AI agents

This folder is a Docker environment for Odoo development. Everything is driven from the
**utils** container through a small set of commands. Humans use them in a terminal; agents
use the same commands through `docker exec` or the built-in **MCP server**.

Read `.env` first. The project name `<project>` is the folder name lowercased without its
leading `_` (`19/_AEC` → `aec`) unless `COMPOSE_PROJECT_NAME` is set in `.env`; it prefixes the
containers (`<project>_odoo`, `<project>_utils`, `<project>_db`) and the URLs
(`http://<project>.odoo|logs|utils|mcp|mail.docker.localhost`, hub of every project at
`http://odoo.docker.localhost`, Traefik dashboard at `http://traefik.docker.localhost`). Several
projects run at the same time behind one shared proxy (`odoo_proxy_traefik` / `odoo_proxy_hub`).
The hub (`.data/proxy/hub.py` + `static/`) pushes its state over SSE, requires its start token on
every POST (injected in the page) and journals the actions run on a project
(`/var/odoo-env/journal/<project>.json`, **history** in the menu). Its **config** panel (a tab's menu)
edits a project's `.env` as a form generated from the file: when adding a key to `.env`, keep the
layout (`# ===` / `# ---` blocks, help comments right above `KEY=value`, and as last help line the
marker `#@ apply=r|compose|rebuild [wipe=db] [type=bool] [auto] [optional]` — see the header of
`.env`). The save button and the tab flag are coloured by that level (blue restart / orange rebuild /
red wipe); the status daemon (`.data/scripts/status.py`, writes `status.json` and the tmux status bars
every 2s) reports the keys changed since the containers were created (`env_changed` in `/status`,
with `apply` and `wipe`) and the hub proposes the action. `.data/VERSION` is the release of the
environment: the daemon compares it hourly with the template's (`env_update` in `/status`) and the hub
proposes `env-update`; bump it to publish.
First start: Odoo stays down until `.data/volumes/shared/.setup_done` exists (`setup: true` in `/status`); the
hub's first-start dialog creates it — never create it
for the user without confirming the paths.
`SELECTED_DB` is the active database (empty = multi-db mode: every database command needs an
explicit database, nothing is asked without a terminal). Outgoing mails never leave the machine:
with `COMPOSE_PROFILES=mail` they land in Mailpit (`http://<project>.mail.docker.localhost`,
JSON API `/api/v1/messages`) — useful to assert that a flow sent a mail.

## 1. MCP server (preferred)

The utils container runs a **Streamable HTTP** MCP server (`.data/mcp/server.py`, Python stdlib only),
served by the shared proxy at `http://<project>.mcp.docker.localhost/mcp`. It is always on (started with the
container, the tmux status bar shows **MCP** green/red). Client configuration:

```json
{
  "mcpServers": {
    "odoo-<project>": { "url": "http://<project>.mcp.docker.localhost/mcp" }
  }
}
```

Cursor: `~/.cursor/mcp.json` or `<workspace>/.cursor/mcp.json`. The stack must be up.
`python3 .data/mcp/server.py --test|--tools|--config` (in the utils container) runs a handshake, lists the
tools, prints the configuration. Each project has its own URL, so several can be registered and used at the same time.

Stdio alternative (client spawns the process): `docker exec -i -u utils <project>_utils python3 /home/utils/odoo_custom_docker/.data/mcp/server.py`.

| Tool | Does |
|------|------|
| `odoo_status` | containers, Odoo process, selected DB, versions, URLs, .env settings — call first |
| `odoo_update(modules, keep, wait, database)` | restart with `-u modules` and return the ready/error report; `database` (name, comma list, `all`) required when `SELECTED_DB` is empty (multi-db mode) |
| `odoo_restart(wait)` / `odoo_start(wait)` / `odoo_stop()` | process control (no module update) |
| `odoo_logs(lines, grep, errors_only, level)` | read the logs pane; `errors_only` = tracebacks of the current run; `level` (`WARNING`, `ERROR`…) = every record of the current run at that level and above |
| `odoo_logs_since(since, grep)` | lines logged after a timestamp (`since` = a previous call's marker, printed at the end of each result): read only what your last `odoo_update` produced |
| `odoo_wait_ready(timeout)` | block until the current start finished |
| `odoo_shell(code, database)` | run Python in `odoo shell` (`env`, `self`); rolled back unless `env.cr.commit()` |
| `odoo_shell_commit(code, database)` | same, committed at the end (nothing committed if the code raises) — ask the user first |
| `odoo_test(modules, tags, on_database, keep, coverage)` | run module tests on a throwaway DB (fresh + demo, or clone of `on_database`); the running Odoo is untouched; `coverage` appends the coverage report of the tested modules |
| `odoo_model_info(model, database)` | fields of a model (type, string, relation, required, compute, store) and the modules that define it — faster than reading every `_inherit` |
| `odoo_xmlid(ref, database)` | resolve `module.name` → model, id and the useful content (view arch / inherit, action target, menu path, access rule) |
| `odoo_module_list(pattern)` | known module names |
| `db_list` / `db_select` / `db_backup` / `db_restore` / `db_drop` / `db_clone` | database management; `db_backup(keep=N)` rotates the backups of that DB; `db_restore` takes `file` (./db_files) **or** `last=true` (latest backup of that DB) |
| `db_query(sql, database)` | psql, CSV output |
| `conf_set(variable, value)` | write `SELECTED_DB`, `ODOO_UPDATE`, `ODOO_ARGS`, `DEBUGPY`, `COMPOSE_PROFILES`, versions (the output tells what applies it) |
| `repos_pull(repo, build, force)` | mounted Odoo/Enterprise git repos → `ODOO_VERSION` branch, build commit |
| `check_versions`, `translation_export`, `pre_commit`, `requirements_install` | tooling |

Prompts: `migrate_module(module, from_version)` and `debug_error()` give a step-by-step
procedure using the tools above. `GET /status` on the same server returns the live `status.json` of
the project (odoo, db, mcp, mail, enterprise, last start, database, versions, rebuild flag).

`db_drop`, `db_restore` and `odoo_shell_commit` are destructive: confirm with the user before calling them.

## 2. Shell access (fallback)

Every command is a script in `.data/scripts/commands/`, sourcing `.data/scripts/common.sh` (which
loads `.data/scripts/lib/{env,ui,panes,odoo,project,db}.sh`, one file per concern).
Run them non-interactively from the host:

```bash
docker exec -u utils <project>_utils bash /home/utils/odoo_custom_docker/.data/scripts/commands/<command>.sh -y [args]
```

Rules for non-interactive use:

- `-y` / `--yes` answers every confirmation; without a TTY a prompt **fails** instead of hanging.
- Colors are disabled automatically when stdout is not a terminal (`NO_COLOR=1` also works).
- Exit codes: `0` ok, `1` error / timeout, `2` (for `-w`) Odoo started **with errors** (details printed).
- The interactive pane of the utils terminal is tmux `utils:0.1`; the Odoo process runs in the
  odoo container, tmux pane `logs:0.1`, started by `odoo_runner.sh [-d DB] [-u MODULES]` (command
  built from `.env`, header, start guard, `exec odoo`; the command of the current run is in
  `/tmp/.odoo_cmd` of the odoo container). Prefer `internal/logs.sh` over `capture-pane`.
- `.data/scripts/internal/` holds the scripts that are not utils commands (humans use the hub for them)
  but that you can call: `logs.sh`, `status.sh`, `conf.sh`, `check_versions.sh` — the MCP tools wrap them.

### Typical loop after editing module code

```bash
U="docker exec -u utils <project>_utils bash /home/utils/odoo_custom_docker/.data/scripts/commands"
I="docker exec -u utils <project>_utils bash /home/utils/odoo_custom_docker/.data/scripts/internal"
$U/update.sh -y -w my_module          # restart with -u, wait, report errors (exit 2 if any)
$I/logs.sh -e                         # error blocks of the current run
$I/logs.sh -n 200 -g "my_module"      # grep the logs
$U/test.sh -y my_module               # run the module tests on a throwaway DB (exit 1 if a test failed)
M=$($I/logs.sh --mark); $U/update.sh -y -w my_module; $I/logs.sh --since "$M"   # only this update's lines
$I/status.sh; $I/conf.sh              # overview; .env runtime settings ($I/conf.sh VAR value sets one)
```

### Commands and flags (summary)

| Command | Flags | Notes |
|---------|-------|-------|
| `update` (`u`) `MODULES` | `-k` save as `ODOO_UPDATE`, `-w` wait | comma list, patterns `my_*`, `all` |
| `reboot` (`r`) / `start` (`s`) | `-w` | no module update |
| `stop` | | SIGKILL, instant |
| `test MODULES` | `-t TAGS`, `--on DB`, `--keep`, `--no-demo`, `--coverage`, `-v` | `test_<module>_<time>` DB, dropped afterwards; full log in `.data/volumes/shared/tests/`; HTML coverage under `.data/volumes/odoo-container/odoo/coverage/` |
| `debug [on\|off\|status]` | | Odoo under debugpy (port 5678 in the container, published on a host port shown by `debug`), writes `.vscode/launch.json` for the user's IDE; `on`/`off` restart Odoo |
| `watch [on\|off]` | | humans: auto `u <module>` on `__manifest__.py` save (`AUTO_UPDATE` in `.env`) |
| `database` (`db`) `list\|select\|drop\|clone\|backup\|restore\|sanitize` | `drop -f`, `clone -f`, `backup -fs --keep N`, `restore -s -f -na -F FILE\|--last`, `sanitize -a -F [FILE]` | `-F/--file` always means a backup file under `./db_files`; `--last` = latest `<name>_*.zip` |
| `psql [-d DB] [psql args]` | | `-tAc 'SQL'` for plain one-shot output |
| `translation MODULES\|--all` | `-l LANG`, `-d DB`, `--pot`, `-L` (every language) | overwrites `i18n/*.po` |
| `pre-commit` (`pc`) `[FOLDER]` | `-a` | modifies files in place |
| `upgrade-code --from VER` | `--to`, `--module`, `--dry-run`, `-f`, `-a` | needs Odoo 19+ |
| `migrate DB VERSION` | | upgrade.odoo.com, needs `ENTERPRISE_KEY` |
| `rebuild` | `-a`, `-n`, `-nc` | builds only the images missing for the `.env` stack (shared `odoo-env/*` tags: seconds when they exist, minutes otherwise); `-n` latest nightly; confirm with the user; pulls the repos first |
| `pull [odoo\|enterprise]` | `--build DATE\|latest`, `-f` | git repos of `ENTERPRISE_PATH` / `ODOO_PATH` → `ODOO_VERSION` branch |
| `env-update` | `-n`, `--ref REF`, `--from PATH` | refresh `.data/`, `docker-compose.yml`, docs from the template repo (`ENV_TEMPLATE_REPO`) or a local working copy (`--from`, host path); keeps `.env` values, `.config/`, `addons/`, `db_files/`; the project stays one git repo — confirm with the user, then follow its next steps (`rebuild`, `docker compose up -d`); it restarts the hub / MCP server itself when their files changed |
| `shell [DB]`, `grok` | | open tmux side panes — humans only; use `odoo_shell` / `docker exec -i ... odoo shell -d DB < code.py` instead |

Global flags on every command: `-y/--yes`, `-p/--pane` (side pane of the utils terminal, humans), `--no-color`.

Internal scripts (`.data/scripts/internal/`, no `--help`, not in the utils terminal):

| Script | Flags | Notes |
|--------|-------|-------|
| `logs.sh` | `-n N`, `-g PATTERN`, `-e`, `-w [SECONDS]`, `--since TS`, `--mark`, `--clear` | `--mark` prints a UTC timestamp, `--since` filters the lines after it; `-w` exits 2 on errors |
| `conf.sh [VAR [value\|-]]` | | `-` clears; `SELECTED_DB`, `ODOO_UPDATE`, `ODOO_ARGS`, `AUTO_UPDATE`, `DEBUGPY`, `COMPOSE_PROFILES`, the version stack, `ENTERPRISE_PATH` / `ODOO_PATH` / `ADDONS_PATH` (then `docker compose up -d`) |
| `status.sh`, `check_versions.sh` | | read-only overview; installed vs `.env` vs latest nightly |
| `prune.sh`, `mcp.sh start\|stop\|restart` | | run by the entrypoint (daily image cleanup, MCP server) — not for you |
Long commands (`rebuild`, `test`, `migrate`, `translation`, `upgrade-code`, `pre-commit`, `requirements`, `db restore|backup|sanitize`) open a side pane by themselves (after their arguments are checked: usage errors and help stay in the prompt) **only when a human runs them from the utils terminal**; without a TTY (your case) they run inline and print everything.
Exception: `psql` and `pip` forward all their arguments to the underlying binary (no `-y`).

## 3. Odoo shell from code

```bash
printf 'print(env["res.users"].search_count([]))\n' | \
  docker exec -i <project>_odoo odoo shell -c /etc/odoo/odoo.conf -d <db> --no-http --log-level=warn
```

The transaction is rolled back at exit; call `env.cr.commit()` explicitly to persist.

Tests: `test my_module` (or `odoo_test`) runs `odoo --test-enable -i my_module --stop-after-init` on a fresh
`test_my_module_<time>` database with demo data, prints the test lines and the summary, then drops it.
`-t :TestClass.test_method` narrows to one test, `--on main` clones `main` and runs with `-u` instead.

Environment self-test (host, not utils): `bash .data/tests/env_test.sh` brings up two throwaway copies
behind the proxy and checks containers, URLs, hub, MCP, mail and the main commands (TAP output).
Hub unit tests (host, no Docker): `python3 .data/tests/hub_test.py`.

## 4. Start guard

Odoo does not start when `ENTERPRISE_PATH` / `ODOO_PATH` are on another series than
`ODOO_VERSION` (`start`/`reboot`/`update` fail with the reason, `logs.sh -w` returns 2).
Fix: `pull` (repos are git clones) or `ODOO_VERSION` in `.env` (hub config, user's call) + `rebuild`.

## 5. Appearance

One palette for everything, `.data/scripts/lib/theme.sh` (hub colours in `.data/proxy/static/hub.css`):
`THEME_*` hex values, `COLOR_*` roles used by the commands, `TMUX_*` / `TERM_*` for the status bars
and the web terminals, `C*`/`B*` ANSI escapes when sourced from bash. Font, cursor, scrollback and the
clock's time zone of the terminals: `.config/terminal.conf`; prompt: `.config/utils/starship.toml`
(`${THEME_*}` placeholders filled at container start). The only per-project value is the primary colour
(`THEME_PRIMARY`: hub tab, titles, prompt, cursor): hashed from the project name, the next free palette
colour when another project of the machine already has it (written as `PROJECT_COLOR` in `.env`, which
also accepts a palette name or `#rrggbb`). Hub tabs can be reordered by drag and drop (kept in the browser).
The utils shell itself is `.data/scripts/zshrc.sh` (environment-owned); the user's aliases go to
`.config/utils/.zshrc`, sourced after it.

Docs: `README.md` (EN), `README.fr.md` (FR), `CHANGELOG.md`, `docs/` (and the root `.gitignore`) live in the template repository only
(removed from a project copy at start and by `env-update`); `AGENTS.md` is replaced by `env-update`.

## 6. Do not

- Edit `odoo/` or `enterprise/` sources; only the addons folders.
- Restore / drop databases, run `rebuild` or `docker compose down` without the user's go-ahead.
- Create DB columns by SQL: declare the field, bump the module version, run `u <module>`.
- Use `reboot` to load code changes: use `u <module>` (`reboot` never passes `-u`).
- Edit `ODOO_IMAGE_REV` / `UTILS_IMAGE_REV` in `.env`: they are computed from the Dockerfiles (`rebuild`, container start).
- Run `env-update` or `debug on/off` (restarts Odoo) without telling the user.
