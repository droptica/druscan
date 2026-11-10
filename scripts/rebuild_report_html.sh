#!/bin/bash

# Helper Script: Rebuild report HTML from existing JSON (developer tool)
# Purpose: Test changes in ./template/ without running the whole audit again.
#          Takes JSON files from an existing report and injects them into a fresh
#          copy of the current HTML template.
#
# Usage (from the DRUSCAN repository root):
#   bash scripts/rebuild_report_html.sh audits_reports/{timestamp}_{site_name} [output_dir_name]
#
# Example:
#   bash scripts/rebuild_report_html.sh audits_reports/2026-11-10_15-27-42_mysite.com
#   -> writes audits_reports/2026-11-10_15-27-42_mysite.com/html_preview/index.html
#
# Notes:
#   - Default output directory name is "html_preview" (the original "html" is not touched)
#   - KEEP_AI_PAGES=1 copies executive_summary.html and action_items.html from the existing
#     "html" directory (use it when the AI analysis was already written there)
#   - JSON injection works the same way as in audit.sh (keep both in sync)

REPORT_DIR="${1%/}"
OUTPUT_NAME="${2:-html_preview}"
BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE_DIR="${BASE_DIR}/template/drupal_audit_template"

if [ -z "$REPORT_DIR" ] || [ ! -d "${REPORT_DIR}/json" ]; then
    echo "Usage: bash scripts/rebuild_report_html.sh <report_dir> [output_dir_name]" >&2
    echo "Error: <report_dir>/json not found" >&2
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed" >&2
    exit 1
fi

OUTPUT_DIR="${REPORT_DIR}/${OUTPUT_NAME}"
rm -rf "$OUTPUT_DIR"
cp -r "$TEMPLATE_DIR" "$OUTPUT_DIR" || exit 1

# Sidebar metadata (same placeholders as in audit.sh)
REPORT_NAME="$(basename "$REPORT_DIR")"
AUDIT_DATE="${REPORT_NAME:0:10}"
SITE_NAME="${REPORT_NAME:20}"
DRUPAL_VERSION="$(jq -r '.system_information.drupal_version // "Unknown"' "${REPORT_DIR}/json/system_information.json" 2>/dev/null | head -1)"
AUDIT_BY="${AUDITOR:-$(whoami)}"

INDEX_HTML="${OUTPUT_DIR}/index.html"
sed -i.bak "s/\[Site Name\]/${SITE_NAME}/g" "$INDEX_HTML"
sed -i.bak "s/\[Drupal Version\]/${DRUPAL_VERSION:-Unknown}/g" "$INDEX_HTML"
sed -i.bak "s/\[Date\]/${AUDIT_DATE}/g" "$INDEX_HTML"
sed -i.bak "s/\[Auditor Name\]/${AUDIT_BY}/g" "$INDEX_HTML"
rm -f "${INDEX_HTML}.bak"

# Inject JSON of every section into templates with the matching placeholder
INJECTED=0
for json_file in "${REPORT_DIR}"/json/*.json; do
    section="$(basename "$json_file" .json)"
    json_content=$(jq -c ".${section}" "$json_file" 2>/dev/null)
    if [ -z "$json_content" ] || [ "$json_content" = "null" ]; then
        echo "  ! ${section}: no data in JSON file, skipped" >&2
        continue
    fi

    json_escaped=$(echo "$json_content" | sed 's/[&/\|]/\\&/g')
    section_upper=$(echo "$section" | tr '[:lower:]' '[:upper:]')
    placeholder="__${section_upper}_JSON_PLACEHOLDER__"

    html_files=$(grep -l "$placeholder" "${OUTPUT_DIR}/includes/"*.html 2>/dev/null)
    if [ -z "$html_files" ]; then
        echo "  ! ${section}: no template with placeholder ${placeholder}" >&2
        continue
    fi

    while IFS= read -r html_file; do
        sed -i.bak "s|${placeholder}|${json_escaped}|g" "$html_file"
        rm -f "${html_file}.bak"
    done <<< "$html_files"
    INJECTED=$((INJECTED + 1))
done

# Optional: keep AI-written pages from the existing report (KEEP_AI_PAGES=1)
if [ "${KEEP_AI_PAGES:-0}" = "1" ]; then
    for page in executive_summary.html action_items.html; do
        existing="${REPORT_DIR}/html/includes/${page}"
        if [ -f "$existing" ]; then
            cp "$existing" "${OUTPUT_DIR}/includes/${page}"
            echo "  kept existing page: ${page}"
        fi
    done
fi

echo "Sections injected: ${INJECTED}"
echo "Preview: ${OUTPUT_DIR}/index.html"
