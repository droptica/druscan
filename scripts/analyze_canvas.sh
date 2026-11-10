#!/bin/bash
# Script: Analyze Drupal Canvas
# Purpose: Check if the Drupal Canvas page builder (drupal/canvas) is used and how
# Returns: JSON object with module status and version, pages built with Canvas,
#          components by source (code-defined, created in the browser, blocks),
#          custom components, content templates, page regions, patterns
#
# Note: All data is collected by scripts/php/canvas.php with one drush call
#       (one Drupal bootstrap). Extend the PHP file instead of adding "ddev drush" calls here.
#       Works also when Canvas is not installed (module.enabled = false, empty lists).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/drush_php.sh"

drush_php "${SCRIPT_DIR}/php/canvas.php" 2>/dev/null
