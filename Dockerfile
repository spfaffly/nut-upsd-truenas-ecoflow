FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV NUT_VERSION=2.8.4
ENV PATH=/usr/local/ups/sbin:/usr/local/ups/bin:${PATH}

RUN apt-get update \
        && apt-get install -y --no-install-recommends \
            ca-certificates \
            wget \
            xz-utils \
            build-essential \
            pkg-config \
            libtool \
            autoconf \
            automake \
            libusb-1.0-0 \
            libusb-1.0-0-dev \
        && groupadd -r nut \
        && useradd -r -g nut -d /var/lib/nut -s /usr/sbin/nologin nut \
        && mkdir -p /var/lib/nut /run/nut /etc/nut \
        && chown nut:nut /var/lib/nut /run/nut \
        && wget -q -O /tmp/nut.tar.gz "https://github.com/networkupstools/nut/releases/download/v${NUT_VERSION}/nut-${NUT_VERSION}.tar.gz" \
        && tar -xzf /tmp/nut.tar.gz -C /tmp \
        && cd /tmp/nut-${NUT_VERSION} \
        && ./configure --with-usb --with-user=nut --with-group=nut \
        && make -j"$(nproc)" \
        && make install \
        && rm -rf /tmp/nut.tar.gz /tmp/nut-${NUT_VERSION} \
        && apt-get purge -y --auto-remove \
            wget \
            xz-utils \
            build-essential \
            pkg-config \
            libtool \
            autoconf \
            automake \
            libusb-1.0-0-dev \
    && rm -rf /var/lib/apt/lists/*

COPY docker/nut.conf /etc/nut/nut.conf
COPY docker/ups.conf /etc/nut/ups.conf
COPY docker/upsd.conf /etc/nut/upsd.conf
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 3493

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
