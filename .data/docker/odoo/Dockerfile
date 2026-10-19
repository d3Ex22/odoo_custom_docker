# Two stages: 'builder' compiles the virtualenv (compilers, -dev headers), the
# final image only carries the runtime libraries + the venv and interpreter
# copied from it (~400 MB lighter, no toolchain to keep updated).
FROM ubuntu:26.04 AS base

ARG ODOO_VERSION
ARG PYTHON_VERSION
ARG TARGETARCH

ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
ENV ODOO_VERSION=${ODOO_VERSION}
ENV ODOO_RC=/etc/odoo/odoo.conf
ENV VIRTUAL_ENV=/opt/venv
ENV PATH="${VIRTUAL_ENV}/bin:/opt/odoo:${PATH}"
# No wheel cache in the image layers (~2 GB otherwise)
ENV UV_NO_CACHE=1
# uv-managed interpreters live here in both stages
ENV UV_PYTHON_INSTALL_DIR=/opt/python

SHELL ["/bin/bash", "-xo", "pipefail", "-c"]

# ============================================
# 1. RUNTIME SYSTEM DEPENDENCIES (shared by both stages)
# ============================================
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        fonts-noto-cjk \
        git \
        libcairo2 \
        libcups2t64 \
        libldap2 \
        libpq5 \
        libsasl2-2 \
        libxml2-16 \
        libxmlsec1-1 \
        libxmlsec1-openssl1 \
        libxslt1.1 \
        npm \
        postgresql-client \
        tmux \
        tini && \
    if [ "$ODOO_VERSION" != "14.0" ] && [ "$ODOO_VERSION" != "15.0" ]; then \
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends libmagic1t64; \
    fi && \
    npm install -g rtlcss && \
    npm cache clean --force && \
    rm -rf /var/lib/apt/lists/* /usr/share/doc /usr/share/man

RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

# ============================================
# 2. BUILDER: toolchain + headers, Python, Odoo requirements compiled here
# ============================================
FROM base AS builder

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential \
        libcairo2-dev \
        libcups2-dev \
        libffi-dev \
        libldap2-dev \
        libpq-dev \
        libsasl2-dev \
        libssl-dev \
        libxml2-dev \
        libxmlsec1-dev \
        libxslt1-dev \
        swig && \
    rm -rf /var/lib/apt/lists/*

RUN uv python install ${PYTHON_VERSION} && \
    uv venv --seed --python ${PYTHON_VERSION} ${VIRTUAL_ENV} && \
    if [ "$ODOO_VERSION" = "17.0" ]; then \
        uv pip install --upgrade pip wheel "setuptools<71"; \
    else \
        uv pip install --upgrade pip wheel setuptools; \
    fi

# ============================================
# 3. ODOO INSTALLATION FROM SOURCE (builder)
# ============================================
# Editable install: the venv points to /opt/odoo instead of holding a second
# copy of the source (halves the layer).
# ODOO_BUILD is declared here on purpose: with BuildKit every RUN after an ARG
# declaration is invalidated when its value changes, so a new nightly build
# only re-runs this layer and the following ones (system deps stay cached).
# 'latest' is resolved to the real build date so .build_version always holds
# a comparable value (rebuild / status bar rely on it).
ARG ODOO_BUILD
RUN BUILD="${ODOO_BUILD}" && \
    if [ "$BUILD" = "latest" ]; then \
        BUILD=$(curl -s "https://nightly.odoo.com/${ODOO_VERSION}/nightly/src/" \
            | grep -oP "odoo_${ODOO_VERSION}\.\K\d{8}(?=\.tar\.gz)" | sort -r | head -1); \
        BUILD="${BUILD:-latest}"; \
    fi && \
    mkdir -p /opt/odoo && \
    curl -sSL https://nightly.odoo.com/${ODOO_VERSION}/nightly/src/odoo_${ODOO_VERSION}.${BUILD}.tar.gz | \
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
    uv pip install -e /opt/odoo && \
    rm -rf /opt/odoo/build && \
    find /opt/odoo /opt/venv -name '__pycache__' -type d -prune -exec rm -rf {} + && \
    echo "${ODOO_VERSION}|${BUILD}" > /opt/odoo/.build_version

# ============================================
# 4. EXTRA PYTHON DEPENDENCIES (builder)
# ============================================
RUN uv pip install \
    coverage \
    debugpy \
    ipython \
    dbfread \
    ebaysdk \
    firebase_admin \
    num2words \
    ofxparse \
    packaging \
    pdfminer.six \
    phonenumbers \
    rlPyCairo
# IoT Box mode (ODOO_IOT_BOX, Odoo 19+): its compiled deps are built here so
# check_iot.sh finds them at start (the final image has no compiler); one that
# fails only disables that part of IoT.
RUN for p in netifaces2 schedule websocket-client python-escpos pyudev zeroconf PyKCS11 evdev pycups; do \
        uv pip install "$p" || echo "IoT dep skipped: $p"; \
    done

# ============================================
# 5. FINAL IMAGE: runtime libs + interpreter, venv and Odoo from the builder
# ============================================
FROM base

COPY --from=builder /opt/python /opt/python
COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /opt/odoo /opt/odoo

# ============================================
# 6. ODOO USER
# ============================================
RUN useradd -m -d /var/lib/odoo -U -r -s /bin/bash odoo

# ============================================
# 7. WKHTMLTOPDF
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
# 8. ENTRYPOINT (mounted, not copied)
# ============================================
# docker-compose.yml mounts .data/docker/odoo at /opt/env/odoo, .data/scripts
# at /opt/env/scripts (linked into /usr/local/bin by the entrypoint) and
# .data/web-terminal at /opt/web-terminal: editing them needs no rebuild (the
# image revision in the tag only covers this Dockerfile).
RUN mkdir -p /mnt/extra-addons && chown -R odoo /mnt/extra-addons
VOLUME ["/var/lib/odoo"]
EXPOSE 8069 8072 7681

ENTRYPOINT ["/usr/bin/tini", "--", "/bin/bash", "/opt/env/odoo/entrypoint.sh"]
