FROM ubuntu:noble

SHELL ["/bin/bash", "-xo", "pipefail", "-c"]

# Generate locale C.UTF-8 for postgres and general locale data
ENV LANG en_US.UTF-8

# Retrieve the target architecture to install the correct wkhtmltopdf package
ARG TARGETARCH

# Install some deps, lessc and less-plugin-clean-css, and wkhtmltopdf

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        dirmngr \
        fonts-noto-cjk \
        gnupg \
        libssl-dev \
        node-less \
        npm \
        python3-magic \
        python3-num2words \
        python3-odf \
        python3-pdfminer \
        python3-pip \
        python3-phonenumbers \
        python3-pyldap \
        python3-qrcode \
        python3-renderpm \
        python3-setuptools \
        python3-slugify \
        python3-vobject \
        python3-watchdog \
        python3-xlrd \
        python3-xlwt \
        xz-utils && \
    if [ -z "${TARGETARCH}" ]; then \
        TARGETARCH="$(dpkg --print-architecture)"; \
    fi; \
    WKHTMLTOPDF_ARCH=${TARGETARCH} && \
    case ${TARGETARCH} in \
    "amd64") WKHTMLTOPDF_ARCH=amd64 ;; \
    "arm64") ;; \
    "ppc64le" | "ppc64el") WKHTMLTOPDF_ARCH=ppc64el ;; \
    esac \
    && curl -o wkhtmltox.deb -sSL https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_${WKHTMLTOPDF_ARCH}.deb \
    && apt-get install -y --no-install-recommends ./wkhtmltox.deb \
    && rm -rf /var/lib/apt/lists/* wkhtmltox.deb

# Install rtlcss (on Debian buster)
RUN npm install -g rtlcss

# Install Odoo
ENV ODOO_VERSION 19.0
ARG ODOO_RELEASE=latest
RUN curl -o odoo.deb -sSL http://nightly.odoo.com/${ODOO_VERSION}/nightly/deb/odoo_${ODOO_VERSION}.${ODOO_RELEASE}_all.deb \
    && apt-get update \
    && apt-get -y install --no-install-recommends ./odoo.deb \
    && rm -rf /var/lib/apt/lists/* odoo.deb

# Copy entrypoint script and Odoo configuration file
COPY ./data/config/odoo/entrypoint.sh /
COPY ./data/config/odoo/odoo.conf /etc/odoo/

# Set permissions and Mount /var/lib/odoo to allow restoring filestore and /mnt/extra-addons for users addons
RUN chown odoo /etc/odoo/odoo.conf \
    && mkdir -p /mnt/extra-addons \
    && chown -R odoo /mnt/extra-addons
VOLUME ["/var/lib/odoo", "/mnt/extra-addons"]

# Expose Odoo services
EXPOSE 8069 8071 8072

# Set the default config file
ENV ODOO_RC /etc/odoo/odoo.conf

COPY data/config/odoo/wait-for-psql.py /usr/local/bin/wait-for-psql.py
RUN chmod +x /usr/local/bin/wait-for-psql.py \
    && chown odoo /usr/local/bin/wait-for-psql.py

# Installer openssh-server et s'assurer que tout est en place
RUN apt-get update && apt-get install -y openssh-server
RUN mkdir -p /var/run/sshd \
    && ssh-keygen -A

RUN pip install qrcode --break-system-packages

# Vérification de la configuration
RUN test -f /etc/ssh/sshd_config || dpkg-reconfigure openssh-server

# Copier les scripts dans le conteneur
COPY data/scripts/entrypoint.sh /home/odoo/entrypoint.sh
RUN chmod +x /home/odoo/entrypoint.sh \
    && chown odoo /home/odoo/entrypoint.sh

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

# Install missing packages for good requirements.txt install
# Create and set permissions for data directory
RUN apt install -y git gcc libcups2-dev python3-dev build-essential

