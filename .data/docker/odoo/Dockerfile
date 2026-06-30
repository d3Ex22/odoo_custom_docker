FROM ubuntu:25.10

ARG ODOO_VERSION
ARG ODOO_BUILD
ARG PYTHON_VERSION
ARG TARGETARCH

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8
ENV ODOO_VERSION=${ODOO_VERSION}
ENV ODOO_RC=/etc/odoo/odoo.conf
ENV VIRTUAL_ENV=/opt/venv
ENV PATH="${VIRTUAL_ENV}/bin:/opt/odoo:${PATH}"

SHELL ["/bin/bash", "-xo", "pipefail", "-c"]

# ============================================
# 1. SYSTEM DEPENDENCIES
# ============================================
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        fonts-noto-cjk \
        gettext-base \
        git \
        libcairo2-dev \
        libcups2-dev \
        libffi-dev \
        libldap2-dev \
        libpq-dev \
        libsasl2-dev \
        libssl-dev \
        libxml2-dev \
        libxmlsec1-dev \
        locales \
        node-less \
        npm \
        postgresql-client \
        tmux \
        tini && \
    locale-gen en_US.UTF-8 && \
    if [ "$ODOO_VERSION" != "14.0" ] && [ "$ODOO_VERSION" != "15.0" ]; then \
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends libmagic1; \
    fi && \
    npm install -g rtlcss && \
    rm -rf /var/lib/apt/lists/*

# ============================================
# 2. CREATE ODOO USER
# ============================================
RUN useradd -m -d /var/lib/odoo -U -r -s /bin/bash odoo

# ============================================
# 3. UV INSTALLATION
# ============================================
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

# ============================================
# 4. INSTALL SELECTED PYTHON VERSION
# ============================================
RUN uv python install ${PYTHON_VERSION} && \
    uv venv --seed --python ${PYTHON_VERSION} ${VIRTUAL_ENV} && \
    if [ "$ODOO_VERSION" = "17.0" ]; then \
        uv pip install --upgrade pip wheel "setuptools<71"; \
    else \
        uv pip install --upgrade pip wheel setuptools; \
    fi

# ============================================
# 5. WKHTMLTOPDF
# ============================================
# v14-15: 0.12.5 (buster, amd64 only)
# v16:    0.12.6.1-3 (bullseye, multi-arch)
# v17+:   0.12.6.1-3 (jammy, multi-arch)
RUN ARCH="${TARGETARCH:-$(dpkg --print-architecture)}" && \
    case "$ODOO_VERSION" in \
        14.0|15.0) curl -o wkhtmltox.deb -sSL "https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.5/wkhtmltox_0.12.5-1.buster_amd64.deb" ;; \
        16.0) curl -o wkhtmltox.deb -sSL "https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.bullseye_${ARCH}.deb" ;; \
        *) curl -o wkhtmltox.deb -sSL "https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_${ARCH}.deb" ;; \
    esac && \
    apt-get update && apt-get install -y --no-install-recommends \
        ./wkhtmltox.deb \
        fonts-liberation \
        fonts-dejavu-core && \
    rm -rf /var/lib/apt/lists/* wkhtmltox.deb

# ============================================
# 6. ODOO INSTALLATION FROM SOURCE
# ============================================
RUN mkdir -p /opt/odoo && \
    curl -sSL https://nightly.odoo.com/${ODOO_VERSION}/nightly/src/odoo_${ODOO_VERSION}.${ODOO_BUILD}.tar.gz | \
    tar -xz --strip-components=1 -C /opt/odoo && \
    if [[ "${PYTHON_VERSION}" == 3.10* ]]; then \
        sed -i \
            -e 's/^gevent==21\.8\.0/gevent==22.10.2/' \
            -e 's/^greenlet==1\.1\.2/greenlet==2.0.2/' \
            -e 's/^cryptography==3\.4\.8; python_version < '\''3\.12'\''.*/cryptography==42.0.8; python_version < '\''3\.12'\''/' \
            -e 's/^pyopenssl==21\.0\.0 ; python_version < '\''3\.12'\''.*/pyopenssl==24.1.0 ; python_version < '\''3\.12'\''/' \
            -e 's/^urllib3==1\.26\.5 ; python_version < '\''3\.12'\''.*/urllib3==2.0.7 ; python_version < '\''3\.12'\''/' \
            -e 's/^requests==2\.25\.1 ;  python_version < '\''3\.11'\''.*/requests==2.31.0 ;  python_version < '\''3\.11'\''/' \
            /opt/odoo/requirements.txt; \
    fi && \
    uv pip install -r /opt/odoo/requirements.txt && \
    uv pip install /opt/odoo && \
    echo "${ODOO_VERSION}|${ODOO_BUILD}" > /opt/odoo/.build_version

# ============================================
# 7. EXTRA PYTHON DEPENDENCIES
# ============================================
RUN uv pip install \
    dbfread \
    ebaysdk \
    firebase_admin \
    num2words \
    ofxparse \
    packaging \
    pdfminer.six \
    phonenumbers

# ============================================
# 8. WEB TERMINAL
# ============================================
COPY .data/web-terminal /opt/web-terminal
WORKDIR /opt/web-terminal
RUN uv pip install gyp-next && npm install && npm run build && \
    cp node_modules/@xterm/xterm/css/xterm.css public/
WORKDIR /

# ============================================
# 9. STRUCTURE & PERMISSIONS
# ============================================
RUN mkdir -p /mnt/extra-addons && chown -R odoo /mnt/extra-addons

# ============================================
# 10. ENTRYPOINT & SCRIPTS
# ============================================
COPY .data/docker/odoo/entrypoint.sh /entrypoint.sh
COPY .data/scripts/dev_db_bootstrap.sh \
     .data/scripts/check_modules.sh \
     .data/scripts/check_requirements.sh \
     .data/scripts/check_iot.sh \
     .data/scripts/check_iot_setup.sh \
     .data/scripts/generate_addons_path.sh \
     .data/scripts/odoo_header.sh \
     .data/scripts/hex_to_ansi.sh \
     .data/scripts/expand_modules.sh \
     .data/scripts/tmux_setup.sh \
     .data/scripts/webterm_env.sh \
     /usr/local/bin/
RUN chmod +x /entrypoint.sh /usr/local/bin/*.sh

# ============================================
# 11. VOLUMES & PORTS
# ============================================
VOLUME ["/var/lib/odoo", "/mnt/extra-addons", "/var/log/odoo"]
EXPOSE 8069 8071 8072 7681

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
