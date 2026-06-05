FROM alpine:3.19

RUN apk add --no-cache bash ca-certificates curl gzip p7zip zstd

ARG SQLCMD_VER=1.8.1
RUN curl -fsSL "https://github.com/microsoft/go-sqlcmd/releases/download/v${SQLCMD_VER}/sqlcmd-linux-amd64.tar.bz2" \
    | tar -xj -C /usr/local/bin sqlcmd \
    && chmod +x /usr/local/bin/sqlcmd

COPY crontab /etc/crontabs/root
COPY scripts/ /scripts/
RUN chmod +x /scripts/*.sh

ENTRYPOINT ["/scripts/entrypoint.sh"]
