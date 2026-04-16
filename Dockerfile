FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends nut \
    && rm -rf /var/lib/apt/lists/*

COPY docker/nut.conf /etc/nut/nut.conf
COPY docker/ups.conf /etc/nut/ups.conf
COPY docker/upsd.conf /etc/nut/upsd.conf
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 3493

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
