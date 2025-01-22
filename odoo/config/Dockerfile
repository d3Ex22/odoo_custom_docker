FROM odoo:15.0

# Passer en tant que root pour les installations
USER root

# Installer openssh-server et s'assurer que tout est en place
RUN apt-get update && apt-get install -y openssh-server && mkdir -p /var/run/sshd && \
    ssh-keygen -A

RUN pip install qrcode

# Vérification de la configuration
RUN test -f /etc/ssh/sshd_config || dpkg-reconfigure openssh-server

# Ajouter un utilisateur pour SSH
RUN usermod -s /bin/bash odoo && echo "odoo:odoo" | chpasswd && \
mkdir -p /home/odoo && chown odoo:odoo /home/odoo

# Ajouter une boucle pour relancer automatiquement la commande en cas d'échec dans /etc/bash.bashrc
RUN echo 'while true; do' >> /etc/bash.bashrc && \
    echo '    odoo shell -d v17 --db_host db --db_password odoo' >> /etc/bash.bashrc && \
    echo '    sleep 5' >> /etc/bash.bashrc && \
    echo 'done' >> /etc/bash.bashrc

# Autoriser la connexion root via SSH (optionnel)
RUN echo "PermitRootLogin yes" >> /etc/ssh/sshd_config

# Exposer le port SSH
EXPOSE 22