#!/bin/bash

# Helper Script: Reuse a value already computed in the current section
# Purpose: Avoid running the same analysis twice. Some sections store a full analysis
#          (e.g., seo_analysis.full_analysis) and also its parts as separate keys
#          (e.g., seo_analysis.sitemap). The parts are copied from the full analysis.
#
# Usage in commands_registry.sh:
#   bash ${BASE_DIR}/scripts/reuse_section_key.sh <full_key> <sub_key> <fallback command...>
#
# Example:
#   bash ${BASE_DIR}/scripts/reuse_section_key.sh full_analysis sitemap bash ${BASE_DIR}/scripts/analyze_seo.sh sitemap
#
# How it works:
#   - SECTION_JSON (exported by audit.sh) points to the JSON collected so far for this section
#   - If .<full_key>.<sub_key> exists there, print it (no extra work)
#   - Otherwise (full analysis failed or key is missing) run the fallback command

FULL_KEY="$1"
SUB_KEY="$2"

if [ -z "$FULL_KEY" ] || [ -z "$SUB_KEY" ] || [ "$#" -lt 3 ]; then
    echo "Usage: reuse_section_key.sh <full_key> <sub_key> <fallback command...>" >&2
    exit 1
fi
shift 2

if [ -n "${SECTION_JSON:-}" ] && [ -f "$SECTION_JSON" ]; then
    VALUE=$(jq --arg full "$FULL_KEY" --arg sub "$SUB_KEY" \
        '.[$full] | objects | select(has($sub)) | .[$sub]' "$SECTION_JSON" 2>/dev/null)
    if [ -n "$VALUE" ]; then
        echo "$VALUE"
        exit 0
    fi
fi

echo "reuse_section_key.sh: ${FULL_KEY}.${SUB_KEY} not available, running: $*" >&2
exec "$@"
