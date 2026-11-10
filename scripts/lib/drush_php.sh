#!/bin/bash

# Helper Library: Run a PHP file inside Drupal with ONE drush call
# Purpose: Every "ddev drush ..." call starts Drupal again (about 1-2 seconds).
#          A script that asks Drupal 200 small questions is slow. Put the questions
#          in one PHP file in ./scripts/php/ and run it once with drush_php.
#
# Usage in a helper script:
#   source "$(dirname "$0")/lib/drush_php.sh"
#   RESULT=$(drush_php "$(dirname "$0")/php/my_analysis.php")
#   RESULT=$(drush_php "$(dirname "$0")/php/my_analysis.php" '{"key": "value"}')
#
# In the PHP file:
#   - First line is "<?php" (removed before the code is sent to drush)
#   - Drupal is fully bootstrapped (\Drupal::service(...) works)
#   - $druscan_args holds the optional JSON argument as an array (null if not given)
#   - Print the result with: echo json_encode($result);
#
# Note: stderr of drush is not hidden here - add 2>/dev/null in the caller if needed.

drush_php() {
    local php_file="$1"
    local json_args="${2:-null}"

    if [ ! -f "$php_file" ]; then
        echo "drush_php: file not found: $php_file" >&2
        return 1
    fi

    local args_b64
    args_b64=$(printf '%s' "$json_args" | base64 | tr -d '\n')

    local code
    code="\$druscan_args = json_decode(base64_decode('${args_b64}'), TRUE); $(sed '1{/^<?php/d;}' "$php_file")"

    ddev drush php:eval "$code"
}
