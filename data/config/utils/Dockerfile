FROM ubuntu:jammy

# Basic setup for SSH and Docker
RUN apt-get update && apt-get install -y openssh-server ca-certificates curl unzip zip && mkdir -p /var/run/sshd && \
    ssh-keygen -A && apt-get upgrade -y

RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc

RUN echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null

RUN apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

RUN test -f /etc/ssh/sshd_config || dpkg-reconfigure openssh-server

RUN useradd -m -s /bin/bash odoo && \
    echo "odoo:odoo" | chpasswd && \
    usermod -aG sudo,root odoo && \
    mkdir -p /home/odoo/.ssh && \
    chown -R odoo:odoo /home/odoo/.ssh
RUN echo "odoo ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Setup scripts for commands
RUN mkdir -p /mnt/scripts
COPY data/scripts/ /mnt/scripts/
RUN chmod +x /mnt/scripts/*.sh

RUN curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc | tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null && \
    echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | tee /etc/apt/sources.list.d/ngrok.list && \
    apt update && \
    apt install ngrok -y

# Download, Install, and Configure Utils/Commands
# - anon
RUN echo "alias anon='/mnt/scripts/anon.sh'" >> /etc/bash.bashrc
# - cheat
RUN echo "alias cheat='/mnt/scripts/cheat.sh'" >> /etc/bash.bashrc
# - copy
RUN echo "alias copy='/mnt/scripts/copy.sh'" >> /etc/bash.bashrc
# - drop
RUN echo "alias drop='/mnt/scripts/drop.sh'" >> /etc/bash.bashrc
# - exp
RUN echo "alias exp='/mnt/scripts/exp.sh'" >> /etc/bash.bashrc
# - imp
RUN echo "alias imp='/mnt/scripts/imp.sh'" >> /etc/bash.bashrc
# - list
RUN echo "alias list='/mnt/scripts/list.sh'" >> /etc/bash.bashrc
# - psql
RUN echo "alias psql='/mnt/scripts/psql.sh'" >> /etc/bash.bashrc
# - switch
RUN echo "alias switch='/mnt/scripts/switch.sh'" >> /etc/bash.bashrc

# - fix-reports
RUN echo "alias fix-reports='/mnt/scripts/fix-reports.sh'" >> /etc/bash.bashrc
# - reboot
RUN echo "alias reboot='/mnt/scripts/reboot.sh'" >> /etc/bash.bashrc

# - docker-shell
RUN echo "alias docker-shell='/mnt/scripts/docker-shell.sh'" >> /etc/bash.bashrc
# - grok
RUN echo "alias grok='/mnt/scripts/grok.sh'" >> /etc/bash.bashrc
# - pip
RUN echo "alias pip='/mnt/scripts/pip.sh'" >> /etc/bash.bashrc

# Loop for user screen
RUN echo "clear" >> /etc/bash.bashrc && \
    echo "echo ''" >> /etc/bash.bashrc && \
    echo "echo '\e[32m         ____        __                      __  __  __    _   __         \e[0m'" >> /etc/bash.bashrc && \
    echo "echo '\e[32m        / __ \  ____/ / ____    ____        / / / / / /_  (_) / / _____   \e[0m'" >> /etc/bash.bashrc && \
    echo "echo '\e[32m       / / / / / __  / / __ \  / __ \      / / / / / __/ / / / / / ___/   \e[0m'" >> /etc/bash.bashrc && \
    echo "echo '\e[32m      / /_/ / / /_/ / / /_/ / / /_/ /     / /_/ / / /_  / / / / (__  )    \e[0m'" >> /etc/bash.bashrc && \
    echo "echo '\e[32m      \____/  \____/  \____/  \____/      \____/  \__/ /_/ /_/ /____/     \e[0m'" >> /etc/bash.bashrc && \
    echo "echo ''" >> /etc/bash.bashrc && \
    echo "echo '      -----------------------------------------------------------------'" >> /etc/bash.bashrc && \
    echo "echo ''" >> /etc/bash.bashrc && \
    echo "echo ' List of available Utils commands [optional args]: '" >> /etc/bash.bashrc && \
    echo "echo ''" >> /etc/bash.bashrc && \
    echo "echo '  Database: '" >> /etc/bash.bashrc && \
    echo "echo '\e[0m   - anon                                    \e[32m take non anonymized db from db_zip and anonymize it        \e[0m'" >> /etc/bash.bashrc && \
    echo "echo '\e[0m   - cheat                                   \e[32m cheat database expiration date                             \e[0m'" >> /etc/bash.bashrc && \
    echo "echo '\e[0m   - copy NEW_DBNAME [-d SOURCE_DBNAME, -s]  \e[32m duplicate current database                                 \e[0m'" >> /etc/bash.bashrc && \
    echo "echo '\e[0m   - drop DBNAME [-y]                        \e[32m drop database                                              \e[0m'" >> /etc/bash.bashrc && \
    echo "echo '\e[0m   - exp [-d DBNAME]                         \e[32m export zip/sql db from psql to the db_zip folder           \e[0m'" >> /etc/bash.bashrc && \
    echo "echo '\e[0m   - imp DBNAME [-na, -s]                    \e[32m import zip/sql db from the db_zip folder and anonymize it  \e[0m'" >> /etc/bash.bashrc && \
    echo "echo '\e[0m   - list                                    \e[32m list available databases                                   \e[0m'" >> /etc/bash.bashrc && \
    echo "echo '\e[0m   - psql [-d DBNAME, -c COMMAND]            \e[32m launch a psql shell to the currently selected database     \e[0m'" >> /etc/bash.bashrc && \
    echo "echo '\e[0m   - switch DBNAME [-y]                      \e[32m switch Odoo the another database, can also create a new db \e[0m'" >> /etc/bash.bashrc && \
    echo "echo ''" >> /etc/bash.bashrc && \
    echo "echo '  Odoo: '" >> /etc/bash.bashrc && \
    echo "echo '\e[0m   - fix-reports [-f]                        \e[32m fix pdf reports by adding a line into db                   \e[0m'" >> /etc/bash.bashrc && \
    echo "echo '\e[0m   - reboot                                  \e[32m quick reboot, will restart the odoo container              \e[0m'" >> /etc/bash.bashrc && \
    echo "echo ''" >> /etc/bash.bashrc && \
    echo "echo '  Tools: '" >> /etc/bash.bashrc && \
    echo "echo '\e[0m   - docker-shell                            \e[32m launch a bash shell in the odoo container                  \e[0m'" >> /etc/bash.bashrc && \
    echo "echo '\e[0m   - grok                                    \e[32m launch a ngrok tunnel to the odoo container                \e[0m'" >> /etc/bash.bashrc && \
    echo "echo '\e[0m   - pip ARGS                                \e[32m launch a pip command in the odoo container                 \e[0m'" >> /etc/bash.bashrc && \
    echo "echo ''" >> /etc/bash.bashrc && \
    echo "echo ' Args definition: '" >> /etc/bash.bashrc && \
    echo "echo '\e[0m  -f            \e[32m force action                                                   \e[0m'" >> /etc/bash.bashrc && \
    echo "echo '\e[0m  -na           \e[32m no anonymization                                               \e[0m'" >> /etc/bash.bashrc && \
    echo "echo '\e[0m  -s            \e[32m switch to the new database                                     \e[0m'" >> /etc/bash.bashrc && \
    echo "echo '\e[0m  -y            \e[32m confirm action                                                 \e[0m'" >> /etc/bash.bashrc && \
    echo "echo '\e[0m  -c COMMAND    \e[32m command to execute                                             \e[0m'" >> /etc/bash.bashrc && \
    echo "echo '\e[0m  -d DBNAME     \e[32m database name, if not specified will take current database     \e[0m'" >> /etc/bash.bashrc && \
    echo "echo ''" >> /etc/bash.bashrc
