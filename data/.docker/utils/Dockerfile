FROM ubuntu:jammy

# Add PostgreSQL official repo for latest client
RUN apt-get update && apt-get install -y ca-certificates curl gnupg && \
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt jammy-pgdg main" > /etc/apt/sources.list.d/pgdg.list

RUN apt-get update && apt-get install -y \
    jq \
    fzf \
    bash-completion \
    python3 \
    python3-pip \
    rsync \
    locales \
    postgresql-client \
    zip \
    unzip \
    p7zip-full \
    openssh-client \
    sudo \
    fontconfig \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# Gum (TUI components)
ARG GUM_VERSION=0.14.5
RUN curl -fsSL "https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}/gum_${GUM_VERSION}_amd64.deb" -o /tmp/gum.deb && \
    dpkg -i /tmp/gum.deb && rm /tmp/gum.deb

# Starship prompt
RUN curl -fsSL https://starship.rs/install.sh | sh -s -- -y

# Nerd Font (0xProto)
RUN mkdir -p /usr/share/fonts/nerd-fonts && \
    curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/0xProto.zip" -o /tmp/0xProto.zip && \
    unzip -q /tmp/0xProto.zip -d /usr/share/fonts/nerd-fonts && \
    fc-cache -f && rm /tmp/0xProto.zip

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc

RUN echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null

RUN apt-get update && apt-get install -y docker-ce-cli && \
    rm -rf /var/lib/apt/lists/*

RUN ln -sf /usr/bin/python3 /usr/bin/python

RUN useradd -m -s /bin/bash odoo && \
    echo "odoo:odoo" | chpasswd && \
    usermod -aG sudo odoo && \
    mkdir -p /home/odoo/.ssh && \
    chown -R odoo:odoo /home/odoo/.ssh

RUN echo "odoo ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Starship config
ENV STARSHIP_CONFIG=/home/odoo/docker_dev/data/.docker/utils/config/starship.toml
RUN echo 'eval "$(starship init bash)"' >> /home/odoo/.bashrc

# Source theme and UI library
RUN echo 'source /home/odoo/docker_dev/data/.docker/utils/config/theme.conf 2>/dev/null' >> /home/odoo/.bashrc && \
    echo 'source /home/odoo/docker_dev/data/.docker/utils/lib/ui.sh 2>/dev/null' >> /home/odoo/.bashrc

# Aliases (alphabetical order by category)
RUN echo '# Odoo Commands' >> /home/odoo/.bashrc && \
    echo 'alias reboot="/home/odoo/docker_dev/data/.docker/utils/commands/reboot.sh"' >> /home/odoo/.bashrc && \
    echo 'alias r="reboot"' >> /home/odoo/.bashrc && \
    echo 'alias rebuild="/home/odoo/docker_dev/data/.docker/utils/commands/rebuild.sh"' >> /home/odoo/.bashrc && \
    echo 'alias set="/home/odoo/docker_dev/data/.docker/utils/commands/set.sh"' >> /home/odoo/.bashrc && \
    echo 'alias shell="/home/odoo/docker_dev/data/.docker/utils/commands/shell.sh"' >> /home/odoo/.bashrc && \
    echo 'alias start="/home/odoo/docker_dev/data/.docker/utils/commands/start.sh"' >> /home/odoo/.bashrc && \
    echo 'alias s="start"' >> /home/odoo/.bashrc && \
    echo 'alias stop="/home/odoo/docker_dev/data/.docker/utils/commands/stop.sh"' >> /home/odoo/.bashrc && \
    echo 'alias update="/home/odoo/docker_dev/data/.docker/utils/commands/update.sh"' >> /home/odoo/.bashrc && \
    echo 'alias u="update"' >> /home/odoo/.bashrc && \
    echo '# Database Commands' >> /home/odoo/.bashrc && \
    echo 'alias cheat="/home/odoo/docker_dev/data/.docker/utils/commands/cheat.sh"' >> /home/odoo/.bashrc && \
    echo 'alias database="/home/odoo/docker_dev/data/.docker/utils/commands/database.sh"' >> /home/odoo/.bashrc && \
    echo 'alias db="database"' >> /home/odoo/.bashrc && \
    echo 'alias fix-reports="/home/odoo/docker_dev/data/.docker/utils/commands/fix-reports.sh"' >> /home/odoo/.bashrc && \
    echo 'alias migrate="/home/odoo/docker_dev/data/.docker/utils/commands/migrate.sh"' >> /home/odoo/.bashrc && \
    echo 'alias psql="/home/odoo/docker_dev/data/.docker/utils/commands/psql.sh"' >> /home/odoo/.bashrc && \
    echo 'alias status="/home/odoo/docker_dev/data/.docker/utils/commands/status.sh"' >> /home/odoo/.bashrc && \
    echo '# Tools' >> /home/odoo/.bashrc && \
    echo 'alias check_versions="/home/odoo/docker_dev/data/.docker/utils/commands/check_versions.sh"' >> /home/odoo/.bashrc && \
    echo 'alias grok="/home/odoo/docker_dev/data/.docker/utils/commands/grok.sh"' >> /home/odoo/.bashrc && \
    echo 'alias help="source /home/odoo/.welcome"' >> /home/odoo/.bashrc && \
    echo 'alias pip="/home/odoo/docker_dev/data/.docker/utils/commands/pip.sh"' >> /home/odoo/.bashrc && \
    echo 'alias pre-commit="/home/odoo/docker_dev/data/.docker/utils/commands/pre-commit.sh"' >> /home/odoo/.bashrc && \
    echo 'alias pc="pre-commit"' >> /home/odoo/.bashrc && \
    echo 'alias requirements="/home/odoo/docker_dev/data/.docker/utils/commands/requirements.sh"' >> /home/odoo/.bashrc && \
    echo 'alias test-ui="/home/odoo/docker_dev/data/.docker/utils/commands/test-ui.sh"' >> /home/odoo/.bashrc && \
    echo 'alias upgrade-code="/home/odoo/docker_dev/data/.docker/utils/commands/upgrade-code.sh"' >> /home/odoo/.bashrc

# Auto-completion
RUN echo '' >> /home/odoo/.bashrc && \
    echo '[ -f /home/odoo/docker_dev/.env ] && source /home/odoo/docker_dev/.env' >> /home/odoo/.bashrc && \
    echo '[ -f /home/odoo/docker_dev/data/.docker/utils/commands/utils/completion.sh ] && source /home/odoo/docker_dev/data/.docker/utils/commands/utils/completion.sh' >> /home/odoo/.bashrc

# Welcome screen (commands list) - sourced from .welcome generated at runtime
RUN echo '' >> /home/odoo/.bashrc && \
    echo '[ -f /home/odoo/.welcome ] && source /home/odoo/.welcome' >> /home/odoo/.bashrc

COPY data/.docker/utils/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /home/odoo

ENTRYPOINT ["/entrypoint.sh"]
