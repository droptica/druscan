#!/bin/bash

# analyze_performance.sh
# Analyzes website performance - both frontend (Lighthouse) and backend (configuration)
# Usage: bash analyze_performance.sh [BASE_URL] [section]
# Sections: frontend, backend, cache_config, database_indexes, php_settings,
#           performance_modules, views_analysis, code_analysis, aggregation, image_optimization

# Note: Not using set -euo pipefail to allow graceful failures in optional checks

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Logging function (same as audit.sh)
log() {
    echo "[$(date '+%H:%M:%S')] [PERF-$1] ${@:2}" >&2
}

# Detect document root
if [ -d "web" ]; then
    DOCROOT="web"
elif [ -d "docroot" ]; then
    DOCROOT="docroot"
else
    DOCROOT="."
fi

# Parse arguments
BASE_URL="${1:-}"
SECTION="${2:-frontend}"

# Load performance modules registry
source "$SCRIPT_DIR/performance_modules_registry.sh" 2>/dev/null || true

# Load helper for running PHP inside Drupal with one drush call
source "$SCRIPT_DIR/lib/drush_php.sh"

# ============================================
# Shared data (collected once, used by several parts)
# ============================================
# DRUPAL_PERF_DATA: config values, cache bins, index counts, table sizes, image styles
#                   (scripts/php/performance.php - ONE Drupal bootstrap instead of ~10)
# Loaded in "Main" before the analysis functions run, because the functions run in
# subshells and cannot share variables with each other.
DRUPAL_PERF_DATA="{}"

load_drupal_perf_data() {
    log INFO "Collecting Drupal performance data (one Drupal call)..."
    local data
    data=$(drush_php "$SCRIPT_DIR/php/performance.php" 2>/dev/null)
    if [ -n "$data" ] && echo "$data" | jq empty 2>/dev/null; then
        DRUPAL_PERF_DATA="$data"
    else
        log WARN "Could not collect Drupal performance data - values will be empty"
    fi
}

# Read one value from DRUPAL_PERF_DATA: perf_data '<jq filter>' '<fallback>'
perf_data() {
    local value
    value=$(echo "$DRUPAL_PERF_DATA" | jq -c "$1 // empty" 2>/dev/null)
    if [ -z "$value" ]; then
        echo "$2"
    else
        echo "$value"
    fi
}

# ============================================
# FRONTEND PERFORMANCE (Lighthouse)
# ============================================

# Function to run lighthouse and extract key metrics
run_lighthouse() {
    local strategy="$1"
    local output_file="$2"

    # Lighthouse 12.x uses --form-factor instead of --preset for mobile
    if [ "$strategy" = "mobile" ]; then
        lighthouse "$BASE_URL" \
            --form-factor=mobile \
            --screenEmulation.mobile \
            --only-categories=performance \
            --output=json \
            --output-path="$output_file" \
            --chrome-flags="--headless --no-sandbox --disable-gpu" \
            --quiet \
            2>/dev/null
    else
        lighthouse "$BASE_URL" \
            --preset="$strategy" \
            --only-categories=performance \
            --output=json \
            --output-path="$output_file" \
            --chrome-flags="--headless --no-sandbox --disable-gpu" \
            --quiet \
            2>/dev/null
    fi

    if [ $? -ne 0 ] || [ ! -f "$output_file" ]; then
        echo "null"
        return 1
    fi

    # Extract key metrics using jq
    jq '{
        performance_score: (.categories.performance.score // 0 | . * 100 | round),
        metrics: {
            first_contentful_paint: (.audits."first-contentful-paint".numericValue // 0 | . / 1000 | round),
            speed_index: (.audits."speed-index".numericValue // 0 | . / 1000 | round),
            largest_contentful_paint: (.audits."largest-contentful-paint".numericValue // 0 | . / 1000 | round),
            time_to_interactive: (.audits.interactive.numericValue // 0 | . / 1000 | round),
            total_blocking_time: (.audits."total-blocking-time".numericValue // 0 | round),
            cumulative_layout_shift: (.audits."cumulative-layout-shift".numericValue // 0 | . * 1000 | round | . / 1000)
        },
        opportunities: [
            .audits | to_entries[] |
            select(.value.details.type? == "opportunity") |
            {
                title: .value.title,
                description: .value.description,
                savings_ms: (.value.details.overallSavingsMs // 0 | round)
            }
        ] | sort_by(-.savings_ms) | .[0:5],
        diagnostics: [
            .audits | to_entries[] |
            select(.value.score? != null and .value.score < 1 and .value.details.type? != "opportunity") |
            {
                title: .value.title,
                description: .value.description,
                score: (.value.score // 0 | . * 100 | round)
            }
        ] | sort_by(.score) | .[0:5]
    }' "$output_file"
}

analyze_frontend() {
    # Check if BASE_URL is provided
    if [ -z "$BASE_URL" ]; then
        echo '{"error": "BASE_URL not provided for frontend analysis", "mobile": null, "desktop": null}'
        return 0
    fi

    # Check if lighthouse is installed
    if ! command -v lighthouse &> /dev/null; then
        echo '{"error": "Lighthouse CLI not installed. Install with: npm install -g lighthouse", "mobile": null, "desktop": null}'
        return 0
    fi

    # Temporary files for results
    local MOBILE_REPORT="/tmp/lighthouse_mobile_$$.json"
    local DESKTOP_REPORT="/tmp/lighthouse_desktop_$$.json"

# Run mobile analysis
echo -n '{"url":"'$BASE_URL'","mobile":'
run_lighthouse "mobile" "$MOBILE_REPORT"
echo -n ',"desktop":'
run_lighthouse "desktop" "$DESKTOP_REPORT"
echo '}'

# Cleanup
rm -f "$MOBILE_REPORT" "$DESKTOP_REPORT"
}

# ============================================
# BACKEND PERFORMANCE - Cache Configuration
# ============================================
analyze_cache_config() {
    log INFO "Analyzing cache configuration..."
    local cache_backend="database"
    local redis_enabled="false"
    local memcache_enabled="false"
    local page_cache_max_age=0
    local render_cache_enabled="false"
    local dynamic_page_cache_enabled="false"

    # Check cache backend in settings.php
    if grep -q "redis" "$DOCROOT/sites/default/settings.php" 2>/dev/null; then
        cache_backend="redis"
        redis_enabled="true"
    elif grep -q "memcache" "$DOCROOT/sites/default/settings.php" 2>/dev/null; then
        cache_backend="memcache"
        memcache_enabled="true"
    fi

    # Get page cache max age
    page_cache_max_age=$(perf_data '.page_cache_max_age' '0')

    # Check core cache modules
    render_cache_enabled=$(ddev drush pm:list --format=json 2>/dev/null | jq -r 'to_entries[] | select(.key == "page_cache") | .value.status' || echo "disabled")
    dynamic_page_cache_enabled=$(ddev drush pm:list --format=json 2>/dev/null | jq -r 'to_entries[] | select(.key == "dynamic_page_cache") | .value.status' || echo "disabled")

    # Get cache bins
    local cache_bins
    cache_bins=$(perf_data '.cache_bins' '[]')

    # Check Varnish/Purge modules
    local varnish_module
    varnish_module=$(ddev drush pm:list --format=json 2>/dev/null | jq 'to_entries[] | select(.key | test("varnish|purge")) | {name: .key, status: .value.status}' | jq -s '.' || echo "[]")

    # Build recommendations array
    local recommendations=()
    if [ "$cache_backend" = "database" ]; then
        recommendations+=("\"Install Redis or Memcache for better cache performance\"")
    fi
    if [ "$page_cache_max_age" -eq 0 ]; then
        recommendations+=("\"Enable page cache by setting max age > 0\"")
    fi
    if [ "$render_cache_enabled" = "disabled" ]; then
        recommendations+=("\"Enable page_cache module for anonymous users\"")
    fi

    local recommendations_json=$(printf '%s\n' "${recommendations[@]}" | jq -R -s -c 'split("\n") | map(select(length > 0)) | map(fromjson)')

    cat <<EOF
{
    "cache_backend": "$cache_backend",
    "redis_enabled": $redis_enabled,
    "memcache_enabled": $memcache_enabled,
    "page_cache_max_age": $page_cache_max_age,
    "page_cache_enabled": "$render_cache_enabled",
    "dynamic_page_cache_enabled": "$dynamic_page_cache_enabled",
    "cache_bins": $cache_bins,
    "varnish_purge_modules": $varnish_module,
    "recommendations": $recommendations_json
}
EOF
}

# ============================================
# BACKEND PERFORMANCE - Database Indexes
# ============================================
analyze_database_indexes() {
    log INFO "Analyzing database indexes..."
    # Index counts, tables without primary key and largest tables come from DRUPAL_PERF_DATA
    local tables_without_pk
    tables_without_pk=$(perf_data '.tables_without_primary_key' '[]')

    local largest_tables
    largest_tables=$(perf_data '.largest_tables' '[]')

    local node_indexes_count
    node_indexes_count=$(perf_data '.node_field_data_indexes' '0')

    local users_indexes_count
    users_indexes_count=$(perf_data '.users_field_data_indexes' '0')

    local taxonomy_indexes_count
    taxonomy_indexes_count=$(perf_data '.taxonomy_term_field_data_indexes' '0')

    local tables_without_pk_count
    tables_without_pk_count=$(echo "$tables_without_pk" | jq '. | length' 2>/dev/null || echo "0")

    # Build recommendations array
    local recommendations=()
    if [ "$tables_without_pk_count" -gt 0 ]; then
        recommendations+=("\"CRITICAL: Add primary keys to tables without them\"")
    fi

    local recommendations_json=$(printf '%s\n' "${recommendations[@]}" | jq -R -s -c 'split("\n") | map(select(length > 0)) | map(fromjson)')

    cat <<EOF
{
    "node_field_data_indexes": $node_indexes_count,
    "users_field_data_indexes": $users_indexes_count,
    "taxonomy_term_field_data_indexes": $taxonomy_indexes_count,
    "tables_without_primary_key": $tables_without_pk,
    "tables_without_primary_key_count": $tables_without_pk_count,
    "largest_tables": $largest_tables,
    "recommendations": $recommendations_json
}
EOF
}

# ============================================
# BACKEND PERFORMANCE - PHP Settings
# ============================================
analyze_php_settings() {
    log INFO "Analyzing PHP settings (from DDEV)..."
    # All PHP settings with ONE "ddev exec" call (was 9 calls)
    local php_info
    php_info=$(ddev exec php -r 'echo json_encode(["php_version" => PHP_VERSION, "memory_limit" => ini_get("memory_limit"), "max_execution_time" => ini_get("max_execution_time"), "opcache_enabled" => (extension_loaded("Zend OPcache") || extension_loaded("opcache")) ? "true" : "false", "opcache_memory" => ini_get("opcache.memory_consumption"), "opcache_max_files" => ini_get("opcache.max_accelerated_files"), "opcache_validate_timestamps" => ini_get("opcache.validate_timestamps"), "post_max_size" => ini_get("post_max_size"), "upload_max_filesize" => ini_get("upload_max_filesize")]);' 2>/dev/null)
    if [ -z "$php_info" ] || ! echo "$php_info" | jq empty 2>/dev/null; then
        php_info="{}"
    fi

    # Read one PHP setting: php_setting <key> <fallback>
    php_setting() {
        local value
        value=$(echo "$php_info" | jq -r --arg key "$1" '.[$key] | if . == null or . == false then empty else . end' 2>/dev/null)
        if [ -z "$value" ]; then
            echo "$2"
        else
            echo "$value"
        fi
    }

    local php_version=$(php_setting php_version unknown)
    local memory_limit=$(php_setting memory_limit unknown)
    local max_execution_time=$(php_setting max_execution_time unknown)
    local opcache_enabled=$(php_setting opcache_enabled false)
    local opcache_memory=$(php_setting opcache_memory unknown)
    local opcache_max_files=$(php_setting opcache_max_files unknown)
    local opcache_validate_timestamps=$(php_setting opcache_validate_timestamps unknown)
    local post_max_size=$(php_setting post_max_size unknown)
    local upload_max_filesize=$(php_setting upload_max_filesize unknown)

    # Build recommendations array
    local recommendations=()
    if [ "$opcache_enabled" = "false" ]; then
        recommendations+=("\"Enable OPcache for 30-50% performance improvement\"")
    fi
    if [ "$memory_limit" = "128M" ]; then
        recommendations+=("\"Consider increasing memory_limit to 256M or higher\"")
    fi

    local recommendations_json=$(printf '%s\n' "${recommendations[@]}" | jq -R -s -c 'split("\n") | map(select(length > 0)) | map(fromjson)')

    cat <<EOF
{
    "warning": "These settings are from LOCAL DDEV environment. Production settings may differ!",
    "php_version": "$php_version",
    "memory_limit": "$memory_limit",
    "max_execution_time": "$max_execution_time",
    "post_max_size": "$post_max_size",
    "upload_max_filesize": "$upload_max_filesize",
    "opcache": {
        "enabled": $opcache_enabled,
        "memory_consumption": "$opcache_memory",
        "max_accelerated_files": "$opcache_max_files",
        "validate_timestamps": "$opcache_validate_timestamps"
    },
    "recommendations": $recommendations_json
}
EOF
}

# ============================================
# BACKEND PERFORMANCE - Performance Modules
# ============================================
analyze_performance_modules() {
    log INFO "Analyzing performance modules (checking 30+ modules)..."
    # Get all installed modules
    local all_modules
    log INFO "  → Fetching module list from Drush..."
    all_modules=$(ddev drush pm:list --format=json 2>/dev/null || echo "{}")
    log INFO "  → Module list fetched, analyzing..."

    local cache_results=()
    local aggregation_results=()
    local image_results=()
    local cdn_results=()
    local database_results=()
    local mobile_results=()
    local additional_results=()

    # Check cache modules
    for module_info in "${CACHE_MODULES[@]}"; do
        IFS='|' read -r module_name description <<< "$module_info"
        local status
        status=$(echo "$all_modules" | jq -r --arg mod "$module_name" 'to_entries[] | select(.key == $mod) | .value.status' 2>/dev/null || echo "not_installed")
        cache_results+=("{\"module\": \"$module_name\", \"description\": \"$description\", \"status\": \"$status\"}")
    done

    # Check aggregation modules
    for module_info in "${AGGREGATION_MODULES[@]}"; do
        IFS='|' read -r module_name description <<< "$module_info"
        local status
        status=$(echo "$all_modules" | jq -r --arg mod "$module_name" 'to_entries[] | select(.key == $mod) | .value.status' 2>/dev/null || echo "not_installed")
        aggregation_results+=("{\"module\": \"$module_name\", \"description\": \"$description\", \"status\": \"$status\"}")
    done

    # Check image optimization modules
    for module_info in "${IMAGE_OPTIMIZATION_MODULES[@]}"; do
        IFS='|' read -r module_name description <<< "$module_info"
        local status
        status=$(echo "$all_modules" | jq -r --arg mod "$module_name" 'to_entries[] | select(.key == $mod) | .value.status' 2>/dev/null || echo "not_installed")
        image_results+=("{\"module\": \"$module_name\", \"description\": \"$description\", \"status\": \"$status\"}")
    done

    # Check CDN modules
    for module_info in "${CDN_MODULES[@]}"; do
        IFS='|' read -r module_name description <<< "$module_info"
        local status
        status=$(echo "$all_modules" | jq -r --arg mod "$module_name" 'to_entries[] | select(.key == $mod) | .value.status' 2>/dev/null || echo "not_installed")
        cdn_results+=("{\"module\": \"$module_name\", \"description\": \"$description\", \"status\": \"$status\"}")
    done

    # Check database optimization modules
    for module_info in "${DATABASE_MODULES[@]}"; do
        IFS='|' read -r module_name description <<< "$module_info"
        local status
        status=$(echo "$all_modules" | jq -r --arg mod "$module_name" 'to_entries[] | select(.key == $mod) | .value.status' 2>/dev/null || echo "not_installed")
        database_results+=("{\"module\": \"$module_name\", \"description\": \"$description\", \"status\": \"$status\"}")
    done

    # Check mobile/rendering modules
    for module_info in "${MOBILE_MODULES[@]}"; do
        IFS='|' read -r module_name description <<< "$module_info"
        local status
        status=$(echo "$all_modules" | jq -r --arg mod "$module_name" 'to_entries[] | select(.key == $mod) | .value.status' 2>/dev/null || echo "not_installed")
        mobile_results+=("{\"module\": \"$module_name\", \"description\": \"$description\", \"status\": \"$status\"}")
    done

    # Check additional modules
    for module_info in "${ADDITIONAL_MODULES[@]}"; do
        IFS='|' read -r module_name description <<< "$module_info"
        local status
        status=$(echo "$all_modules" | jq -r --arg mod "$module_name" 'to_entries[] | select(.key == $mod) | .value.status' 2>/dev/null || echo "not_installed")
        additional_results+=("{\"module\": \"$module_name\", \"description\": \"$description\", \"status\": \"$status\"}")
    done

    # Build JSON
    local cache_json=$(printf '%s\n' "${cache_results[@]}" | jq -s '.')
    local aggregation_json=$(printf '%s\n' "${aggregation_results[@]}" | jq -s '.')
    local image_json=$(printf '%s\n' "${image_results[@]}" | jq -s '.')
    local cdn_json=$(printf '%s\n' "${cdn_results[@]}" | jq -s '.')
    local database_json=$(printf '%s\n' "${database_results[@]}" | jq -s '.')
    local mobile_json=$(printf '%s\n' "${mobile_results[@]}" | jq -s '.')
    local additional_json=$(printf '%s\n' "${additional_results[@]}" | jq -s '.')

    # Count enabled modules
    local cache_enabled=$(echo "$cache_json" | jq '[.[] | select(.status == "enabled")] | length')
    local aggregation_enabled=$(echo "$aggregation_json" | jq '[.[] | select(.status == "enabled")] | length')
    local image_enabled=$(echo "$image_json" | jq '[.[] | select(.status == "enabled")] | length')
    local cdn_enabled=$(echo "$cdn_json" | jq '[.[] | select(.status == "enabled")] | length')
    local database_enabled=$(echo "$database_json" | jq '[.[] | select(.status == "enabled")] | length')

    cat <<EOF
{
    "cache_modules": $cache_json,
    "aggregation_modules": $aggregation_json,
    "image_optimization_modules": $image_json,
    "cdn_modules": $cdn_json,
    "database_optimization_modules": $database_json,
    "mobile_modules": $mobile_json,
    "additional_modules": $additional_json,
    "statistics": {
        "cache_enabled": $cache_enabled,
        "aggregation_enabled": $aggregation_enabled,
        "image_optimization_enabled": $image_enabled,
        "cdn_enabled": $cdn_enabled,
        "database_optimization_enabled": $database_enabled
    }
}
EOF
}

# ============================================
# BACKEND PERFORMANCE - Views Performance
# ============================================
analyze_views_performance() {
    log INFO "Analyzing views performance..."
    # Get views statistics from existing script
    local views_stats
    views_stats=$(bash "$SCRIPT_DIR/analyze_views.sh" statistics 2>/dev/null || echo "{}")

    # Get full views data
    local views_data
    views_data=$(bash "$SCRIPT_DIR/analyze_views.sh" all 2>/dev/null || echo "[]")

    # Find views with relationships (potential performance issues)
    local views_with_relationships
    views_with_relationships=$(echo "$views_data" | jq '[.[] | select((.relationships | length) > 0)] | map({id: .id, label: .label, relationships_count: (.relationships | length), displays_count: (.displays | length)})' 2>/dev/null || echo "[]")

    # Find views with many filters (complex queries)
    local complex_views
    complex_views=$(echo "$views_data" | jq '[.[] | select((.filters | length) > 5)] | map({id: .id, label: .label, filters_count: (.filters | length), relationships_count: (.relationships | length)})' 2>/dev/null || echo "[]")

    # Find views with large items_per_page
    local large_page_views
    large_page_views=$(echo "$views_data" | jq '[.[] | select(.items_per_page > 50)] | map({id: .id, label: .label, items_per_page: .items_per_page})' 2>/dev/null || echo "[]")

    # Find views without caching
    local uncached_views
    uncached_views=$(echo "$views_data" | jq '[.[] | select(.cache_type == null or .cache_type == "none")] | map({id: .id, label: .label, displays_count: (.displays | length)})' 2>/dev/null || echo "[]")

    cat <<EOF
{
    "statistics": $views_stats,
    "views_with_relationships": $views_with_relationships,
    "views_with_relationships_count": $(echo "$views_with_relationships" | jq 'length'),
    "complex_views": $complex_views,
    "complex_views_count": $(echo "$complex_views" | jq 'length'),
    "large_page_views": $large_page_views,
    "large_page_views_count": $(echo "$large_page_views" | jq 'length'),
    "uncached_views": $uncached_views,
    "uncached_views_count": $(echo "$uncached_views" | jq 'length'),
    "recommendations": [
        "Review views with relationships for potential JOIN performance issues",
        "Enable caching for frequently accessed views",
        "Consider reducing items_per_page for views with large result sets",
        "Optimize complex views with many filters"
    ]
}
EOF
}

# ============================================
# BACKEND PERFORMANCE - Code Analysis
# ============================================
analyze_code_performance() {
    log INFO "Analyzing code performance patterns..."
    # Find files with custom database queries
    local custom_queries_files
    custom_queries_files=$(find "$DOCROOT/modules/custom" -type f -name '*.php' -exec grep -l 'db_query\|->query\|Database::getConnection' {} \; 2>/dev/null | wc -l | tr -d ' ')

    # Find files using EntityQuery (good practice)
    local entity_query_files
    entity_query_files=$(find "$DOCROOT/modules/custom" -type f -name '*.php' -exec grep -l 'entityQuery\|entityTypeManager\|->loadMultiple' {} \; 2>/dev/null | wc -l | tr -d ' ')

    # Find direct SQL in .module files (potential issue)
    local direct_sql_in_modules
    direct_sql_in_modules=$(find "$DOCROOT/modules/custom" -type f -name '*.module' -exec grep -l 'SELECT\|INSERT\|UPDATE\|DELETE' {} \; 2>/dev/null | wc -l | tr -d ' ')

    # Find cache API usage (good practice)
    local cache_api_usage
    cache_api_usage=$(find "$DOCROOT/modules/custom" -type f -name '*.php' -exec grep -l 'cache()->get\|cache()->set\|CacheBackendInterface' {} \; 2>/dev/null | wc -l | tr -d ' ')

    # Find render cache usage
    local render_cache_usage
    render_cache_usage=$(find "$DOCROOT/modules/custom" -type f -name '*.php' -exec grep -l '#cache' {} \; 2>/dev/null | wc -l | tr -d ' ')

    # Check for hook_query_alter (can impact performance)
    local query_alter_hooks
    query_alter_hooks=$(find "$DOCROOT/modules/custom" -type f -name '*.module' -exec grep -l 'function.*_query_alter' {} \; 2>/dev/null | wc -l | tr -d ' ')

    # Build recommendations array
    local recommendations=()
    if [ "$custom_queries_files" -gt 5 ]; then
        recommendations+=("\"Consider refactoring custom queries to use EntityQuery API\"")
    fi
    if [ "$cache_api_usage" -eq 0 ]; then
        recommendations+=("\"Implement cache API to reduce database load\"")
    fi
    if [ "$direct_sql_in_modules" -gt 0 ]; then
        recommendations+=("\"Review direct SQL queries for security and performance\"")
    fi

    local recommendations_json=$(printf '%s\n' "${recommendations[@]}" | jq -R -s -c 'split("\n") | map(select(length > 0)) | map(fromjson)')

    cat <<EOF
{
    "custom_database_queries": {
        "files_count": $custom_queries_files,
        "description": "Files using direct database queries (db_query, Database::getConnection)",
        "impact": "May have performance issues if not optimized"
    },
    "entity_queries": {
        "files_count": $entity_query_files,
        "description": "Files using EntityQuery API (recommended approach)",
        "impact": "Better performance through entity caching"
    },
    "direct_sql_in_modules": {
        "files_count": $direct_sql_in_modules,
        "description": "Module files with direct SQL queries",
        "impact": "Potential security and performance risks"
    },
    "cache_api_usage": {
        "files_count": $cache_api_usage,
        "description": "Files using Drupal Cache API",
        "impact": "Good - reduces database load"
    },
    "render_cache_usage": {
        "files_count": $render_cache_usage,
        "description": "Files using render cache (#cache)",
        "impact": "Good - improves page rendering performance"
    },
    "query_alter_hooks": {
        "count": $query_alter_hooks,
        "description": "Implementations of hook_query_alter",
        "impact": "Can slow down queries if not optimized"
    },
    "recommendations": $recommendations_json
}
EOF
}

# ============================================
# BACKEND PERFORMANCE - CSS/JS Aggregation
# ============================================
analyze_aggregation() {
    log INFO "Analyzing CSS/JS aggregation..."
    local css_preprocess
    css_preprocess=$(perf_data '.css_preprocess' '"unknown"' | jq -r '.')

    local js_preprocess
    js_preprocess=$(perf_data '.js_preprocess' '"unknown"' | jq -r '.')

    # Count CSS/JS files in custom themes
    local custom_css_files
    custom_css_files=$(find "$DOCROOT/themes/custom" -type f -name '*.css' 2>/dev/null | wc -l | tr -d ' ')

    local custom_js_files
    custom_js_files=$(find "$DOCROOT/themes/custom" -type f -name '*.js' 2>/dev/null | wc -l | tr -d ' ')

    # Build recommendations array
    local recommendations=()
    if [ "$css_preprocess" != "1" ] && [ "$css_preprocess" != "true" ]; then
        recommendations+=("\"Enable CSS aggregation in system.performance settings\"")
    fi
    if [ "$js_preprocess" != "1" ] && [ "$js_preprocess" != "true" ]; then
        recommendations+=("\"Enable JavaScript aggregation in system.performance settings\"")
    fi

    local recommendations_json=$(printf '%s\n' "${recommendations[@]}" | jq -R -s -c 'split("\n") | map(select(length > 0)) | map(fromjson)')

    cat <<EOF
{
    "note": "Drupal 10+ core aggregation is sufficient - no additional modules needed",
    "css_aggregation": {
        "enabled": $(if [ "$css_preprocess" = "1" ] || [ "$css_preprocess" = "true" ]; then echo "true"; else echo "false"; fi),
        "value": "$css_preprocess"
    },
    "js_aggregation": {
        "enabled": $(if [ "$js_preprocess" = "1" ] || [ "$js_preprocess" = "true" ]; then echo "true"; else echo "false"; fi),
        "value": "$js_preprocess"
    },
    "custom_assets": {
        "css_files": $custom_css_files,
        "js_files": $custom_js_files
    },
    "recommendations": $recommendations_json
}
EOF
}

# ============================================
# BACKEND PERFORMANCE - Image Optimization
# ============================================
analyze_image_optimization() {
    log INFO "Analyzing image optimization..."
    # Check responsive image module (Drupal core)
    local responsive_image
    responsive_image=$(ddev drush pm:list --format=json 2>/dev/null | jq -r 'to_entries[] | select(.key == "responsive_image") | .value.status' || echo "not_installed")

    # Count image styles
    local image_styles_count
    image_styles_count=$(perf_data '.image_styles_count' '0')

    # Check image optimization modules
    local webp_module
    webp_module=$(ddev drush pm:list --format=json 2>/dev/null | jq -r 'to_entries[] | select(.key == "webp") | .value.status' || echo "not_installed")

    local imageapi_optimize
    imageapi_optimize=$(ddev drush pm:list --format=json 2>/dev/null | jq -r 'to_entries[] | select(.key == "imageapi_optimize") | .value.status' || echo "not_installed")

    local blazy_module
    blazy_module=$(ddev drush pm:list --format=json 2>/dev/null | jq -r 'to_entries[] | select(.key == "blazy") | .value.status' || echo "not_installed")

    local lazy_module
    lazy_module=$(ddev drush pm:list --format=json 2>/dev/null | jq -r 'to_entries[] | select(.key == "lazy") | .value.status' || echo "not_installed")

    # Count images in files directory (with timeout to avoid long waits)
    log INFO "  → Counting images in files directory (timeout: 30s)..."
    local total_images
    total_images=$(timeout 30 find "$DOCROOT/sites/default/files" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.webp' \) 2>/dev/null | wc -l | tr -d ' ' || echo "0")

    # Find largest images (limited to first 1000 for performance)
    log INFO "  → Finding largest images (limited to 1000 files)..."
    local largest_images
    largest_images=$(timeout 30 find "$DOCROOT/sites/default/files" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' \) 2>/dev/null | head -1000 | xargs -I {} du -h {} 2>/dev/null | sort -rh | head -10 | awk '{print $2}' | jq -R -s -c 'split("\n") | map(select(length > 0))' || echo "[]")

    # Calculate approximate size of all images
    local images_total_size_mb
    images_total_size_mb=$(du -sm "$DOCROOT/sites/default/files" 2>/dev/null | awk '{print $1}' || echo "0")

    # Build recommendations array
    local recommendations=()
    if [ "$responsive_image" = "disabled" ]; then
        recommendations+=("\"Enable Responsive Image module for mobile optimization\"")
    fi
    if [ "$webp_module" = "not_installed" ]; then
        recommendations+=("\"Install WebP module for 25-35% smaller image file sizes\"")
    fi
    if [ "$blazy_module" = "not_installed" ] && [ "$lazy_module" = "not_installed" ]; then
        recommendations+=("\"Install Blazy or Lazy module for lazy loading images\"")
    fi
    if [ "$imageapi_optimize" = "not_installed" ]; then
        recommendations+=("\"Install Image Optimize API for lossless image compression\"")
    fi

    local recommendations_json=$(printf '%s\n' "${recommendations[@]}" | jq -R -s -c 'split("\n") | map(select(length > 0)) | map(fromjson)')

    cat <<EOF
{
    "responsive_image_module": "$responsive_image",
    "image_styles_count": $image_styles_count,
    "webp_module": "$webp_module",
    "imageapi_optimize_module": "$imageapi_optimize",
    "blazy_module": "$blazy_module",
    "lazy_module": "$lazy_module",
    "statistics": {
        "total_images": $total_images,
        "images_directory_size_mb": $images_total_size_mb,
        "largest_images_sample": $largest_images
    },
    "recommendations": $recommendations_json
}
EOF
}

# ============================================
# BACKEND PERFORMANCE - Full Backend Analysis
# ============================================
analyze_backend() {
    log INFO "Starting full backend performance analysis (8 sections)..."

    local cache_data
    cache_data=$(analyze_cache_config)

    local db_data
    db_data=$(analyze_database_indexes)

    local php_data
    php_data=$(analyze_php_settings)

    local modules_data
    modules_data=$(analyze_performance_modules)

    local views_data
    views_data=$(analyze_views_performance)

    local code_data
    code_data=$(analyze_code_performance)

    local aggregation_data
    aggregation_data=$(analyze_aggregation)

    local image_data
    image_data=$(analyze_image_optimization)

    log INFO "Backend performance analysis completed ✓"

    cat <<EOF
{
    "cache_configuration": $cache_data,
    "database_indexes": $db_data,
    "php_settings": $php_data,
    "performance_modules": $modules_data,
    "views_performance": $views_data,
    "code_performance": $code_data,
    "css_js_aggregation": $aggregation_data,
    "image_optimization": $image_data
}
EOF
}

# ============================================
# Main
# ============================================
case "$SECTION" in
    backend|cache_config|database_indexes|aggregation|image_optimization)
        load_drupal_perf_data
        ;;
esac

case "$SECTION" in
    frontend)
        analyze_frontend
        ;;
    backend)
        analyze_backend
        ;;
    cache_config)
        analyze_cache_config
        ;;
    database_indexes)
        analyze_database_indexes
        ;;
    php_settings)
        analyze_php_settings
        ;;
    performance_modules)
        analyze_performance_modules
        ;;
    views_analysis)
        analyze_views_performance
        ;;
    code_analysis)
        analyze_code_performance
        ;;
    aggregation)
        analyze_aggregation
        ;;
    image_optimization)
        analyze_image_optimization
        ;;
    *)
        echo "Unknown section: $SECTION" >&2
        echo "Available sections: frontend, backend, cache_config, database_indexes, php_settings, performance_modules, views_analysis, code_analysis, aggregation, image_optimization" >&2
        exit 1
        ;;
esac
