# odoo_custom_docker
Odoo custon docker with cool features

Version: 17.0

How to run:
- run docker-compose.yml as a regular docker file

Features:
- URL: 'odoo.docker.localhost' will give you access to your odoo instance
- URL: 'logs.docker.localhost' will give you access to this odoo logs and pdb.
- URL: 'shell.docker.localhost' will give you access to this database odoo shell.
- You can edit database name and modules to update in the .env file
- The odoo version will be updated each time odoo release a new Dockerfile on the specified version
