FROM ubuntu:jammy

# Basic setup for SSH and Docker

RUN apt-get update && apt-get install -y openssh-server docker.io && mkdir -p /var/run/sshd && \
    ssh-keygen -A && apt-get upgrade -y

RUN test -f /etc/ssh/sshd_config || dpkg-reconfigure openssh-server

RUN useradd -m -s /bin/bash odoo && \
    echo "odoo:odoo" | chpasswd && \
    usermod -aG sudo,root odoo && \
    mkdir -p /home/odoo/.ssh && \
    chown -R odoo:odoo /home/odoo/.ssh

RUN echo "odoo ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Loop for user screen

RUN echo "while true; do" >> /etc/bash.bashrc && \
    echo "    clear" >> /etc/bash.bashrc && \
    echo "    echo ''" >> /etc/bash.bashrc && \
    echo "    echo '\e[31m         ____        __                     __                         \e[0m'" >> /etc/bash.bashrc && \
    echo "    echo '\e[31m        / __ \  ____/ / ____   ____        / /   ____    ____ _  _____ \e[0m'" >> /etc/bash.bashrc && \
    echo "    echo '\e[31m       / / / / / __  / / __ \ / __ \      / /   / __ \  / __  / / ___/ \e[0m'" >> /etc/bash.bashrc && \
    echo "    echo '\e[31m      / /_/ / / /_/ / / /_/ // /_/ /     / /___/ /_/ / / /_/ / (__  )  \e[0m'" >> /etc/bash.bashrc && \
    echo "    echo '\e[31m      \____/  \____/  \____/ \____/     /_____/\____/  \__, / /____/   \e[0m'" >> /etc/bash.bashrc && \
    echo "    echo '\e[31m                                                      /____/           \e[0m'" >> /etc/bash.bashrc && \
    echo "    echo '      ----------------------------------------------------------------'" >> /etc/bash.bashrc && \
    echo "    echo ''" >> /etc/bash.bashrc && \
    echo "    docker attach odoo" >> /etc/bash.bashrc && \
    echo "    sleep 5" >> /etc/bash.bashrc && \
    echo "done" >> /etc/bash.bashrc