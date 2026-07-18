# Znuny LTS on Debian (vanilla upstream tarball).
#
# Build:
#   docker build --build-arg ZNUNY_VERSION=6.5.22 -t ghcr.io/cygnusnetworks/docker-znuny:6.5.22 .
#
# Volume design: /opt/otrs/Kernel stays inside the image. Only Kernel/Config.pm,
# optional Custom/ code and article storage are mounted at runtime, so an image
# update is a real code update.

FROM debian:trixie-slim

ARG ZNUNY_VERSION
ENV ZNUNY_VERSION=${ZNUNY_VERSION}
ENV OTRS_ROOT=/opt/otrs
ENV LANG=C.UTF-8

LABEL org.opencontainers.image.title="znuny" \
      org.opencontainers.image.description="Znuny LTS on Debian (Apache + mod_perl)" \
      org.opencontainers.image.source="https://github.com/CygnusNetworks/docker-znuny" \
      org.opencontainers.image.url="https://github.com/CygnusNetworks/docker-znuny" \
      org.opencontainers.image.documentation="https://github.com/CygnusNetworks/docker-znuny#readme" \
      org.opencontainers.image.licenses="AGPL-3.0" \
      org.opencontainers.image.vendor="CygnusNetworks" \
      org.opencontainers.image.version="${ZNUNY_VERSION}"

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    apache2 \
    libapache2-mod-perl2 \
    libapache2-reload-perl \
    supervisor \
    cron \
    curl \
    ca-certificates \
    patch \
    procps \
    mariadb-client \
    libarchive-zip-perl \
    libauthen-ntlm-perl \
    libauthen-sasl-perl \
    libcrypt-eksblowfish-perl \
    libdata-uuid-perl \
    libhash-merge-perl \
    libical-parser-perl \
    libcss-minifier-xs-perl \
    libjavascript-minifier-xs-perl \
    libdatetime-perl \
    libdatetime-timezone-perl \
    libdbi-perl \
    libdbd-mysql-perl \
    libencode-hanextra-perl \
    libgd-graph-perl \
    libgd-text-perl \
    libio-socket-ssl-perl \
    libjson-xs-perl \
    libmail-imapclient-perl \
    libmoo-perl \
    libnamespace-clean-perl \
    libnet-dns-perl \
    libnet-ldap-perl \
    libtemplate-perl \
    libtext-csv-xs-perl \
    libtimedate-perl \
    libxml-libxml-perl \
    libxml-libxslt-perl \
    libxml-parser-perl \
    libyaml-libyaml-perl \
    libspreadsheet-xlsx-perl \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -d ${OTRS_ROOT} -c 'Znuny user' -s /bin/bash -G www-data otrs

# Official tarball + checksum from download.znuny.org
# Keep the upstream filename so sha256sum -c matches the published .sha256 file.
RUN set -euo pipefail; \
    test -n "${ZNUNY_VERSION}"; \
    cd /tmp; \
    curl -fsSL "https://download.znuny.org/releases/znuny-${ZNUNY_VERSION}.tar.gz" \
      -o "znuny-${ZNUNY_VERSION}.tar.gz"; \
    curl -fsSL "https://download.znuny.org/releases/znuny-${ZNUNY_VERSION}.tar.gz.sha256" \
      -o "znuny-${ZNUNY_VERSION}.tar.gz.sha256"; \
    sha256sum -c "znuny-${ZNUNY_VERSION}.tar.gz.sha256"; \
    tar -xzf "znuny-${ZNUNY_VERSION}.tar.gz" -C /opt; \
    mv "/opt/znuny-${ZNUNY_VERSION}" ${OTRS_ROOT}; \
    rm -f "znuny-${ZNUNY_VERSION}.tar.gz" "znuny-${ZNUNY_VERSION}.tar.gz.sha256"

# Optional version-specific patches (patches/<version>/*.patch). Empty by default.
COPY patches /tmp/patches
RUN if [ -d "/tmp/patches/${ZNUNY_VERSION}" ] && ls "/tmp/patches/${ZNUNY_VERSION}"/*.patch >/dev/null 2>&1; then \
        set -e; \
        for p in /tmp/patches/${ZNUNY_VERSION}/*.patch; do \
            echo "Applying $p"; \
            patch -p1 -d ${OTRS_ROOT} --fuzz=0 < "$p"; \
        done; \
    fi \
    && rm -rf /tmp/patches

# Placeholder config; bind-mount a real Kernel/Config.pm at runtime.
RUN cp ${OTRS_ROOT}/Kernel/Config.pm.dist ${OTRS_ROOT}/Kernel/Config.pm

# Fail the build if a required Perl module is missing or core modules do not compile.
RUN ${OTRS_ROOT}/bin/otrs.CheckModules.pl | tee /tmp/checkmodules.out \
    && ! grep -E 'Not installed!.*required' /tmp/checkmodules.out \
    && rm /tmp/checkmodules.out \
    && cd ${OTRS_ROOT} && perl -I. -I Kernel/cpan-lib -cw Kernel/System/Queue.pm \
    && perl -I. -I Kernel/cpan-lib -cw Kernel/System/TemplateGenerator.pm \
    && perl -I. -I Kernel/cpan-lib -cw bin/otrs.Console.pl

# Apache: mod_perl needs the prefork MPM; Znuny ships its own include config.
RUN a2dismod -q mpm_event \
    && a2enmod -q mpm_prefork headers \
    && ln -s ${OTRS_ROOT}/scripts/apache2-httpd.include.conf /etc/apache2/conf-enabled/zzz_znuny.conf \
    && echo 'ServerName localhost' > /etc/apache2/conf-enabled/servername.conf \
    && rm -f /etc/apache2/sites-enabled/000-default.conf \
    && ln -sf /dev/stdout /var/log/apache2/access.log \
    && ln -sf /dev/stderr /var/log/apache2/error.log

# Pass REMOTE_USER from a reverse proxy (X-Forwarded-User) for
# Kernel::System::Auth::HTTPBasicAuth / SSO setups.
RUN printf 'SetEnvIf X-Forwarded-User "(.*)" REMOTE_USER=$1\n' > /etc/apache2/conf-enabled/auth-forward.conf

RUN ${OTRS_ROOT}/bin/otrs.SetPermissions.pl --web-group=www-data

COPY container/supervisord.conf /etc/supervisor/conf.d/znuny.conf
COPY container/entrypoint.sh /entrypoint.sh
RUN chmod 755 /entrypoint.sh

EXPOSE 80

HEALTHCHECK --interval=1m --timeout=10s --retries=3 --start-period=2m \
    CMD curl -f http://localhost/otrs/index.pl || exit 1

ENTRYPOINT ["/entrypoint.sh"]
