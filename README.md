# odoo_custom_docker
Odoo custon docker with cool features

Version: 17.0

How to run:
- open cmd and execute "docker network create web" (only once)
- run db/docker-compose.yml first. either with right click on it or with the "commande docker compose up".
- run the two other docker-compose.

Update modules:
- compose down then compose up only the odoo/docker-compose.yml file.

Note: 
- The docker-compose files are separated because odoo will often need to be compose down/up to change module update list and/or update modules.
This way it keep the booting time the fastest possible because db and utils dont need to be rebooted.
- Keep in mind that only a single container of each can run at the same time because they all use the same network. If you want to change this behaviour, simply create a new network and rename every occurence of the current network in all docker-compose.yml files. You will also need to give new url to each containers.
URL must contain ".docker.localhost".


Features:
- URL: 'odoo.docker.localhost' will give you access to your odoo instance
- URL: 'logs.docker.localhost' will give you access to this odoo logs and pdb.
- URL: 'shell.docker.localhost' will give you access to this database odoo shell.
- You can edit database name/addons to update/path to addons and enterprise in the .env file. (Leave the enterprise folder as is if you wish to create a CE Odoo)
- The odoo version will be updated each time odoo release a new Dockerfile on the specified version.

How to manage multiple projects:
- Multiple folders:
    To have multiple folders cointaining each a different projet, keep the utils folder apart, it's only needed once.
    You will need to copy paste the odoo folder for each of your projects.
    For the database you have 2 options:
    - either you copy paste the db folder with the odoo folder.
    - either you keep apart with utils a db folder that will contain all the databases, and you rename the database in the .env of the odoo folder.
- Multiple githubs:
    You can also manage multiple projet simply by adding theses folders in a github branch. You can keep the utils folder appart if you want.
    A .gitignore exemple is added to ignore theses folder in a github project, you can also change the path of the addons folder to have addons in the parent directory.

Manage different versions of odoo:
- Keep in mind that different versions of odoo might need different versions of postgresSQL (the database manager) and so will need different db folders. But the utils folder might not change except maybe with updates of the features.