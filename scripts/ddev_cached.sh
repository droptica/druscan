#!/bin/bash

# Helper Script: Cached ddev wrapper
# Purpose: Avoid running the same slow, read-only ddev command many times during one audit
#          (e.g., "ddev drush pm:list --format=json" is called 50+ times by registry and scripts)
#
# How it works:
#   audit.sh puts a copy of this file named "ddev" at the front of PATH.
#   Every "ddev ..." call from commands_registry.sh and ./scripts/ goes through this wrapper.
#   - Read-only commands from the list below: first result is saved, next identical calls
#     (same arguments) are answered from the cache.
#   - Commands that change module state (pm:enable, pm:uninstall, ...): cache is cleared.
#   - Everything else: passed to the real ddev unchanged.
#
# Environment (set by audit.sh):
#   DRUSCAN_REAL_DDEV  - path to the real ddev binary (required)
#   DRUSCAN_CACHE_DIR  - cache directory for this audit run (removed when audit ends)
#   DRUSCAN_NO_CACHE=1 - disable caching (pass everything to the real ddev)

REAL_DDEV="${DRUSCAN_REAL_DDEV:-}"
CACHE_DIR="${DRUSCAN_CACHE_DIR:-}"

if [ -z "$REAL_DDEV" ] || [ ! -x "$REAL_DDEV" ]; then
    echo "ddev_cached.sh: DRUSCAN_REAL_DDEV is not set or not executable" >&2
    exit 127
fi

if [ -z "$CACHE_DIR" ] || [ ! -d "$CACHE_DIR" ] || [ "${DRUSCAN_NO_CACHE:-0}" = "1" ]; then
    exec "$REAL_DDEV" "$@"
fi

case "${1:-} ${2:-}" in
    # Read-only commands that are repeated with identical arguments
    "drush pm:list" | "drush config:status" | "composer outdated" | "composer show")
        ;;

    # Commands that change module state or caches - cached results are no longer valid
    "drush pm:enable" | "drush pm:install" | "drush en" | \
    "drush pm:uninstall" | "drush pmu" | \
    "drush cr" | "drush cache:rebuild" | \
    "drush config:import" | "drush cim" | "drush config:set" | "drush cset" | \
    "drush updatedb" | "drush updb" | \
    "composer require" | "composer remove" | "composer update" | "composer install")
        rm -f "$CACHE_DIR"/cmd_* 2>/dev/null
        exec "$REAL_DDEV" "$@"
        ;;

    *)
        exec "$REAL_DDEV" "$@"
        ;;
esac

# Cache key: checksum of all arguments (one per line, so "a b" and "a" "b" differ)
CACHE_KEY=$(printf '%s\n' "$@" | cksum | tr -s ' ' '_')
CACHE_FILE="${CACHE_DIR}/cmd_${CACHE_KEY}"

if [ -f "$CACHE_FILE" ]; then
    echo "$*" >> "${CACHE_DIR}/hits.log"
    cat "$CACHE_FILE"
    exit 0
fi

TMP_FILE="${CACHE_FILE}.tmp.$$"
"$REAL_DDEV" "$@" > "$TMP_FILE"
EXIT_CODE=$?

cat "$TMP_FILE"

# Cache only successful, non-empty results (failures are retried on the next call)
if [ "$EXIT_CODE" -eq 0 ] && [ -s "$TMP_FILE" ]; then
    mv "$TMP_FILE" "$CACHE_FILE"
else
    rm -f "$TMP_FILE"
fi

exit "$EXIT_CODE"
