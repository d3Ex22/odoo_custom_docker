# Odoo Development Environment

🇬🇧 [English](#english) | 🇫🇷 [Français](#français)

---

<a name="english"></a>
## 🇬🇧 English

Fast, flexible Docker environment for Odoo development.

### Features

- **Fast restarts**: ~2s with tmux (vs ~30s with container restart)
- **Version switching**: Change Odoo/Python/PostgreSQL version in `.env`
- **Smart caching**: Skip pip install if requirements unchanged
- **Web terminal**: Access via browser
- **Quick commands**: `r`, `u`, `s`, `db` aliases
- **Auto addon discovery**: Scans subfolders for modules

### Quick Start

#### 1. Configure `.env`

```bash
ODOO_VERSION=19.0
PYTHON_VERSION=3.12
POSTGRES_VERSION=17
ADDONS_PATH=./addons
ENTERPRISE_PATH=../enterprise
```

#### 2. Start

```bash
docker compose up -d
```

#### 3. Access

| Service | URL |
|---------|-----|
| Odoo    | http://odoo.docker.localhost |
| Logs    | http://logs.docker.localhost |
| Utils   | http://utils.docker.localhost |

### Commands

| Command | Alias | Description |
|---------|-------|-------------|
| `reboot` | `r` | Restart Odoo (~2s) |
| `update [module]` | `u` | Update modules + restart |
| `start` | `s` | Start Odoo process |
| `stop` | | Stop Odoo process |
| `shell [db]` | | Odoo shell (new pane) |
| `database [cmd]` | `db` | Database management |
| `set VAR [value]` | | Configure .env settings |
| `rebuild` | | Rebuild containers |
| `migrate DB VER` | | Migrate database |
| `requirements` | | Install addon dependencies |
| `status` | | Container status |
| `grok` | | Ngrok tunnel |

### Configuration

#### .env Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ODOO_VERSION` | `19.0` | 14.0, 15.0, 16.0, 17.0, 18.0, 19.0 |
| `ODOO_BUILD` | `latest` | Build date (YYYYMMDD) or `latest` |
| `PYTHON_VERSION` | `3.12` | Must be compatible with Odoo version |
| `POSTGRES_VERSION` | `17` | Must be compatible with Odoo version |
| `ADDONS_PATH` | `./addons` | Path to custom addons |
| `ENTERPRISE_PATH` | | Path to enterprise addons (empty = disabled) |
| `ODOO_PATH` | | Path to Odoo source (for module discovery) |
| `SCAN_SUBFOLDERS` | `true` | Scan nested folders for addons |
| `SELECTED_DB` | `main` | Active database |
| `ODOO_UPDATE` | | Modules to update on restart |
| `ODOO_ARGS` | | Extra Odoo arguments |

#### Version Compatibility

| Odoo | Python | PostgreSQL |
|------|--------|------------|
| 19.0 | 3.12, 3.11 | 17, 16, 15 |
| 18.0 | 3.12, 3.11, 3.10 | 17, 16, 15, 14 |
| 17.0 | 3.11, 3.10 | 16, 15, 14, 13 |
| 16.0 | 3.10, 3.9, 3.8 | 15, 14, 13, 12 |
| 15.0 | 3.10, 3.9, 3.8 | 14, 13, 12 |
| 14.0 | 3.8, 3.7, 3.6 | 13, 12, 11 |

### Path Configuration

Paths are relative to `docker-compose.yml`:

```
project/
├── docker-compose.yml
├── addons/
│   └── my_module/
└── ../enterprise/
```

```bash
ADDONS_PATH=./addons           # Same directory
ENTERPRISE_PATH=../enterprise  # Parent directory
```

With `SCAN_SUBFOLDERS=true`, nested structures are auto-discovered:

```
addons/
├── custom-addons/
│   └── module1/
└── extra-addons/
    └── module2/
```

### Changing Odoo Version

1. Edit `.env`: `ODOO_VERSION=18.0`
2. Adjust `PYTHON_VERSION` and `POSTGRES_VERSION` if needed
3. Run: `rebuild`

### Troubleshooting

**Permission denied on docker.sock**
```bash
sudo chmod 666 /var/run/docker.sock
```

**Database connection failed**
```bash
docker compose logs db
```

---

<a name="français"></a>
## 🇫🇷 Français

Environnement Docker rapide et flexible pour le développement Odoo.

### Fonctionnalités

- **Redémarrages rapides**: ~2s avec tmux (vs ~30s avec restart conteneur)
- **Changement de version**: Modifiez Odoo/Python/PostgreSQL dans `.env`
- **Cache intelligent**: Skip pip install si requirements inchangés
- **Terminal web**: Accès via navigateur
- **Commandes rapides**: Alias `r`, `u`, `s`, `db`
- **Découverte auto des addons**: Scan des sous-dossiers

### Démarrage Rapide

#### 1. Configurer `.env`

```bash
ODOO_VERSION=19.0
PYTHON_VERSION=3.12
POSTGRES_VERSION=17
ADDONS_PATH=./addons
ENTERPRISE_PATH=../enterprise
```

#### 2. Démarrer

```bash
docker compose up -d
```

#### 3. Accès

| Service | URL |
|---------|-----|
| Odoo    | http://odoo.docker.localhost |
| Logs    | http://logs.docker.localhost |
| Utils   | http://utils.docker.localhost |

### Commandes

| Commande | Alias | Description |
|----------|-------|-------------|
| `reboot` | `r` | Redémarre Odoo (~2s) |
| `update [module]` | `u` | Met à jour les modules + restart |
| `start` | `s` | Démarre le processus Odoo |
| `stop` | | Arrête le processus Odoo |
| `shell [db]` | | Shell Odoo (nouveau pane) |
| `database [cmd]` | `db` | Gestion base de données |
| `set VAR [valeur]` | | Configure les paramètres .env |
| `rebuild` | | Reconstruit les conteneurs |
| `migrate DB VER` | | Migre une base de données |
| `requirements` | | Installe les dépendances addons |
| `status` | | Statut des conteneurs |
| `grok` | | Tunnel Ngrok |

### Configuration

#### Variables .env

| Variable | Défaut | Description |
|----------|--------|-------------|
| `ODOO_VERSION` | `19.0` | 14.0, 15.0, 16.0, 17.0, 18.0, 19.0 |
| `ODOO_BUILD` | `latest` | Date du build (YYYYMMDD) ou `latest` |
| `PYTHON_VERSION` | `3.12` | Doit être compatible avec la version Odoo |
| `POSTGRES_VERSION` | `17` | Doit être compatible avec la version Odoo |
| `ADDONS_PATH` | `./addons` | Chemin vers les addons custom |
| `ENTERPRISE_PATH` | | Chemin vers enterprise (vide = désactivé) |
| `ODOO_PATH` | | Chemin vers sources Odoo (découverte modules) |
| `SCAN_SUBFOLDERS` | `true` | Scanner les sous-dossiers pour les addons |
| `SELECTED_DB` | `main` | Base de données active |
| `ODOO_UPDATE` | | Modules à mettre à jour au restart |
| `ODOO_ARGS` | | Arguments Odoo supplémentaires |

#### Compatibilité des Versions

| Odoo | Python | PostgreSQL |
|------|--------|------------|
| 19.0 | 3.12, 3.11 | 17, 16, 15 |
| 18.0 | 3.12, 3.11, 3.10 | 17, 16, 15, 14 |
| 17.0 | 3.11, 3.10 | 16, 15, 14, 13 |
| 16.0 | 3.10, 3.9, 3.8 | 15, 14, 13, 12 |
| 15.0 | 3.10, 3.9, 3.8 | 14, 13, 12 |
| 14.0 | 3.8, 3.7, 3.6 | 13, 12, 11 |

### Configuration des Chemins

Les chemins sont relatifs à `docker-compose.yml`:

```
projet/
├── docker-compose.yml
├── addons/
│   └── mon_module/
└── ../enterprise/
```

```bash
ADDONS_PATH=./addons           # Même répertoire
ENTERPRISE_PATH=../enterprise  # Répertoire parent
```

Avec `SCAN_SUBFOLDERS=true`, les structures imbriquées sont auto-découvertes:

```
addons/
├── custom-addons/
│   └── module1/
└── extra-addons/
    └── module2/
```

### Changer de Version Odoo

1. Modifier `.env`: `ODOO_VERSION=18.0`
2. Ajuster `PYTHON_VERSION` et `POSTGRES_VERSION` si nécessaire
3. Exécuter: `rebuild`

### Dépannage

**Permission denied sur docker.sock**
```bash
sudo chmod 666 /var/run/docker.sock
```

**Connexion base de données échouée**
```bash
docker compose logs db
```
