FROM odoo:17.0

# Passer en tant que root pour les installations
USER root

# Installer openssh-server et s'assurer que tout est en place
RUN apt-get update && apt-get install -y openssh-server && mkdir -p /var/run/sshd && \
    ssh-keygen -A

RUN pip install qrcode --break-system-packages

# Vérification de la configuration
RUN test -f /etc/ssh/sshd_config || dpkg-reconfigure openssh-server

# Copier les scripts dans le conteneur
COPY data/scripts/entrypoint.sh /home/odoo/entrypoint.sh
RUN chmod +x /home/odoo/entrypoint.sh

# Ajouter un utilisateur pour SSH
RUN usermod -s /bin/bash odoo && echo "odoo:odoo" | chpasswd && \
mkdir -p /home/odoo && chown odoo:odoo /home/odoo

# Ajouter une boucle pour relancer automatiquement la commande en cas d'échec dans /etc/bash.bashrc
RUN echo 'while true; do' >> /etc/bash.bashrc && \
    echo "    clear" >> /etc/bash.bashrc && \
    echo "    echo ''" >> /etc/bash.bashrc && \
    echo "    echo '         ____        __                    _____   __            __  __'" >> /etc/bash.bashrc && \
    echo "    echo '        / __ \  ____/ / ____   ____       / ___/  / /_   ___    / / / /'" >> /etc/bash.bashrc && \
    echo "    echo '       / / / / / __  / / __ \ / __ \      \__ \  / __ \ / _ \  / / / / '" >> /etc/bash.bashrc && \
    echo "    echo '      / /_/ / / /_/ / / /_/ // /_/ /     ___/ / / / / //  __/ / / / /  '" >> /etc/bash.bashrc && \
    echo "    echo '      \____/  \____/  \____/ \____/     /____/ /_/ /_/ \___/ /_/ /_/   '" >> /etc/bash.bashrc && \
    echo "    echo ''" >> /etc/bash.bashrc && \
    echo "    echo '      -----------------------------------------------------------------'" >> /etc/bash.bashrc && \
    echo "    echo ''" >> /etc/bash.bashrc && \
    echo '    odoo shell -d main --db_host db --db_password odoo' >> /etc/bash.bashrc && \
    echo '    sleep 5' >> /etc/bash.bashrc && \
    echo 'done' >> /etc/bash.bashrc

# Autoriser la connexion root via SSH (optionnel)
RUN echo "PermitRootLogin yes" >> /etc/ssh/sshd_config

# Exposer le port SSH
EXPOSE 22