# Changelog

The release of a project copy is in `.data/VERSION`; the hub flags a newer one and `env-update`
applies it (see [README](README.md#keeping-a-project-up-to-date)).

## 4.0.0

Several projects at once, a hub, agents, one toolbox. A copy of version 3 upgrades with
`docker compose down`, then `env-update --from <path of a 4.0 copy>` (or copy `docker-compose.yml`,
`.data/`, `.dockerignore` and merge `.env` by hand), `rebuild`, `docker compose up -d`. Databases and
filestore are bind mounts in the project folder: nothing to migrate.

### Several projects, one proxy

- The per-project Traefik (`<project>_traefik`, port 80) is replaced by one shared stack `odoo_proxy`
  (Traefik + hub, `.data/proxy/`), started by the first project that comes up. It listens on
  `127.0.0.1` only.
- The project is named after its folder (`./19/_AEC` → `aec`): containers `aec_odoo` / `aec_utils` /
  `aec_db`, URLs `aec.odoo|logs|utils|mcp|mail.docker.localhost`. `COMPOSE_PROJECT_NAME` is empty by
  default (set it only when two folders share a name). Remove the old `*_traefik` container of a copy
  before starting it.
- `.env` keys gone: `ODOO_URL`, `LOGS_URL`, `UTILS_URL`, `NETWORK_NAME`, `NETWORK_SUBNET`,
  `RESTART_ON_FAIL`, `FORCE_STOP_DELAY`. New: `COMPOSE_PROFILES`, `IMAGE_RETENTION_DAYS`,
  `SSH_PATH`, `PROJECT_COLOR`, `ODOO_WS_PORT`, `DEBUGPY` / `DEBUGPY_PORT`, `AUTO_UPDATE`,
  `ENV_TEMPLATE_REPO` / `ENV_TEMPLATE_REF`, `ODOO_IMAGE_REV` / `UTILS_IMAGE_REV` (auto), `GITHUB_TOKEN`.
  Each key carries a `#@ apply=…` marker line that drives the hub's Config panel.

### Hub (`http://odoo.docker.localhost`)

- One tab per project seen on this machine: live status dots (Odoo, PostgreSQL, Enterprise), views
  Odoo / Logs / Utils / Mail / MCP kept mounted, `REBUILD` / `RESTART` / `WIPE DB` / release flags,
  rebuild and start progress in the tab, drag-and-drop order, `Alt+1..9`, `Alt+←/→`, `Alt+V`.
- Menu per project: Config, history (journal of the hub actions), restart odoo, compose down; Start for
  stopped projects; update env when a newer release is published.
- **Config** panel: the `.env` as a form generated from the file, Save button coloured by the impact
  (restart / rebuild / wipe db), the matching action proposed afterwards; `.env` watched for changes
  made outside the hub.
- **First start** wizard for a new copy (paths pre-filled from a sibling project, addons, database);
  Odoo waits until the setup is confirmed.
- Every action carries a per-process token; the page is pushed over server-sent events.

### Images and versions

- Images are shared between projects and tagged by stack and by the revision of the Dockerfiles
  (`odoo-env/odoo:19.0-py3.12-latest-<rev>`, `odoo-env/db:17`, `odoo-env/utils:<rev>`); `docker compose
  up` never rebuilds an existing image, `rebuild` builds only the missing ones and recreates the
  containers (seconds). Images unused for `IMAGE_RETENTION_DAYS` are pruned automatically (daily).
- Two-stage Odoo image (no compiler in the final image), utils image without Node.js (the web
  terminals are a versioned xterm.js bundle served by a stdlib Python server).
- Nightly builds: `ODOO_BUILD=latest` or a date, `rebuild -n`, newer-nightly hint in the status bar.
- `pull` puts the `ENTERPRISE_PATH` / `ODOO_PATH` repos on the `ODOO_VERSION` branch at the commit of
  the build; **start guard**: Odoo refuses to start on a mismatched series.
- `.data/compat.map` validated by the hub and `rebuild`.

### Commands

- New: `test` (throwaway database, `--coverage`), `debug` (debugpy + `.vscode/launch.json`), `watch`
  (auto `u` on manifest save), `pull`, `env-update`.
- `db restore`: from `./db_files/` only (`-F FILE`, picker, `--last`); the URL / master-password mode
  is gone. Restored dumps are neutralized and anonymized by default (`-na` to skip). `db backup --keep N`,
  `db clone`, `db drop -f`, multi-db mode (`SELECTED_DB` empty).
- `update -w` / `reboot -w` / `start -w` wait for the start and report its errors (exit 2);
  `update -d DB|all`.
- Removed from the utils shell: `conf` (`set`), `status`, `check_versions`, `i18n-export` (merged into
  `translation`) — status and settings live in the hub; the plain backends stay in
  `.data/scripts/internal/` for agents and scripts. The proxy, the MCP server and the image pruning
  are always on, without a command.
- Global flags on every command: `-y`, `-p` (side pane), `--no-color`. Long commands open a side pane by
  themselves once their arguments are valid; usage errors and `--help` stay in the prompt; a finished
  pane is closed by the next command.
- Help and usage texts rewritten; completion for every command, module and database name.

### Agents

- MCP server per project (Streamable HTTP, always on, `http://<name>.mcp.docker.localhost/mcp`):
  `odoo_*`, `db_*`, `conf_set`, `odoo_test`, `odoo_model_info`, `odoo_xmlid`, prompts `migrate_module`
  and `debug_error`; `/status` and `/health`.
- `AGENTS.md` at the root of each copy.

### Environment

- One palette (`.data/scripts/lib/theme.sh`) for the hub, the terminals, tmux, the prompt and the
  command output; the `.data/themes/` files and `.config/*/theme.conf` are gone. The primary colour is per project
  (`PROJECT_COLOR`, or picked from the name without colliding with another project).
- The utils shell is owned by the environment (`.data/scripts/zshrc.sh`); `.config/utils/.zshrc` is now
  the user's file for personal aliases (an old generated one is replaced by `env-update`).
- Status daemon `status.py` (Engine API, no `docker` CLI) feeding the tmux bars, the hub and `/status`.
- Mail catcher (Mailpit, `COMPOSE_PROFILES=mail`) wired into `odoo.conf` and every dev database.
- ssh keys of the host detected at the first start (`SSH_PATH`); only the keys and `known_hosts` are
  copied into the utils container.
- `env-update` keeps a copy in sync with the template (or a local copy with `--from`), merges `.env`,
  restarts the hub / MCP server when their files changed; releases announced by the hub.
- A project copy keeps only what runs it: the copied `.git`, `README*`, `CHANGELOG.md`, `docs/` and the
  template `.gitignore` are removed at its first start (and by `env-update`); `addons/` is never touched.
- `.config/terminal.conf` replaces `web-terminal.conf` / `theme.conf`; `odoo.conf.template` is gone
  (`odoo.conf` is edited in place at start).
- End-to-end test `.data/tests/env_test.sh` and `hub_test.py`.

## 3.x

Single project per machine (`odoo_dev`, `odoo.docker.localhost`), per-project Traefik, themes in
`.data/themes/`, Node.js web terminal, no hub, no MCP server.
