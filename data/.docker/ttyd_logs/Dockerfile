FROM tsl0922/ttyd:latest

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        docker.io \
        tmux \
        locales && \
    locale-gen en_US.UTF-8 && \
    rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

COPY data/.docker/ttyd_logs/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
