# odoo\_custom\_docker

Odoo custom Docker setup with advanced database management tools.

## Version

**17.0**

## Features

- **Access Odoo Instance**: `http://odoo.docker.localhost`
- **Access Logs and Debugging**: `http://logs.docker.localhost`
- **Access Tools and Commands**: `http://utils.docker.localhost`
- **Access Database Shell**: `http://shell.docker.localhost`
- **Customizable Environment**:
  - Edit Odoo arguments and addons paths in the `.env` file. Theses are working directly with no need to compose down and up the whole container, a simple and quick 'reboot' in utils is all you need.
  - Set the currently active database using `SELECTED_DB` in `.env` or with proper command in utils.
  - Leave the `enterprise` pointing to an empty directory to enable community edition.
- **Automatic Version Updates**:
  - Odoo version will update automatically when a new Dockerfile is released for the specified version.

## Utilities & Command Line Tools

All utilities are directly available in the **utils container shell** (access via `utils.docker.localhost`):

### Database & Odoo commands:

| Command                                            | Description                                                           |
|----------------------------------------------------|-----------------------------------------------------------------------|
| `anon`                                             | Take non-anonymized DB from `db_zip`, anonymize it, and export it.     |
| `cheat`                                            | Cheat database expiration date.                                       |
| `copy NEW_DBNAME [-d SOURCE_DBNAME, -s]`            | Duplicate the current or selected database.                           |
| `drop DBNAME [-y]`                                 | Drop a database (with confirmation).                                  |
| `export [-d DBNAME]`                               | Export database to `db_zip` as zip/sql.                               |
| `import DBNAME [-na, -s]`                          | Import DB from `db_zip`, anonymize it unless already or -na given.    |
| `list`                                             | List available databases.                                             |
| `psql [-d DBNAME, -c COMMAND]`                     | Open psql shell or execute command on selected DB.                    |
| `switch DBNAME [-y]`                               | Switch Odoo to another DB, can create a new one if missing.            |

### Odoo specific:

| Command  | Description                                |
|----------|--------------------------------------------|
| `reboot` | Quick reboot: restart only the Odoo container. |

### Tools:

| Command | Description                              |
|---------|------------------------------------------|
| `grok`  | Launch an ngrok tunnel to the Odoo container. |

### Arguments Definition:

| Argument    | Description                                                              |
|-------------|--------------------------------------------------------------------------|
| `-na`       | No anonymization (used with `import`).                                    |
| `-s`        | Switch Odoo to the new DB (used with `import`, `copy`).                   |
| `-y`        | Confirm actions without prompt (e.g., `drop`).                           |
| `-c COMMAND`| Execute specific command inside `psql`.                                  |
| `-d DBNAME` | Specify DB to target, defaults to `SELECTED_DB` if omitted.              |

## How to Run

### 1. **Create the Docker Network** (only needed once):

If you already have a `web` network, delete it:
```bash
docker network rm web
```
Then recreate it with proper IP range:
```bash
docker network create --subnet=192.168.2.0/24 --gateway=192.168.2.1 --ip-range=192.168.2.0/24 web
```

### 2. **Run the Docker Compose**:

   - Execute the following command in the folder:
     ```bash
     docker compose up
     ```
   - Alternatively, you can right-click on the `docker-compose.yml` file and choose "Compose Up" if you have installed the docker extension of your code editor.
   ![Capture d'écran docker-compose](https://i.postimg.cc/sXrRxG2J/image-2025-01-08-101256825.png)

## Updating Modules, args, or changing db

```bash
docker compose restart odoo
```

or simply

```bash
reboot
```
in the utils shell at http://utils.docker.localhost

## Notes

The utils shell contain most of the commands you will need, no need to compose down and compose up the container most of the time.

Edits in odoo args, change in db etc are automatically used directly with no need to compose down and up. So a simple 'reboot' in the utils can save you a lot of time.

