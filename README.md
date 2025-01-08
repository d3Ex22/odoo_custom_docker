# odoo\_custom\_docker

Odoo custom Docker setup with cool features.

## Version

**17.0**

## How to Run

1. **Create a Docker Network** (only needed once):

   ```bash
   docker network create web
   ```

2. **Run the Database Docker Compose**:

   - Execute the following command in the `db` folder:
     ```bash
     docker compose up
     ```
   - Alternatively, you can right-click on the `db/docker-compose.yml` file and choose "Compose Up" if you have installed the docker extension of your code editor.
   ![Capture d'écran docker-compose](https://i.postimg.cc/sXrRxG2J/image-2025-01-08-101256825.png)

3. **Run the Other Docker Compose Files**:

   - Navigate to the `odoo` and `utils` folders and execute their respective `docker-compose.yml` files the same way.

## Updating Modules

1. **If Changes Were Made to the ****************`.env`**************** File**:

   - Stop the Odoo container:
     ```bash
     docker compose down
     ```
   - Restart the Odoo container:
     ```bash
     docker compose up
     ```
   - Alternatively, you can also compose up and compose down using the docker extension of your code editor.
   ![Capture d'écran docker-compose](https://i.postimg.cc/sXrRxG2J/image-2025-01-08-101256825.png)

2. **If No Changes Were Made to the ****************`.env`**************** File**:

   - Simply restart the Odoo container:
     ```bash
     docker restart odoo
     ```
   - Or you can also restart the container quickly by accessing the docker tab of your code editor and right clicking the odoo container.
   ![docker restart](https://i.postimg.cc/pXmvrHZy/image-2025-01-08-101748853.png)

## Notes

- **Separation of Docker Compose Files**:

  - The files are separated to allow the Odoo container to be restarted independently. This ensures minimal downtime by avoiding unnecessary restarts of the `db` and `utils` containers.

- **Single Network Limitation**:

  - Only one container of each type can run at a time on the same network. To allow multiple instances:
    1. Create a new network:
       ```bash
       docker network create <new_network_name>
       ```
    2. Update all `docker-compose.yml` files to use the new network.
    3. Assign new URLs for each container using `.docker.localhost`.

## Features

- **Access Odoo Instance**: `http://odoo.docker.localhost`
- **Access Logs and Debugging**: `http://logs.docker.localhost`
- **Access Database Shell**: `http://shell.docker.localhost`
- **Customizable Environment**:
  - Edit odoo arguments, database name, addons path, or enterprise path in the `.env` file.
  - Leave the `enterprise` folder untouched for a CE (Community Edition) Odoo setup.
- **Automatic Version Updates**:
  - Odoo version will update automatically when a new Dockerfile is released for the specified version.

## Managing Multiple Projects

### Using Multiple Folders

1. **Separate Project Folders**:

   - Create a unique folder for each project.
   - The `utils` folder can remain shared as it is only needed once.

2. **Database Management**:

   - Option 1: Copy the `db` folder for each project.
   - Option 2: Use a single `db` folder shared across projects, and update the database name in each project's `.env` file.

### Using Multiple Git Branches

1. **Branch Setup**:

   - Organize projects by creating separate branches.

2. **Ignoring Folders in Git**:

   - Use the provided `.gitignore` example to ignore specific folders in your Git project.

3. **Custom Addons Folder**:

   - Update the addons path in `.env` to point to a shared parent directory if needed.

## Managing Different Odoo Versions

- **Database Compatibility**:

  - Different Odoo versions may require different PostgreSQL versions. Set up separate `db` folders for each version.

- **Shared Utils**:

  - The `utils` folder generally remains unchanged but may require updates for new features or compatibility adjustments.

