#!/bin/bash
# Znuny container entrypoint.
#
# Expects Kernel/Config.pm to be bind-mounted with valid DB credentials.
# Environment flags:
#   ZNUNY_SKIP_REBUILD=1   skip Maint::Config::Rebuild (e.g. before running a
#                          migration script)
#   ZNUNY_SKIP_DAEMON=1    do not start the Znuny daemon / cron jobs
set -e

OTRS_ROOT=${OTRS_ROOT:-/opt/otrs}
cd "$OTRS_ROOT"

# If a command is given (e.g. docker run ... bash), run it directly instead of
# booting the full stack.
if [ $# -gt 0 ]; then
    exec "$@"
fi

if grep -q 'otrs-dummy-host-placeholder' Kernel/Config.pm 2>/dev/null || ! grep -q 'DatabaseHost' Kernel/Config.pm; then
    echo "WARNING: Kernel/Config.pm looks like the dist placeholder - did you forget to mount it?" >&2
fi

bin/otrs.SetPermissions.pl --web-group=www-data

echo "Waiting for database..."
for i in $(seq 1 60); do
    if su -s /bin/bash otrs -c "bin/otrs.Console.pl Maint::Database::Check" >/dev/null 2>&1; then
        echo "Database is up."
        break
    fi
    if [ "$i" = "60" ]; then
        echo "ERROR: database not reachable after 300s" >&2
        exit 1
    fi
    sleep 5
done

if [ "${ZNUNY_SKIP_REBUILD}" != "1" ]; then
    # OPM package files live in the container layer and are lost on container
    # recreate; the DB (package_repository) still has them - restore the files.
    su -s /bin/bash otrs -c "bin/otrs.Console.pl Admin::Package::ReinstallAll" || true
    su -s /bin/bash otrs -c "bin/otrs.Console.pl Maint::Config::Rebuild" || true
    su -s /bin/bash otrs -c "bin/otrs.Console.pl Maint::Cache::Delete" || true
fi

if [ "${ZNUNY_SKIP_DAEMON}" != "1" ]; then
    # Install cron jobs (includes the daemon watchdog) and start the daemon.
    su -s /bin/bash otrs -c "cd var/cron && for f in *.dist; do cp -n \"\$f\" \"\${f%.dist}\"; done"
    su -s /bin/bash otrs -c "bin/Cron.sh start" || true
    su -s /bin/bash otrs -c "bin/otrs.Daemon.pl start" || true
fi

exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
