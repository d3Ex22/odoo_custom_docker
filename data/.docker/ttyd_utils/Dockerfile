FROM tsl0922/ttyd:latest

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        docker.io \
        tmux \
        locales \
        curl \
        ca-certificates \
        gnupg && \
    locale-gen en_US.UTF-8 && \
    curl -s https://ngrok-agent.s3.amazonaws.com/ngrok.asc | tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null && \
    echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | tee /etc/apt/sources.list.d/ngrok.list && \
    apt-get update && apt-get install -y ngrok && \
    rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

COPY data/.docker/ttyd_utils/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
