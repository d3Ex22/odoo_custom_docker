FROM ubuntu:jammy

# ============================================
# 1. SYSTEM DEPENDENCIES + POSTGRESQL CLIENT
# ============================================
RUN export DEBIAN_FRONTEND=noninteractive && apt-get update && \
    apt-get install -y ca-certificates curl gnupg && \
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt jammy-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
    apt-get update && apt-get install -y \
        gettext-base \
        git \
        openssh-client \
        p7zip-full \
        postgresql-client \
        python3 \
        sudo \
        tmux \
        tzdata \
        unzip \
        zip \
        zsh \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=C.UTF-8 LC_ALL=C.UTF-8

# The web terminal (.data/web-terminal: committed xterm.js bundle + Python
# server) runs from the mounted project folder, no Node.js in the image; the
# browser renders the fonts. ngrok is not in the image either: 'grok'
# downloads it on first use.

# ============================================
# 2. STARSHIP PROMPT
# ============================================
RUN curl -fsSL https://starship.rs/install.sh | sh -s -- -y

# ============================================
# 3. DOCKER CLI
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
# 4. UTILS USER + PYTHON SYMLINK
# ============================================
RUN ln -sf /usr/bin/python3 /usr/bin/python && \
    useradd -m -s /bin/zsh utils && \
    echo "utils:utils" | chpasswd && \
    usermod -aG sudo utils && \
    echo "utils ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    mkdir -p /home/utils/.ssh && \
    chown -R utils:utils /home/utils/.ssh

# ============================================
# 5. OH MY ZSH
# ============================================
RUN HOME=/home/utils sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended && \
    git clone https://github.com/zsh-users/zsh-autosuggestions /home/utils/.oh-my-zsh/custom/plugins/zsh-autosuggestions && \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting /home/utils/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting && \
    git clone https://github.com/MichaelAquilina/zsh-you-should-use /home/utils/.oh-my-zsh/custom/plugins/you-should-use && \
    chown -R utils:utils /home/utils/.oh-my-zsh /home/utils/.zshrc

# ============================================
# 6. SHELL ENVIRONMENT
# ============================================
RUN printf '%s\n' \
    'export ZSH="$HOME/.oh-my-zsh"' \
    'export STARSHIP_CONFIG=/home/utils/starship.toml' \
    'source /home/utils/odoo_custom_docker/.data/scripts/zshrc.sh' \
    '[ -f /home/utils/odoo_custom_docker/.config/utils/.zshrc ] && source /home/utils/odoo_custom_docker/.config/utils/.zshrc' \
    > /home/utils/.zshrc && \
    chown utils:utils /home/utils/.zshrc

EXPOSE 7681

WORKDIR /home/utils

# Entrypoint read from the mounted project folder: no rebuild when it changes
# (the image revision in the tag only covers this Dockerfile).
ENTRYPOINT ["/bin/bash", "/home/utils/odoo_custom_docker/.data/docker/utils/entrypoint.sh"]
