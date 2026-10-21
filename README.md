# Odoo Development Environment

🇬🇧 English · 🇫🇷 [Français](README.fr.md) · 🤖 [Agents (MCP)](AGENTS.md) · 📝 [Changelog](CHANGELOG.md)

Fast Docker environment for Odoo development: Odoo restarts in ~2 seconds, every version from
14.0 to latest is one `.env` change away, several projects run side by side behind one shared
proxy with a hub page, and everything is driven by a handful of commands from the **utils**
terminal — usable by humans and by AI agents (MCP).

![Hub](docs/hub.png)

- [Features](#features)
- [Quick start](#quick-start)
- [How it works](#how-it-works)
- [The hub](#the-hub)
- [The terminals](#the-terminals)
- [Commands](#commands)
- [AI agents (MCP)](#ai-agents-mcp)
- [Configuration](#configuration)
- [Images and versions](#images-and-versions)
- [Keeping a project up to date](#keeping-a-project-up-to-date)
- [Debugging with Cursor / VS Code](#debugging-with-cursor--vs-code)
- [Layout of the repository](#layout-of-the-repository)
- [Troubleshooting](#troubleshooting)

## Features

- **Instant restarts**: Odoo runs in a tmux pane, `u my_module` restarts it with `-u` in ~2s; `u -w` waits and reports the errors of the start
- **Version switching**: `ODOO_VERSION` / `PYTHON_VERSION` / `POSTGRES_VERSION` in `.env` (hub **Config** panel), then `rebuild`
- **Shared images**: tagged by stack and by the revision of the Dockerfiles (`odoo-env/odoo:18.0-py3.10-latest-94f22b6c`) and reused by every project — switching 19 → 18 → 19 never rebuilds twice, and a project never runs an image built from other files; the ones unused for `IMAGE_RETENTION_DAYS` are removed automatically
- **Nightly builds**: `ODOO_BUILD=latest` or a date; `rebuild -n` refreshes the nightly, the status bar tells you when a newer one exists
- **Several projects at once**: each project is named after its folder (`aec`, `wms`…) behind one shared proxy; **`http://odoo.docker.localhost`** shows a tab per project (live Odoo / DB / Enterprise status dots, Odoo / Logs / Utils / Mail / MCP / Config menu, stopped projects can be started from there, tabs reorder by drag and drop, `Alt+1..9` switches tabs)
- **First start wizard**: a new project copy is configured from the hub (paths, addons, database) — nothing to edit by hand
- **Mail catcher**: every outgoing mail lands in Mailpit (`http://<name>.mail.docker.localhost`), including from restored dumps
- **Debugger**: `debug on` runs Odoo under debugpy and writes the `.vscode/launch.json` to attach Cursor / VS Code
- **Kept up to date**: `env-update` refreshes the environment files of a project from the template repository; the hub flags new releases
- **Web terminals**: Odoo logs and the utils shell in the browser (xterm.js, one colour palette for everything)
- **Database toolbox**: backup, restore + sanitize (neutralize / anonymize), clone, drop, select, multi-db mode
- **Tests**: `test my_module` runs the module tests on a throwaway database (`--coverage` for a report); `watch on` auto-updates a module when its manifest is saved
- **Side panes**: long commands (`rebuild`, `test`, `db restore`, `translation`…) and interactive ones (`shell`, `psql`) open by themselves in a tmux side pane; `-p` does it for any other command
- **AI ready**: always-on MCP server per project, `-y` / `NO_COLOR` on every command, readiness report of `u -w` (see [`AGENTS.md`](AGENTS.md))
- **Auto addon discovery**: nested addons folders, `requirements.txt` installed at start, ssh keys of the host detected for private repos

## Quick start

### 1. Copy the environment

One copy per project. The folder name becomes the project name (`./19/_AEC` → `aec`, lowercased,
without the leading `_`): prefix of the containers (`aec_odoo`, `aec_utils`, `aec_db`) and of the
URLs (`aec.odoo.docker.localhost`). Put your modules under `addons/`.

### 2. Start

```bash
docker compose up -d
```

Nothing to edit for a first try: Odoo waits, and the hub (`http://odoo.docker.localhost`) opens a
**first start** dialog for the project — enterprise / odoo source paths (pre-filled from a sibling
project of the same version when one exists, empty = Community), addons path, database — then writes
`.env`, marks the setup done (`.data/volumes/shared/.setup_done`) and starts the stack. Later changes
go through **Config** in the hub. By hand, the keys that matter:

```bash
ODOO_VERSION=19.0
PYTHON_VERSION=3.12
POSTGRES_VERSION=17
ADDONS_PATH=./addons
ENTERPRISE_PATH=../enterprise      # optional
SELECTED_DB=main
```

Secrets (`ENTERPRISE_KEY`, `NGROK_KEY`, `GITHUB_TOKEN`) go in the git-ignored `.env.secrets`.

### 3. Use

| Service | URL | What |
|---------|-----|------|
| **Hub** | http://odoo.docker.localhost | one tab per project, each with an Odoo / Logs / Utils / Mail / MCP / Config menu — the only URL to remember |
| Odoo    | http://`<name>`.odoo.docker.localhost  | this project's Odoo |
| Logs    | http://`<name>`.logs.docker.localhost  | live Odoo logs (tmux pane, read-only) |
| Utils   | http://`<name>`.utils.docker.localhost | the commands below |
| MCP     | http://`<name>`.mcp.docker.localhost/mcp | MCP server for AI agents |
| Mail    | http://`<name>`.mail.docker.localhost  | outgoing mails caught by Mailpit (`COMPOSE_PROFILES=mail`) |
| Traefik | http://traefik.docker.localhost        | dashboard of the shared proxy (routers, services) |

In the utils terminal: `u my_module` after a code change, `db restore my_db` to load a customer dump,
`test my_module` to run its tests, `help` for the rest.

## How it works

### One stack per project, one proxy for all

```
docker compose up -d  (project aec)            docker compose up -d  (project wms)
┌──────────────────────────────────┐           ┌──────────────────────────────────┐
│ aec_db      PostgreSQL           │           │ wms_db                           │
│ aec_odoo    Odoo in a tmux pane  │           │ wms_odoo                         │
│ aec_utils   commands, MCP, status│           │ wms_utils                        │
│ aec_mail    Mailpit (optional)   │           │ wms_mail                         │
└───────────────┬──────────────────┘           └───────────────┬──────────────────┘
                │ network odoo_proxy                           │
         ┌──────┴───────────────────────────────────────────────┴──────┐
         │ odoo_proxy_traefik   *.docker.localhost → the right container│
         │ odoo_proxy_hub       http://odoo.docker.localhost            │
         └─────────────────────────────────────────────────────────────┘
```

- **db**: PostgreSQL, data in `.data/volumes/db-container/pgdata` (bind mount in the project folder).
- **odoo**: the Odoo server of the chosen version, started in a tmux pane by `odoo_runner.sh`
  (command built from `.env`: `-d SELECTED_DB`, `ODOO_ARGS`, debugpy), filestore and sessions in
  `.data/volumes/odoo-container/odoo`. Your `ADDONS_PATH` is mounted at `/mnt/extra-addons`,
  `ENTERPRISE_PATH` at `/mnt/enterprise-addons`, `ODOO_PATH` at `/opt/odoo` (read-only mirror for
  module discovery and `upgrade-code`). The environment scripts are mounted, not baked into the image.
- **utils**: the toolbox — the commands, a zsh shell in tmux, the MCP server (port 8300 inside, served
  by the proxy), the status daemon (`status.py`) that feeds the tmux status bars and the hub, the web
  terminals (`.data/web-terminal/server.py`, stdlib Python). It talks to Docker through the socket
  (`docker exec` into odoo / db, `docker compose` for `rebuild`).
- **mail** (`COMPOSE_PROFILES=mail`): Mailpit; the odoo entrypoint points `smtp_server` / `smtp_port`
  of `odoo.conf` to it and every `ir.mail_server` of the dev databases is rewritten to it at each start.
- **odoo_proxy** (`.data/proxy/`): Traefik (ports 80 and 8080 on `127.0.0.1` only) and the hub. Started
  by the first project that comes up (`ensure_proxy` in the utils entrypoint), shared by all of them,
  never stopped by a project's `docker compose down`. Each project's containers carry Traefik labels
  (`<project>-odoo|logs|utils|mcp|mail` routers), nothing else to configure.
- **odoo_env_meta** (Docker volume shared by every project): the registry of the projects seen on this
  machine (`projects/<name>` = host folder), the colour taken by each (`colors/`), the journal of the
  hub actions (`journal/`), the step of a running `rebuild` (`progress/`), the last use of each image
  (`last_used/`) and `prune.log`.

### Start, restart, update

`start` / `reboot` / `update` (aliases `s` / `r` / `u`) never recreate a container: they respawn the
Odoo pane with `odoo_runner.sh [-d DB] [-u MODULES]`, which prints a start header (addons paths,
modules, database), runs the **start guard** (`odoo_guard.sh`: refuses to start when a mounted
`ENTERPRISE_PATH` / `ODOO_PATH` is on another series than `ODOO_VERSION`, since a wrong series loaded
with `-u` corrupts the database) and `exec`s Odoo. That is why a restart takes ~2 s. `stop` sends
SIGKILL (dev environment, fastest possible). `-w` waits for the "HTTP service running" line and prints
the tracebacks of this run, if any — the same report the MCP `odoo_update` tool returns.

Before each start, `dev_db_bootstrap.sh` sets the dev defaults on the database(s) about to be served
(`report.url`, no database expiration, mail server to Mailpit).

### Status

`status.py --loop` (utils) reads the containers through the Engine API every 2 s and writes
`/var/shared/status.json` (`.data/volumes/shared/`): versions, rebuild / nightly / release alerts,
service pills (MCP / ODOO / ENT / DB / database), `.env` keys changed since the containers were created.
The tmux status bars of both terminals and the hub tabs render that file; the MCP server serves it on
`/status`. One process, no `docker` CLI, slow values cached (installed build, nightly, enterprise
series, template release).

## The hub

`http://odoo.docker.localhost` is the single page of the environment: one tab per project seen on this
machine, running or not. The page receives its state over server-sent events (`/api/events`): nothing
to refresh, ever.

### Tabs

![Tabs](docs/hub-tabs.png)

- **Number and name** in the project's colour (see [Appearance](#the-terminals)); the number is the
  `Alt+<n>` shortcut. The active tab also sets the **favicon** (a letter on the project's colour) and
  the **title** of the browser tab (`AEC · UTILS`, prefixed with `⚠` when a dot is red), so the hub is
  recognizable among your other tabs even pinned.
- **`ODOO` pill**: the current view (`ODOO`, `LOGS`, `UTILS`, `MAIL`, `MCP`). Every opened view stays
  mounted when you switch tabs: Odoo keeps its page, the terminals keep their scrollback.
- **Three dots**: the Odoo process, PostgreSQL and Enterprise — green ok, red down / missing, orange
  Enterprise on another series than Odoo. Hover them: the tooltip gives the detail — outcome of the last
  start, MCP up / down, Enterprise version, selected database, Odoo version and build.
- **Outcome of the last start**, told apart because one blocks Odoo and the other does not: red `✖`
  (dot, flag, browser title) when the start **failed** — database not loaded, process exited — Odoo is
  not serving and the panel offers **restart odoo**; orange `⚠ N` when Odoo is up but **N errors** were
  logged during the start (a module that failed to update…). The utils status bar colours its `ODOO`
  pill the same way.
- **Progress** replaces the view pill during long actions: `starting · 0:04` while Odoo starts,
  `odoo 3/7 · 1:20` during a `rebuild` (current image, elapsed time counting live).
- **Flags** appear only when something is due:

  ![Flags](docs/hub-tab-flags.png)

  `REBUILD` — the containers do not match the `.env` (image revision, version) · blinking coloured
  flag `restart` / `rebuild` / `wipe db` — a `.env` key changed since the containers were created, even
  from an editor (the hub watches the file; the colour is the level of the action it needs) · `v4.1` —
  a newer release of the environment is published · `setup` — first start pending · `OFFLINE` —
  stopped project, dimmed tab with a **Start** action. The flags are **clickable**: each one opens the
  dialog that applies it (restart / rebuild, update env, first start wizard).
- **Order**: drag a tab to move it; the order is kept in the browser (`localStorage`), new projects
  land at the end, and `Alt+1..9` follow it. The hub reopens on the last project / view you used, and
  remembers the last view of each project.
- **Middle-click** a tab: that project's current view opens in a new browser tab (handy for a terminal
  on a second screen). `#aec/utils` in the URL bookmarks a view; `logs.` / `utils.<name>.docker.localhost`
  open the hub on that view.

![Shortcuts](docs/hub-shortcuts.png)

- **Keyboard** (when the hub page has the focus, not an iframe — click the top bar first): `Alt+1..9`
  tab by position, `Alt+←/→` previous / next running project, `Alt+V` next view of the current one,
  `Escape` closes a dialog or the Config panel.
- **TRAEFIK** opens the proxy dashboard; **+ SCAN** registers the template copies found under a host
  folder (3 levels deep) without starting them — the tabs appear stopped, ready for **Start**:

  ![Scan](docs/hub-scan.png)

### Menu of a tab

![Menu](docs/menu.png) ![Menu of a stopped project](docs/hub-menu-stopped.png)

The views, then **Config**, the **MCP** URL (opens its `/health`), a status block (versions, database,
paths), **restart odoo**, **history** (journal of the actions run from the hub; the last one and its
result are shown right in the menu entry) and **compose down** (stops the project, data kept). A stopped
project gets **Start**, **forget** (removes its tab until its next `docker compose up`; the folder is
not touched), **Config** and **history**; **update env** appears when a newer release is published.
Every destructive action asks for a confirmation that says what is kept.

Actions run `docker compose` in a throwaway `docker:cli` container (start, down, restart, first start)
or a utils command in the project's utils container (`restart odoo`, `env-update`). `rebuild` is
different: it asks questions, so the hub **types it in the project's utils terminal** — at an idle
prompt it appears immediately, while a command runs there it waits and starts when the prompt comes back
(`› hub: rebuild`).

### Config panel

![Config panel](docs/config.png)

The project's `.env` as a form **generated from the file itself**: the `# ===` / `# ---` blocks are the
sections, the comments above each key are its help text, the `#@` marker of a key gives its widget and
its badge. Nothing is hardcoded in the hub: a key you add to `.env` with the same layout gets its row.

![Badges](docs/config-badges.png)
![Toggle](docs/config-toggle.png)

- **Badges** next to a key: `rebuild` / `wipe db` (what changing it costs), `optional`, `auto` (managed
  by the environment, read-only — the image revisions for example).
- **Widgets**: toggle for `true/false` keys, text field otherwise; the current value is shown as typed in
  the file, comments and layout are preserved on save.
- **Save button**: disabled until something changed, then it counts the changes and **takes the colour
  of the heaviest action they need**:

  ![restart](docs/config-save-restart.png)
  ![rebuild](docs/config-save-rebuild.png)
  ![wipe db](docs/config-save-wipe.png)

  blue **restart** (`docker compose down` + `up -d`, data kept — applied from the hub right away),
  orange **rebuild** (version stack: typed in the utils terminal), red **wipe db** (`POSTGRES_VERSION`:
  the databases are dropped, back them up first). Once saved the matching action is proposed.
- **`.env changed` dialog**: the hub also notices a key edited outside the panel (editor, `conf_set` by an
  agent) and explains what it needs, with a **later** button that only snoozes it — the flag stays on
  the tab:

  ![.env changed](docs/hub-env-changed.png)

### First start

![First start](docs/hub-first-start.png)

A project whose `.data/volumes/shared/.setup_done` does not exist yet gets the wizard as soon as its
tab appears: paths **pre-filled from a sibling project of the same version**, addons path, database.
Odoo waits for the confirmation (its logs pane says so), so a fresh copy never starts on wrong paths.

### Security

The proxy listens on `127.0.0.1` only (ports 80 and 8080) and every hub action carries a token
generated at its start (`X-Hub-Token`): nothing on the local network can reach the terminals nor
start / stop a project.

## The terminals

![Utils terminal](docs/utils.png)
![Logs terminal](docs/logs.png)

Two tmux sessions, served in the browser by xterm.js (hub views **Logs** and **Utils**, or the bare
URLs) and reachable with `docker exec -it <name>_utils tmux attach` for a native terminal.

- **Logs** (odoo container): a logo pane and the Odoo process pane — the live server output, read-only.
  Each start prints a **header** (command line, addon paths, requirements, database) so the boundary
  between two runs is easy to find when scrolling back. When the start guard refuses to start, the
  explanation is printed there. With `ODOO_IOT_BOX=true` a third pane shows the IoT Box setup.
- **Utils** (utils container): an interactive zsh (Oh My Zsh, autosuggestions, syntax highlighting,
  Starship prompt) where the commands below are typed. `help` prints the welcome screen again (so does
  `clear`), `help <command> [sub]` its `--help` (`help db restore`).

### Typing less

![Completion](docs/term-completion.png)

- **Completion** of every command, its sub-commands and options with their description, and of the
  **module names** (`u my_mod<Tab>`, from every addons folder — the list is refreshed at each start /
  `u` / `test`, so a module added after `compose up` is known) and **database names** (`db select <Tab>`,
  `psql -d <Tab>`). `u` also accepts patterns: `u my_*` updates every module matching.
- **Suggestions**: the grey text after the cursor is the last matching command of the history, `→`
  accepts it. The `you-should-use` plugin reminds you of an alias when you type its long form.
- **Pickers**: a command missing a choice asks instead of failing — `db select` lists the databases,
  `db restore <name>` the dumps of `./db_files` (taken without asking when there is only one),
  `pre-commit` / `upgrade-code` the addons paths and modules:

  ![Picker](docs/term-picker.png)

- **Usage errors stay in the prompt**: a wrong argument prints the usage line and a `See:` hint, no pane
  opened, nothing started:

  ![Usage](docs/term-usage.png)

### Reading the result

![u -w](docs/term-update.png)

- **Prompt**: the clock at the left (live, `TERMINAL_TZ`), `took 8s528ms` after any command longer than
  a second, a red `❯` after a failure.
- **`u -w` / `r -w`**: waits for the start and reports *ready after Ns* with the count of warnings, or
  the tracebacks of this start only, followed by what to do next:

  ![u -w errors](docs/term-update-errors.png)

  The same report is what the hub's **restart odoo** and the agents' `odoo_update` get.
- **Side panes** keep the prompt free for the long commands (`rebuild`, `test`, `migrate`,
  `translation`, `upgrade-code`, `pre-commit`, `requirements`, `db restore|backup|sanitize`) and the
  interactive ones (`shell`, `psql`, `grok`, `watch`):

  ![Side pane](docs/term-side-pane.png)

  the pane opens **once the arguments are valid** (a usage error or `--help` stays in the prompt),
  **closes by itself on success** (`done · closing`) and **stays open on error or warning**
  (`done (exit 1) · press any key to close`) so the output is read before it goes; a pane left open is
  closed when the next command starts. A second pane of a command still running gets a suffix
  (`test·2`). `-p` opens a pane for any other command (`db list -p`). Without a terminal (agents,
  `docker exec`, pipes) everything runs inline, and the confirmations fail instead of hanging.
- **Commands handed over by the hub** (`rebuild` after a `.env` change) are typed in this terminal so
  their confirmations are answered where you are: right away at an idle prompt, or queued and started
  with a `› hub:` prefix when the running command returns.

### Status bar

![Status bar, left](docs/term-statusbar-left.png) ![Status bar, right](docs/term-statusbar-right.png)

Left: the versions of the stack (Odoo and build, Python, PostgreSQL) and the alerts — `⇡` a newer
nightly exists (`rebuild -n`), `rebuild` the containers lag behind `.env`, `v4.1` a newer release.
Right: the pills **MCP** (server answering), **ODOO** (process up; red while it restarts), **ENT**
(Enterprise mounted and on the same series), **DB** (PostgreSQL up), the selected database (`multi-db`
when none), then the date and the clock. Both terminals show the same bar; it refreshes by itself.

### Mouse and clipboard

- The **wheel** scrolls the history (tmux copy-mode, `q` or scroll back down to leave), a **drag**
  selects and **copies to the system clipboard** when released (OSC 52 through xterm.js — nothing to
  install, works in the browser and over `docker exec -it … tmux attach`).
- Clicks and wheel on the **logo pane** are redirected to the main pane: the logo never steals the focus.
- `.config/terminal.conf`: font and size, cursor shape / blink, scrollback length, applied to both
  terminals at the next `docker compose up`.

### Appearance

One palette for the hub, the terminals, tmux, the prompt and the command output
(`.data/scripts/lib/theme.sh`, hub `.data/proxy/static/hub.css`); only the **primary colour** is per
project — hashed from its name, the next free palette colour when another project of this machine
already shows it, or `PROJECT_COLOR` in `.env` (a palette name or `#rrggbb`). It colours the hub tab,
the favicon, the logos and the prompt of that project, so two terminals side by side are never
confused. Prompt in `.config/utils/starship.toml`, personal zsh aliases in `.config/utils/.zshrc`
(sourced after the environment's `zshrc.sh`, never overwritten).

## Commands

Type `help` in the utils terminal for the overview and `help <command> [sub]` (or `<command> --help`)
for details. Every command (except `psql` / `pip`, which forward their arguments) accepts the **global
flags**:

| Flag | Effect |
|------|--------|
| `-y`, `--yes` | answer yes to every confirmation (mandatory when no terminal is attached: a prompt without a tty fails instead of hanging) |
| `-p`, `--pane` | run the command in a new side pane of the utils terminal and keep working (see [The terminals](#the-terminals)) |
| `--no-color` | plain output (automatic when piped or `NO_COLOR` is set) |

Exit codes: `0` ok, `1` error, `2` with `-w`: Odoo started **with errors** (the report lists them).

### Odoo

| Command | Alias | Description |
|---------|-------|-------------|
| `update [-k] [-w] [-d DB] MODULES` | `u` | Restart Odoo with `-u MODULES` (comma list, patterns `my_*`, `all`). `-k` saves the list as `ODOO_UPDATE` so a bare `u` reuses it; `-w` waits for readiness and reports errors; `-d` picks the database(s) (`all` = every Odoo DB) — asked when `SELECTED_DB` is empty |
| `reboot [-w]` | `r` | Restart Odoo without module update |
| `start [-w]` | `s` | Start Odoo if stopped |
| `stop` | | Stop Odoo (SIGKILL, instant) |
| `shell [db]` | | Odoo shell (IPython: completion, history, `obj?`) in a side pane |
| `test [-t TAGS] [--on DB] [--keep] [--no-demo] [--coverage] [-v] <modules>` | | Run the module tests (`--test-enable`) on a throwaway `test_<module>_<time>` DB — fresh with demo data and `-i`, or a clone of `--on DB` with `-u` — then drop it. The running Odoo is untouched; exit 1 if a test failed; full log in `.data/volumes/shared/tests/`. `--coverage` prints the coverage of the tested modules and writes an HTML report under `.data/volumes/odoo-container/odoo/coverage/` |
| `debug [on\|off]` | | Run Odoo under **debugpy** and write `.vscode/launch.json` (`Attach: Odoo (<name>)`, path mappings for your addons, Odoo and Enterprise). The port is published on a free host port (or `DEBUGPY_PORT`); `debug` alone shows it. `DEBUGPY=true` persists across `r` / `u` |
| `watch [on\|off]` | | Side pane that runs `u <module> -w` each time a `__manifest__.py` under `addons/` is saved (only manifests trigger it). Persisted as `AUTO_UPDATE` in `.env`, reopened on `compose up` |
| `logs [LEVEL] [-g PATTERN]` | | Records of the **current run** at `LEVEL` and above (`DEBUG`, `INFO`, `WARNING` — default —, `ERROR`, `CRITICAL`), tracebacks included, in a side pane: `logs error` after a `u`, `logs info -g my_module`. The live log stays in the hub's Logs tab |

### Database (`db`)

| Command | Description |
|---------|-------------|
| `db` | Overview: selected DB and the list |
| `db list` | Databases with size and Odoo version, selected one marked ●, then the backups of `./db_files/` |
| `db select [name]` | Set `SELECTED_DB` and reboot Odoo (picker when omitted; confirms creation if the DB does not exist) |
| `db drop [-f] <name>` | Drop a DB and its filestore. `-f` resets the **selected** DB (stop → drop → start on a fresh one) |
| `db clone [-f] <src> <dst>` | Copy a DB (and filestore); `-f` replaces `dst` |
| `db backup [-fs] [--keep N] [name]` | Zip to `./db_files/<name>_<date>.zip`; `-fs` includes the filestore; `--keep N` keeps only the N most recent backups of that database |
| `db restore [-s] [-f] [-na] [-F FILE \| --last] <name>` | Restore a backup from `./db_files/` into `<name>` (created, or replaced only if it exists), then neutralize + anonymize. `-s` selects it, `-na` skips sanitizing, `-F` picks the file non-interactively (when `./db_files/` holds a single backup it is taken without asking), `--last` takes the most recent backup of `<name>` |
| `db sanitize [-a] [-F [FILE]] [name]` | Neutralize (crons, mail, payment…) and/or anonymize (emails → `@test.test`, admin/admin) a DB or a backup file |

Supported backup formats: `.sql`, `.dump`, `.zip`, `.7z`, `.tar.gz` (Odoo layout with `filestore/` is
handled). Restore and clone pause Odoo when it may hold the database (multi-db mode) and start it again.

### Project

| Command | Description |
|---------|-------------|
| `rebuild [-a] [-n] [-nc]` | Build the images missing for the `.env` stack and recreate the containers on them (seconds when they exist); `-n` rebuilds the odoo image on the latest nightly, `-a` rebuilds both, `-nc` without the build cache; pulls the repos first; the hub tab shows each build step; `docker compose` keeps working from the host afterwards |
| `pull [odoo\|enterprise] [--build DATE\|latest] [-f]` | Git repos of `ENTERPRISE_PATH` / `ODOO_PATH` → `ODOO_VERSION` branch, at the commit of the nightly `ODOO_BUILD` (or the tip with `latest`) |
| `env-update [-n] [--ref REF \| --from PATH]` | Refresh the environment files of this project from the template repository (`ENV_TEMPLATE_REPO` / `ENV_TEMPLATE_REF` in `.env`) or a local copy (`--from`) — see [Keeping a project up to date](#keeping-a-project-up-to-date). `-n` previews |
| `requirements` | Install addons `requirements.txt` in the Odoo venv |
| `pip <args>` | pip inside the Odoo venv |
| `psql [-d db] [psql args]` | PostgreSQL shell / one-shot queries |

### Code

| Command | Alias | Description |
|---------|-------|-------------|
| `translation MODULES\|--all [-l LANG\|-L] [--pot]` | | Re-export `i18n/*.po` of your modules (picker when no argument; `-L` every language found) |
| `pre-commit [FOLDER] [-a]` | `pc` | Run the hooks of `.config/.pre-commit-config.yaml` (kept in sync as `addons/.pre-commit-config.yaml` — ignore it in your addons repository — so your IDE sees the same hooks) |
| `upgrade-code --from VER [--to VER] [--module M] [--dry-run]` | | Migrate module code with Odoo's `upgrade_code` scripts plus the ones of `.data/migration_scripts/` (Odoo 19+ runtime required) |
| `migrate <db> <version>` | | Upgrade a DB through upgrade.odoo.com (`ENTERPRISE_KEY`) |

### Other

| Command | Description |
|---------|-------------|
| `grok` | ngrok tunnel to Odoo in a side pane (`NGROK_KEY`) |
| `help [command]` | Overview or detailed help |
| `bash .data/tests/env_test.sh` (host) | Self-test of the environment: two throwaway copies behind the proxy, hub, URLs, MCP, mail, main commands, then teardown (`-1` single project, `-k` keep, `--clean`); `python3 .data/tests/hub_test.py` tests the hub's `.env` parser |

### Always-on services

Some things that used to be commands are now automatic: the **proxy** starts with the first project,
the **MCP server** with the utils container (red **MCP** pill when down, log in
`.data/volumes/shared/mcp.log`), unused shared images are **pruned** daily (`IMAGE_RETENTION_DAYS`),
the **status** and the **settings** live in the hub (tab flags, Config panel). Agents and scripts keep
the plain backends under `.data/scripts/internal/` (`status.sh`, `conf.sh`, `logs.sh`,
`check_versions.sh`) — see [`AGENTS.md`](AGENTS.md).

## AI agents (MCP)

The utils container runs an MCP server (Streamable HTTP, started with the container, served by the
proxy at `http://<name>.mcp.docker.localhost/mcp`) exposing the commands above as tools:
`odoo_status`, `odoo_update`, `odoo_restart` / `odoo_start` / `odoo_stop`, `odoo_wait_ready`,
`odoo_logs` (`level` = records of the current run at that level and above), `odoo_logs_since`, `odoo_shell` / `odoo_shell_commit`, `odoo_test` (with `coverage`),
`odoo_model_info`, `odoo_xmlid`, `odoo_module_list`, `db_list` / `db_select` / `db_backup` /
`db_restore` / `db_drop` / `db_clone` / `db_query`, `conf_set`, `check_versions`, `repos_pull`,
`translation_export`, `pre_commit`, `requirements_install` — plus two prompts (`migrate_module`,
`debug_error`). `/status` serves the live `status.json` of the project (used by the hub), `/health`
answers `ok`. Client configuration (Cursor `~/.cursor/mcp.json`, Claude Desktop):

```json
{ "mcpServers": { "odoo-<name>": { "url": "http://<name>.mcp.docker.localhost/mcp" } } }
```

Agents without MCP can call the scripts directly:

```bash
U="docker exec -u utils <name>_utils bash /home/utils/odoo_custom_docker/.data/scripts"
$U/commands/update.sh -y -w my_module      # restart with -u, wait, exit 2 if errors
$U/internal/logs.sh -e                     # tracebacks of the current run
$U/commands/test.sh -y my_module           # tests on a throwaway DB
```

Everything an agent needs to know is in [`AGENTS.md`](AGENTS.md).

## Configuration

### `.env`

The file is organised in sections (`# ===`) and sub-sections (`# ---`), each key preceded by its help
lines and a marker line `#@ apply=r|compose|rebuild [wipe=db] [type=bool] [auto] [optional]` that
says how a change is applied; the hub's Config panel and its flags are generated from it — keep the
layout when adding a key. Runtime values (`SELECTED_DB`, `ODOO_UPDATE`, `ODOO_ARGS`, `DEBUGPY`,
`AUTO_UPDATE`) are applied by the next Odoo start (`r`), the mounts and profiles by `docker compose up -d`,
the version stack by `rebuild`.

| Variable | Default | Description |
|----------|---------|-------------|
| `ODOO_VERSION` | `19.0` | 14.0 … 19.0 (`rebuild` to apply) |
| `ODOO_BUILD` | `latest` | Nightly build date (YYYYMMDD) or `latest` |
| `PYTHON_VERSION` | `3.12` | Must be compatible with the Odoo version (`.data/compat.map`) |
| `POSTGRES_VERSION` | `17` | Must be compatible; changing it wipes the databases |
| `IMAGE_RETENTION_DAYS` | `30` | Days before an unused shared image is removed (checked at start and daily; 0 = keep them all) |
| `ADDONS_PATH` | `./addons` | Your addons (`/mnt/extra-addons` in the container) |
| `ENTERPRISE_PATH` | | Enterprise addons (empty = Community) |
| `ODOO_PATH` | | Odoo source on the host (module discovery, `upgrade-code`, debugger mappings) |
| `SSH_PATH` | | Host `~/.ssh` mounted read-only in utils (`pull` over ssh). Empty = detected at the first start: the `~/.ssh` of the user owning the project folder when it holds a key, written here for the next `docker compose up -d`. Only the keys and `known_hosts` are copied for the utils user — the host `ssh config` stays out of the container |
| `SCAN_SUBFOLDERS` | `true` | Discover modules in nested folders |
| `IGNORED_PATH` | | Folders excluded from the scan |
| `SELECTED_DB` | `main` | Active database (`db select`). Empty = **multi-db mode**: Odoo starts without `-d`, the database is chosen in the web selector (`/web/database/selector`, `?db=`). Commands that need one (`u`, `shell`, `psql`, `translation`, `db backup/sanitize`, `watch`) then ask which, `u` also offers `all`; Odoo serves only the updated database(s) until the next `r`. Restore / clone pause Odoo since any database may be loaded; crons run on every database (restored ones are neutralized) |
| `ODOO_UPDATE` | | Modules updated by a bare `u` / `start` (`u -k`) |
| `ODOO_ARGS` | | Extra Odoo arguments, e.g. `--dev xml` |
| `AUTO_UPDATE` | `false` | Auto-update watcher pane (`watch on` / `watch off`) |
| `DEBUGPY`, `DEBUGPY_PORT` | `false`, | Odoo under debugpy (`debug on/off`); empty port = a free host port chosen by Docker, never conflicting between projects |
| `COMPOSE_PROFILES` | `mail` | `mail` runs the Mailpit container. Empty disables it (`docker compose up -d` to apply) |
| `ODOO_WS_PORT` | `8069` | Port Traefik routes `/websocket` to: `8069` in threaded mode, `8072` with `--workers` |
| `PROJECT_COLOR` | | Colour of the project (hub tab, terminal titles, prompt, cursor): a palette name (`yellow cyan red purple green orange blue fg`) or `#rrggbb`. Empty = picked from the name, another one when a project of this machine already has it (written here then) |
| `COMPOSE_PROJECT_NAME` | | Project name: empty = folder name (`./19/_AEC` → `aec`). Set it only when two folders share a name |
| `ENV_TEMPLATE_REPO`, `ENV_TEMPLATE_REF` | template URL, | Repository / branch `env-update` refreshes the environment from (empty ref = default branch of the repository) |
| `ODOO_IOT_BOX` | `false` | Built-in IoT Box mode (Odoo 19+): `iot_drivers` loaded, CUPS virtual printers, setup pane in the logs terminal |
| `ODOO_IMAGE_REV`, `UTILS_IMAGE_REV` | auto | Revision of the Dockerfiles (+ web terminal), part of the image tags. Written by the utils container at start and by `rebuild`: do not edit |
| `ENTERPRISE_KEY`, `NGROK_KEY`, `GITHUB_TOKEN` | | Secrets — put them in `.env.secrets` (`GITHUB_TOKEN`: `pull` on https remotes) |

### Paths

Paths are relative to `docker-compose.yml`:

```
project/
├── docker-compose.yml
├── addons/
│   ├── my_module/
│   └── custom-addons/        # nested folders are scanned (SCAN_SUBFOLDERS=true)
│       └── other_module/
└── ../enterprise/
```

```bash
ADDONS_PATH=./addons           # Same directory
ENTERPRISE_PATH=../enterprise  # Parent directory
```

Every folder holding a `__manifest__.py` is a module; `generate_addons_path.sh` rewrites
`addons_path` in `odoo.conf` at each start and `check_requirements.sh` installs the `requirements.txt`
found under `ADDONS_PATH`. The module list (`.data/volumes/odoo-container/cache/.modules_list`) feeds
the completion and the `u` patterns; it is refreshed on every `u`.

### Configuration files

| File | Description |
|------|-------------|
| `.config/odoo.conf` | Odoo server configuration (`addons_path`, `smtp_*` are rewritten at startup) |
| `.config/terminal.conf` | Web terminals: font, cursor, scrollback, time zone |
| `.config/utils/starship.toml` | Prompt of the utils shell (`${THEME_*}` placeholders) |
| `.config/utils/.zshrc` | Your aliases and functions for the utils shell (sourced after the environment's `zshrc.sh`) |
| `.config/.pre-commit-config.yaml` | Hooks used by `pre-commit` / `upgrade-code` |
| `.data/scripts/lib/theme.sh` | The palette (hub, terminals, tmux, prompt, command output) |
| `.data/compat.map` | Odoo / Python / PostgreSQL compatibility (read-only) |

`.config/odoo.conf`:

```ini
[options]
admin_passwd = odoo          ; Master password
without_demo = True          ; Disable demo data
; workers = 0                ; Number of workers (0 = disabled)
; limit_memory_hard = 2684354560
; limit_time_real = 120
```

`.config/terminal.conf`:

```bash
WEBTERM_FONT_FAMILY='"JetBrainsMono Nerd Font", Consolas, Menlo, Ubuntu, monospace'
WEBTERM_FONT_SIZE=15
TMUX_CURSOR_STYLE=bar        # block, underline, bar
TMUX_CURSOR_BLINK=true
TMUX_SCROLLBACK=50000
TERMINAL_TZ=Europe/Paris     # clocks: status bar, prompt, utils shell
```

> Fonts are rendered client-side (browser). For Nerd Font icons (Starship prompt), install a Nerd Font locally:
> - **Linux**: `wget https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.zip && unzip JetBrainsMono.zip -d ~/.local/share/fonts && fc-cache -f`
> - **macOS**: `brew install font-jetbrains-mono-nerd-font`
> - **Windows**: download from https://www.nerdfonts.com/

Changes to `terminal.conf`, `starship.toml` or the palette take effect after `docker compose restart
<container>`; `odoo.conf` after `r`.

## Images and versions

Images are independent from the project and tagged by stack **and by the content of the Dockerfiles**
(8 hex chars of `.data/scripts/image_rev.sh`), so every project on the same versions and the same
environment files shares them, `docker compose up` never rebuilds an image that exists, and a project
whose Dockerfiles changed (after `env-update`) gets its own tag instead of silently reusing — or being
orphaned by — another project's image. Entrypoints and scripts are mounted, not baked, so most changes
need no rebuild at all. The Odoo image is built in two stages (compilers and headers stay in the
builder; the final image has only the runtime libraries, the interpreter and the venv) and the utils
image carries no Node.js: the web terminals are a versioned xterm.js bundle served by a stdlib Python
server. `pip` / `requirements` install wheels in the Odoo container; a package that must be compiled
goes in the Dockerfile.

| Service | Image |
|---------|-------|
| odoo | `odoo-env/odoo:<ODOO_VERSION>-py<PYTHON_VERSION>-<ODOO_BUILD>-<rev>` (e.g. `odoo-env/odoo:19.0-py3.12-latest-94f22b6c`) |
| db | `odoo-env/db:<POSTGRES_VERSION>` |
| utils | `odoo-env/utils:<rev>` |

`ODOO_BUILD=latest` means the nightly of the day the image was built: a newer nightly never forces a
rebuild (the status bar `⇡` mentions it; `rebuild -n` refreshes). Each start records the images a
project uses in the shared `odoo_env_meta` volume; the ones unused for `IMAGE_RETENTION_DAYS` are
removed automatically (at start, then daily, `prune.log` in the volume).

### Changing the Odoo version

1. `ODOO_VERSION=18.0` in the hub's **Config** panel (and `PYTHON_VERSION` / `POSTGRES_VERSION` if
   needed — the combination is validated against `.data/compat.map`)
2. `rebuild` (runs in a side pane, keep working meanwhile) — builds the `18.0` images only if no project
   built them yet, switches the git repos in `ENTERPRISE_PATH` / `ODOO_PATH` to the `18.0` branch, and
   recreates the containers. `docker compose` keeps working from the host afterwards (the build runs in a
   throwaway container that sees the project at its host path).

Compatibility (`.data/compat.map`, default first):

| Odoo | Python | PostgreSQL |
|------|--------|------------|
| 19.0 | 3.12, 3.13, 3.11, 3.10 | 17, 16, 15, 14, 13 |
| 18.0 | 3.12, 3.13, 3.11, 3.10 | 17, 16, 15, 14, 13, 12 |
| 17.0 | 3.10, 3.13, 3.12, 3.11 | 16, 15, 14, 13, 12 |
| 16.0 | 3.10, 3.12, 3.11, 3.9, 3.8, 3.7 | 15, 14, 13, 12, 11, 10 |
| 15.0 | 3.10, 3.12, 3.11, 3.9, 3.8, 3.7 | 14, 15, 13, 12, 11, 10 |
| 14.0 | 3.8, 3.10, 3.9, 3.7, 3.6 | 13, 12, 11, 10 |

## Keeping a project up to date

Every project is a standalone copy with its own git repository. `env-update` (utils) fetches the
template (`ENV_TEMPLATE_REPO` / `ENV_TEMPLATE_REF`, or a local working copy with `--from <host path>`),
shows what changed in the environment files and applies it:

- **Replaced**: `.data/` (except `volumes/`, `host_project_path.map`), `docker-compose.yml`,
  `.dockerignore`, `AGENTS.md`.
- **Removed**: `README.md`, `README.fr.md`, `CHANGELOG.md`, `docs/`, `.gitignore` — they belong to the
  template repository and are dropped from a project copy (the utils container does it at its first
  start, with the copied `.git`; `addons/` and its own `.gitignore` are never touched).
- **Merged**: `.env` — values kept, new keys appended with their help comments, obsolete ones reported.
- **Added only**: `.config/` (new files; an old generated `.config/utils/.zshrc` is replaced by the
  comment-only user file).
- **Never touched**: `addons/`, `db_files/`, `.env.secrets`, data volumes.

Review with `git diff`, commit, then follow the printed next steps: `rebuild` when a Dockerfile changed
(the image tag changes with it), `docker compose up -d` when the compose file changed. The hub and the
MCP server are restarted by the command itself when their files changed (in the background, log in
`.data/volumes/shared/env-update.log`). `.data/.template_rev` records the template commit so the next
run also removes files the template dropped. `-n` previews without writing.

**Releases.** `.data/VERSION` is the release of the environment (`4.0.1`, see
[`CHANGELOG.md`](CHANGELOG.md)). Every hour the status loop compares it with the template's on
`ENV_TEMPLATE_REF` (empty = the repository's default branch, i.e. the current release line — `v4`);
when a newer one is published, the tab shows a `v4.1` flag and the hub proposes **update env** (runs
`env-update -y` in utils, shows its report, then offers the restart when the compose file changed). To
publish: bump `.data/VERSION`, commit, push to the release branch (make it the default branch of the
repository, or set `ENV_TEMPLATE_REF` in the projects).

## Debugging with Cursor / VS Code

```
debug on            # Odoo restarts under debugpy, .vscode/launch.json gets "Attach: Odoo (<name>)"
```

Open the project folder in the IDE, set breakpoints in your addons, run that configuration (F5): the
path mappings cover `ADDONS_PATH` → `/mnt/extra-addons`, `ODOO_PATH` → `/opt/odoo` and
`ENTERPRISE_PATH` → `/mnt/enterprise-addons`. Breakpoints in Odoo's own code hit when `ODOO_PATH` is
on the commit of the build (`pull`). If the IDE is opened on a parent folder, copy the configuration
into that workspace's `launch.json`. `debug off` goes back to a plain start.

## Layout of the repository

```
.
├── docker-compose.yml          the project stack (db, odoo, utils, mail)
├── .env                        settings (hub Config panel) · .env.secrets for the keys
├── addons/                     your modules
├── db_files/                   backups (db backup / db restore)
├── .config/
│   ├── odoo.conf               Odoo configuration
│   ├── terminal.conf           terminals: font, cursor, scrollback, time zone
│   ├── utils/starship.toml     prompt · utils/.zshrc your aliases
│   └── .pre-commit-config.yaml hooks
└── .data/                      the environment (owned by env-update)
    ├── VERSION · compat.map · migration_scripts/
    ├── docker/{odoo,utils,db}/ Dockerfiles and entrypoints
    ├── proxy/                  shared Traefik + hub (hub.py, static/hub.js, hub.css)
    ├── mcp/server.py           MCP server
    ├── web-terminal/           xterm.js bundle + server.py
    ├── scripts/
    │   ├── commands/*.sh       the utils commands (one script each, zsh functions in zshrc.sh)
    │   ├── internal/*.sh       backends without a command: status, conf, logs, check_versions, prune, mcp
    │   ├── lib/*.sh            env, ui, panes, odoo, project, db, theme — sourced by common.sh
    │   ├── odoo_runner.sh · odoo_header.sh · odoo_guard.sh   the Odoo pane
    │   ├── status.py           status daemon
    │   ├── zshrc.sh · completion.sh · tmux_setup.sh
    │   └── generate_addons_path.sh · check_*.sh · dev_db_bootstrap.sh · mail_catcher.sh · image_rev.sh
    ├── tests/                  env_test.sh (end to end), hub_test.py
    └── volumes/                data: db-container, odoo-container, shared (status.json, logs, tests)
```

## Troubleshooting

**Odoo did not start / view error after `u`** — `u -w my_module` does the update and reports the
errors of the start; the hub's logs tab shows the whole run.

**"start guard" in the logs pane** — a mounted `ENTERPRISE_PATH` / `ODOO_PATH` is on another series
than `ODOO_VERSION`: `pull` switches the repos to the right branch, or change the version and `rebuild`.

**Module shown as unknown in the start banner** — the module list is refreshed on every `u`; check the
folder has a `__manifest__.py` and is not under `IGNORED_PATH`.

**The tab or the status bar says rebuild** — the running containers differ from `.env`: run `rebuild`
(seconds when the images exist). A newer nightly is only a hint: `rebuild -n` when you want it.

**`RESTART` flag on the tab** — a `.env` key applied by compose changed since the containers were
created: `docker compose up -d` (the hub proposes it).

**Disk usage** — the shared images unused for `IMAGE_RETENTION_DAYS` are removed daily (`prune.log` in
the `odoo_env_meta` volume lists them); lower the value to free space sooner.

**No URL answers / hub empty** — the shared proxy must be running: `docker compose up -d` of any
project starts it. Port 80 already taken usually means an old per-project `*_traefik` container from a
previous version of this environment: `docker rm -f <project>_traefik`, then `docker compose up -d`.
Compose warns "network odoo_proxy exists but was not created for project …" at each start: expected,
the network is shared.

**MCP pill red** — the server is started by the utils entrypoint; `.data/volumes/shared/mcp.log` says
why it stopped, `docker compose restart utils` starts it again.

**Upgrading a project copy from version 3** — see [`CHANGELOG.md`](CHANGELOG.md): `docker compose
down` first (its traefik holds port 80), `env-update --from <path of a v4 copy>` or copy the new
`docker-compose.yml`, `.env` (keep your values) and `.data/`, then `rebuild` and `docker compose up -d`.
Databases and filestore are bind mounts in the project folder: nothing is lost. Update the MCP entry in
`~/.cursor/mcp.json`.

**Permission denied on docker.sock (Linux)**

```bash
sudo chmod 666 /var/run/docker.sock                 # temporary
```

```bash
sudo mkdir -p /etc/systemd/system/docker.socket.d   # permanent
sudo tee /etc/systemd/system/docker.socket.d/override.conf << EOF
[Socket]
SocketMode=0666
EOF
sudo systemctl daemon-reload && sudo systemctl restart docker.socket
```
