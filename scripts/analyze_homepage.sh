#!/bin/bash
# Script: Analyze Homepage Configuration
# Purpose: Comprehensive analysis of Drupal homepage configuration
# Returns: JSON object with homepage path, type, blocks, views, Layout Builder info
#
# Note: All data is collected by scripts/php/homepage.php with one drush call
#       (one Drupal bootstrap). Extend the PHP file instead of adding "ddev drush" calls here.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/drush_php.sh"

# Verify DOCROOT is set
if [ -z "$DOCROOT" ]; then
    echo "{}"
    exit 0
fi

drush_php "${SCRIPT_DIR}/php/homepage.php" 2>/dev/null
