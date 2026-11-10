#!/bin/bash
# Analyzes code quality and static analysis tools in Drupal project
# Checks for configuration files, composer packages, and DDEV commands

set -e

# Colors for output (optional, for debugging)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Detect document root
if [ -d "web" ]; then
    DOCROOT="web"
elif [ -d "docroot" ]; then
    DOCROOT="docroot"
else
    DOCROOT="."
fi

# Define tools registry with config files and composer packages
# Format: "tool_key|Name|Description|config files (comma separated)|composer packages (comma separated)"
# Note: plain indexed array (not "declare -A") - must work with Bash 3.2 (default on macOS)
TOOLS=(
    "phpstan|PHPStan|Static analysis tool that finds bugs in code without running it. Offers configurable strictness levels.|phpstan.neon,phpstan.neon.dist,phpstan.dist.neon|phpstan/phpstan"
    "psalm|Psalm|Advanced static analysis with focus on type safety and annotation support.|psalm.xml,psalm.xml.dist|vimeo/psalm"
    "phpcs|PHP_CodeSniffer|Enforces coding standards (PSR-2, PSR-12, Drupal). Analyzes PHP, JS, CSS files.|phpcs.xml,phpcs.xml.dist,.phpcs.xml,phpcs.ruleset.xml|squizlabs/php_codesniffer,drupal/coder"
    "phpmd|PHP Mess Detector|Identifies code smells, dead code, and overly complex expressions.|phpmd.xml,phpmd.xml.dist,.phpmd.xml|phpmd/phpmd"
    "php-cs-fixer|PHP CS Fixer|Automatically fixes code standard violations according to predefined rules.|.php-cs-fixer.php,.php-cs-fixer.dist.php,.php_cs,.php_cs.dist|friendsofphp/php-cs-fixer"
    "phan|Phan|Static analyzer focusing on catching real bugs with reduced false positives.|.phan/config.php,phan.php|phan/phan"
    "rector|Rector|Automated refactoring tool for upgrading and modernizing PHP code.|rector.php,rector.yaml|rector/rector"
    "phpunit|PHPUnit|Unit testing framework for PHP. Essential for automated testing.|phpunit.xml,phpunit.xml.dist|phpunit/phpunit"
    "grumphp|GrumPHP|Git hooks manager that runs code quality checks before commits.|grumphp.yml,grumphp.yml.dist|phpro/grumphp"
    "phpmetrics|PhpMetrics|Generates quality reports and complexity metrics.|.phpmetrics.json,.phpmetrics.yml|phpmetrics/phpmetrics"
    "scrutinizer|Scrutinizer|Cloud-based continuous integration for code quality analysis.|.scrutinizer.yml|"
    "sonarqube|SonarQube|Comprehensive static analysis platform for bugs, code smells, security.|sonar-project.properties,.sonarcloud.properties|"
    "codeception|Codeception|Full-stack testing framework for PHP (BDD-style).|codeception.yml,codeception.yml.dist,codeception.dist.yml|codeception/codeception"
    "behat|Behat|Behavior-driven development framework for PHP.|behat.yml,behat.yml.dist|behat/behat"
    "infection|Infection|Mutation testing framework for PHP to measure test quality.|infection.json,infection.json.dist|infection/infection"
    "phpcpd|PHP Copy/Paste Detector|Detects duplicated code in PHP projects.|.phpcpd.xml|sebastian/phpcpd"
    "phploc|PHPLOC|Measures project size and analyzes code structure.|.phploc.yml|phploc/phploc"
    "parallel-lint|PHP Parallel Lint|Checks PHP files for syntax errors in parallel.|.parallel-lint.yml|php-parallel-lint/php-parallel-lint,jakub-onderka/php-parallel-lint"
    "phpcompatibility|PHPCompatibility|Checks PHP version compatibility.|.phpcompat.xml|phpcompatibility/php-compatibility"
    "larastan|Larastan|PHPStan wrapper for Laravel (may be used in Drupal custom code).|phpstan.neon|nunomaduro/larastan"
    "deptrac|Deptrac|Enforces architectural rules and layer dependencies.|deptrac.yaml,deptrac.yml|qossmic/deptrac-shim"
)

# Initialize result object
RESULT='{
  "tools_found": [],
  "tools_not_found": [],
  "statistics": {
    "total_tools_checked": 0,
    "tools_configured": 0,
    "tools_not_configured": 0
  },
  "composer_packages": [],
  "ddev_commands": []
}'

# Function to check if file exists
check_file_exists() {
    local files=$1
    local found_files=()
    
    IFS=',' read -ra FILE_ARRAY <<< "$files"
    for file in "${FILE_ARRAY[@]}"; do
        if [ -f "$file" ]; then
            found_files+=("$file")
        fi
    done
    
    if [ ${#found_files[@]} -gt 0 ]; then
        printf '%s\n' "${found_files[@]}" | jq -R . | jq -s .
    else
        echo "[]"
    fi
}

# Function to check composer package
check_composer_package() {
    local packages=$1
    
    if [ -z "$packages" ]; then
        echo "false"
        return
    fi
    
    IFS=',' read -ra PKG_ARRAY <<< "$packages"
    for pkg in "${PKG_ARRAY[@]}"; do
        if ddev composer show "$pkg" &>/dev/null; then
            echo "true"
            return
        fi
    done
    
    echo "false"
}

# Get composer scripts
COMPOSER_SCRIPTS="[]"
if [ -f "composer.json" ]; then
    COMPOSER_SCRIPTS=$(cat composer.json | jq -c '.scripts // {}' 2>/dev/null || echo '{}')
fi

# Get DDEV commands
DDEV_COMMANDS="[]"
if [ -d ".ddev/commands" ]; then
    DDEV_COMMANDS=$(find .ddev/commands -type f -name "*.sh" -o -name "*.bash" -o -name "*.zsh" 2>/dev/null | jq -R . | jq -s . || echo "[]")
fi

# Analyze each tool
TOOLS_FOUND_JSON="[]"
TOOLS_NOT_FOUND_JSON="[]"
TOOLS_CONFIGURED=0
TOOLS_NOT_CONFIGURED=0

for tool_entry in "${TOOLS[@]}"; do
    IFS='|' read -r tool_key tool_name description config_files composer_packages <<< "$tool_entry"
    
    # Check config files
    config_files_found=$(check_file_exists "$config_files")
    config_exists=$(echo "$config_files_found" | jq 'length > 0')
    
    # Check composer package
    composer_installed=$(check_composer_package "$composer_packages")
    
    # Check composer scripts
    composer_scripts_related="[]"
    if [ -f "composer.json" ]; then
        composer_scripts_related=$(cat composer.json | jq -c --arg tool "$tool_key" '[.scripts | to_entries[] | select(.key | contains($tool)) | .key] // []' 2>/dev/null || echo "[]")
    fi
    
    # Determine if tool is configured
    is_configured="false"
    if [ "$config_exists" = "true" ] || [ "$composer_installed" = "true" ]; then
        is_configured="true"
        TOOLS_CONFIGURED=$((TOOLS_CONFIGURED + 1))
    else
        TOOLS_NOT_CONFIGURED=$((TOOLS_NOT_CONFIGURED + 1))
    fi
    
    # Build tool object
    tool_obj=$(jq -n \
        --arg key "$tool_key" \
        --arg name "$tool_name" \
        --arg desc "$description" \
        --argjson config "$config_files_found" \
        --arg composer "$composer_installed" \
        --argjson scripts "$composer_scripts_related" \
        --arg configured "$is_configured" \
        '{
            tool_key: $key,
            name: $name,
            description: $desc,
            is_configured: ($configured == "true"),
            config_files_found: $config,
            composer_installed: ($composer == "true"),
            composer_scripts: $scripts
        }')
    
    if [ "$is_configured" = "true" ]; then
        TOOLS_FOUND_JSON=$(echo "$TOOLS_FOUND_JSON" | jq --argjson obj "$tool_obj" '. + [$obj]')
    else
        TOOLS_NOT_FOUND_JSON=$(echo "$TOOLS_NOT_FOUND_JSON" | jq --argjson obj "$tool_obj" '. + [$obj]')
    fi
done

# Get list of relevant composer packages
COMPOSER_PACKAGES="[]"
if command -v ddev &>/dev/null; then
    COMPOSER_PACKAGES=$(ddev composer show --format=json 2>/dev/null | jq '[.installed[] | select(.name | test("phpstan|psalm|phpcs|phpmd|php-cs-fixer|phan|rector|phpunit|grumphp|phpmetrics|codeception|behat|infection|phpcpd|phploc|parallel-lint|phpcompat|deptrac|coder|drupal.*dev")) | {name: .name, version: .version, description: .description}] // []' 2>/dev/null || echo "[]")
fi

# Build final result
TOTAL_TOOLS=${#TOOLS[@]}

RESULT=$(jq -n \
    --argjson found "$TOOLS_FOUND_JSON" \
    --argjson not_found "$TOOLS_NOT_FOUND_JSON" \
    --argjson total "$TOTAL_TOOLS" \
    --argjson configured "$TOOLS_CONFIGURED" \
    --argjson not_configured "$TOOLS_NOT_CONFIGURED" \
    --argjson packages "$COMPOSER_PACKAGES" \
    --argjson scripts "$COMPOSER_SCRIPTS" \
    --argjson ddev "$DDEV_COMMANDS" \
    '{
        tools_found: $found | sort_by(.name),
        tools_not_found: $not_found | sort_by(.name),
        statistics: {
            total_tools_checked: $total,
            tools_configured: $configured,
            tools_not_configured: $not_configured,
            coverage_percentage: (($configured / $total * 100) | floor)
        },
        composer_packages: $packages,
        composer_scripts: $scripts,
        ddev_commands: $ddev
    }')

# Output result as JSON
echo "$RESULT"

