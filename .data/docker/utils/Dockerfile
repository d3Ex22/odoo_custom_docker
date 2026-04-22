FROM ubuntu:jammy

# ============================================
# 1. SYSTEM DEPENDENCIES + POSTGRESQL CLIENT
# ============================================
RUN apt-get update && \
    apt-get install -y ca-certificates curl gnupg && \
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt jammy-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
    apt-get update && apt-get install -y \
        fzf \
        fontconfig \
        gettext-base \
        git \
        jq \
        locales \
        openssh-client \
        p7zip-full \
        postgresql-client \
        python3 \
        python3-pip \
        rsync \
        sudo \
        tmux \
        unzip \
        zip \
        zsh \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# 2. NGROK
# ============================================
RUN curl -s https://ngrok-agent.s3.amazonaws.com/ngrok.asc | tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null && \
    echo "deb https://ngrok-agent.s3.amazonaws.com bookworm main" | tee /etc/apt/sources.list.d/ngrok.list && \
    apt-get update && apt-get install -y ngrok && \
    rm -rf /var/lib/apt/lists/*

# ============================================
# 3. NODE.JS + WEB TERMINAL
# ============================================
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

COPY .data/web-terminal /opt/web-terminal
WORKDIR /opt/web-terminal
RUN npm install -g node-gyp && npm install && npm run build && \
    cp node_modules/@xterm/xterm/css/xterm.css public/
WORKDIR /home/utils

# ============================================
# 4. STARSHIP PROMPT
# ============================================
RUN curl -fsSL https://starship.rs/install.sh | sh -s -- -y

ENV STARSHIP_CONFIG=/home/utils/starship.toml

# ============================================
# 5. NERD FONT (0xProto)
# ============================================
RUN mkdir -p /usr/share/fonts/nerd-fonts && \
    curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/0xProto.zip" -o /tmp/0xProto.zip && \
    unzip -q /tmp/0xProto.zip -d /usr/share/fonts/nerd-fonts && \
    fc-cache -f && rm /tmp/0xProto.zip

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# ============================================
# 6. DOCKER CLI
# ============================================
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && apt-get install -y docker-ce-cli && \
    rm -rf /var/lib/apt/lists/*

# ============================================
# 7. UTILS USER + PYTHON SYMLINK
# ============================================
RUN ln -sf /usr/bin/python3 /usr/bin/python && \
    useradd -m -s /bin/zsh utils && \
    echo "utils:utils" | chpasswd && \
    usermod -aG sudo utils && \
    echo "utils ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    mkdir -p /home/utils/.ssh && \
    chown -R utils:utils /home/utils/.ssh

# ============================================
# 8. OH MY ZSH
# ============================================
RUN HOME=/home/utils sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended && \
    git clone https://github.com/zsh-users/zsh-autosuggestions /home/utils/.oh-my-zsh/custom/plugins/zsh-autosuggestions && \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting /home/utils/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting && \
    git clone https://github.com/MichaelAquilina/zsh-you-should-use /home/utils/.oh-my-zsh/custom/plugins/you-should-use && \
    chown -R utils:utils /home/utils/.oh-my-zsh /home/utils/.zshrc

# ============================================
# 9. SHELL ENVIRONMENT
# ============================================
RUN printf '%s\n' \
    'export ZSH="$HOME/.oh-my-zsh"' \
    'export STARSHIP_CONFIG=/home/utils/starship.toml' \
    '[ -f /home/utils/odoo_custom_docker/.config/utils/.zshrc ] && source /home/utils/odoo_custom_docker/.config/utils/.zshrc' \
    > /home/utils/.zshrc && \
    chown utils:utils /home/utils/.zshrc

COPY .data/docker/utils/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 7681

WORKDIR /home/utils

ENTRYPOINT ["/entrypoint.sh"]
