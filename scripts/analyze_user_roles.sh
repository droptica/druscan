#!/bin/bash
# Script: Analyze User Roles and Permissions
# Purpose: Generate comprehensive JSON data for users, roles, and permissions
# Returns: JSON object with user statistics, roles, permissions, and security analysis
#
# Note: All data is collected by scripts/php/user_roles.php with one drush call
#       (one Drupal bootstrap). Extend the PHP file instead of adding "ddev drush" calls here.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/drush_php.sh"

drush_php "${SCRIPT_DIR}/php/user_roles.php" 2>/dev/null
