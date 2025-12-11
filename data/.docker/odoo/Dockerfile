FROM ubuntu:noble

ARG ODOO_VERSION=18.0
ARG ODOO_BUILD=latest
ARG PYTHON_VERSION=3.12
ARG TARGETARCH

ENV LANG=C.UTF-8
ENV ODOO_VERSION=${ODOO_VERSION}
ENV ODOO_RC=/etc/odoo/odoo.conf
ENV PYENV_ROOT=/opt/pyenv
ENV PATH="${PYENV_ROOT}/shims:${PYENV_ROOT}/bin:/opt/odoo:${PATH}"

SHELL ["/bin/bash", "-xo", "pipefail", "-c"]

# ============================================
# 1. SYSTEM DEPENDENCIES
# ============================================
RUN apt-get update && apt-get upgrade -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        dirmngr \
        git \
        gcc \
        g++ \
        make \
        build-essential \
        libssl-dev \
        zlib1g-dev \
        libbz2-dev \
        libreadline-dev \
        libsqlite3-dev \
        libncursesw5-dev \
        xz-utils \
        tk-dev \
        libxml2-dev \
        libxmlsec1-dev \
        libffi-dev \
        liblzma-dev \
        libcups2-dev \
        libsasl2-dev \
        libldap2-dev \
        libpq-dev \
        npm \
        node-less \
        tmux \
        tini \
        postgresql-client && \
    npm install -g rtlcss && \
    rm -rf /var/lib/apt/lists/*

# ============================================
# 2. CREATE ODOO USER
# ============================================
RUN useradd -m -d /var/lib/odoo -U -r -s /bin/bash odoo

# ============================================
# 3. PYENV INSTALLATION
# ============================================
RUN git clone https://github.com/pyenv/pyenv.git ${PYENV_ROOT}

# ============================================
# 4. INSTALL SELECTED PYTHON VERSION
# ============================================
RUN pyenv install ${PYTHON_VERSION} && \
    pyenv global ${PYTHON_VERSION} && \
    pip install --upgrade pip wheel setuptools

# ============================================
# 5. WKHTMLTOPDF
# ============================================
RUN ARCH=${TARGETARCH:-$(dpkg --print-architecture)} && \
    curl -o wkhtmltox.deb -sSL https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_${ARCH}.deb && \
    apt-get update && apt-get install -y --no-install-recommends \
        ./wkhtmltox.deb \
        fonts-liberation \
        fonts-dejavu-core && \
    rm -rf /var/lib/apt/lists/* wkhtmltox.deb

# ============================================
# 6. ODOO INSTALLATION FROM SOURCE
# ============================================
RUN mkdir -p /opt/odoo && \
    curl -sSL http://nightly.odoo.com/${ODOO_VERSION}/nightly/src/odoo_${ODOO_VERSION}.${ODOO_BUILD}.tar.gz | \
    tar -xz --strip-components=1 -C /opt/odoo && \
    pip install -r /opt/odoo/requirements.txt && \
    pip install /opt/odoo

# ============================================
# 7. EXTRA PYTHON DEPENDENCIES
# ============================================
RUN pip install \
    packaging \
    num2words \
    ofxparse \
    dbfread \
    ebaysdk \
    phonenumbers \
    firebase_admin \
    pdfminer.six

# ============================================
# 8. STRUCTURE & PERMISSIONS
# ============================================
RUN mkdir -p \
        /var/lib/odoo/filestore \
        /var/lib/odoo/sessions \
        /var/lib/odoo/cache \
        /var/log/odoo \
        /mnt/extra-addons \
        /mnt/enterprise-addons \
        /etc/odoo && \
    chown -R odoo:odoo /var/lib/odoo /var/log/odoo /mnt/extra-addons /mnt/enterprise-addons /etc/odoo /opt/odoo && \
    chmod -R 755 /var/lib/odoo /var/log/odoo

# ============================================
# 9. ENTRYPOINT & SCRIPTS
# ============================================
COPY data/.docker/odoo/entrypoint.sh /entrypoint.sh
COPY data/.docker/odoo/scripts/ /usr/local/bin/
RUN chmod +x /entrypoint.sh && \
    if [ -d /usr/local/bin ] && [ "$(ls -A /usr/local/bin/*.sh 2>/dev/null)" ]; then \
        chmod +x /usr/local/bin/*.sh; \
    fi

# ============================================
# 10. VOLUMES & PORTS
# ============================================
VOLUME ["/var/lib/odoo", "/mnt/extra-addons", "/var/log/odoo"]
EXPOSE 8069 8071 8072

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
