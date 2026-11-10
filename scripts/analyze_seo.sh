#!/bin/bash
# SEO Analysis Script for Drupal 8+
# Analyzes SEO configuration: metatags, URL aliases, sitemaps, robots.txt, schema.org

set -e

SECTION="${1:-all}"

# ============================================
# Helper Functions
# ============================================

check_module_enabled() {
    local module_name="$1"
    local status=$(ddev drush pm:list --format=json 2>/dev/null | jq -r "to_entries[] | select(.key == \"$module_name\") | .value.status" || echo "not_installed")
    # Convert to lowercase for consistent comparison
    echo "$status" | tr '[:upper:]' '[:lower:]'
}

get_module_info() {
    local module_name="$1"
    ddev drush pm:list --format=json 2>/dev/null | jq -r "to_entries[] | select(.key == \"$module_name\") | .value"
}

# ============================================
# SEO Modules Analysis
# ============================================

analyze_seo_modules() {
    local seo_modules=(
        "metatag:Meta tags for all pages:Essential for page-level SEO metadata"
        "pathauto:Automatic URL alias patterns:Human-readable URLs from patterns"
        "simple_sitemap:XML sitemap generation:Helps search engines discover content"
        "redirect:URL redirect management:Maintains SEO during content changes"
        "google_analytics:Google Analytics integration:Track visitor behavior"
        "xmlsitemap:XML sitemap (alternative):Generate XML sitemaps for search engines"
        "schema_metatag:Schema.org structured data:Add structured data markup"
        "jsonld:JSON-LD structured data:Schema.org markup in JSON-LD format"
        "robotstxt:Robots.txt management:Control crawler access"
        "page_title:Page title management:Custom page titles"
        "global_redirect:Global redirect settings:Canonical URLs and redirects"
    )

    local results=()

    for entry in "${seo_modules[@]}"; do
        IFS=':' read -r module_name display_name description <<< "$entry"
        local status=$(check_module_enabled "$module_name")
        local enabled=false
        [[ "$status" == "enabled" ]] && enabled=true

        results+=("{\"module\":\"$module_name\",\"name\":\"$display_name\",\"description\":\"$description\",\"status\":\"$status\",\"enabled\":$enabled}")
    done

    # Join array with commas
    local json_output=$(printf "%s," "${results[@]}")
    json_output="[${json_output%,}]"

    echo "$json_output"
}

# ============================================
# Metatags Configuration
# ============================================

analyze_metatags() {
    local metatag_status=$(check_module_enabled "metatag")

    if [[ "$metatag_status" != "enabled" ]]; then
        echo '{"status":"not_enabled","message":"Metatag module is not enabled"}'
        return
    fi

    # Get metatag defaults configuration
    local metatag_defaults=$(ddev drush config:get metatag.metatag_defaults.global --format=json 2>/dev/null || echo '{}')

    # Get configured entity types
    local entity_configs=$(ddev drush config:status --format=json 2>/dev/null | jq -r 'to_entries[] | select(.key | startswith("metatag.metatag_defaults.")) | .key' | sed 's/metatag.metatag_defaults.//' || echo "")

    # Count metatag configurations
    local config_count=$(echo "$entity_configs" | grep -c "^" || echo "0")

    # Check for important metatag submodules
    local metatag_open_graph=$(check_module_enabled "metatag_open_graph")
    local metatag_twitter=$(check_module_enabled "metatag_twitter_cards")
    local metatag_mobile=$(check_module_enabled "metatag_mobile")
    local schema_metatag=$(check_module_enabled "schema_metatag")

    cat <<EOF
{
    "status": "$metatag_status",
    "global_defaults_configured": $([ "$metatag_defaults" != "{}" ] && echo "true" || echo "false"),
    "entity_type_configs": $config_count,
    "entity_types": $(echo "$entity_configs" | jq -R -s -c 'split("\n") | map(select(length > 0))'),
    "submodules": {
        "open_graph": "$metatag_open_graph",
        "twitter_cards": "$metatag_twitter",
        "mobile": "$metatag_mobile",
        "schema_metatag": "$schema_metatag"
    },
    "global_defaults": $metatag_defaults
}
EOF
}

# ============================================
# URL Aliases and Pathauto
# ============================================

analyze_url_aliases() {
    local pathauto_status=$(check_module_enabled "pathauto")

    # Count total URL aliases
    local total_aliases=$(ddev drush sql-query "SELECT COUNT(*) FROM path_alias;" 2>/dev/null | grep -E '^[0-9]+$' | head -1 | tr -d ' ' || echo "0")

    # Sample aliases (first 10)
    local sample_aliases=$(ddev drush sql-query "SELECT path, alias FROM path_alias LIMIT 10;" --format=json 2>/dev/null || echo '[]')

    if [[ "$pathauto_status" == "enabled" ]]; then
        # Get pathauto patterns
        local patterns=$(ddev drush config:status --format=json 2>/dev/null | jq -r 'to_entries[] | select(.key | startswith("pathauto.pattern.")) | .key' | sed 's/pathauto.pattern.//' || echo "")
        local patterns_count=$(echo "$patterns" | grep -c "^" || echo "0")

        # Get pattern details
        local pattern_details=()
        while IFS= read -r pattern_id; do
            if [[ -n "$pattern_id" ]]; then
                # </dev/null: ddev must not read the loop input (it would end the loop after the first pattern)
                local pattern_config=$(ddev drush config:get "pathauto.pattern.$pattern_id" --format=json 2>/dev/null </dev/null || echo '{}')
                pattern_details+=("$pattern_config")
            fi
        done <<< "$patterns"

        local patterns_json=$(printf "%s," "${pattern_details[@]}")
        patterns_json="[${patterns_json%,}]"

        cat <<EOF
{
    "pathauto_enabled": true,
    "total_aliases": $total_aliases,
    "patterns_count": $patterns_count,
    "patterns": $patterns_json,
    "sample_aliases": $sample_aliases
}
EOF
    else
        cat <<EOF
{
    "pathauto_enabled": false,
    "total_aliases": $total_aliases,
    "message": "Pathauto module not enabled - URL aliases must be created manually",
    "sample_aliases": $sample_aliases
}
EOF
    fi
}

# ============================================
# Sitemap Analysis
# ============================================

analyze_sitemap() {
    local simple_sitemap_status=$(check_module_enabled "simple_sitemap")
    local xmlsitemap_status=$(check_module_enabled "xmlsitemap")

    local sitemap_type="none"
    local sitemap_config="{}"

    if [[ "$simple_sitemap_status" == "enabled" ]]; then
        sitemap_type="simple_sitemap"
        sitemap_config=$(ddev drush config:get simple_sitemap.settings --format=json 2>/dev/null || echo '{}')

        # Get sitemap variants
        local variants=$(ddev drush config:status --format=json 2>/dev/null | jq -r 'to_entries[] | select(.key | startswith("simple_sitemap.variant.")) | .key' | sed 's/simple_sitemap.variant.//' || echo "")
        local variants_count=$(echo "$variants" | grep -c "^" || echo "0")

        cat <<EOF
{
    "type": "$sitemap_type",
    "module_status": "$simple_sitemap_status",
    "variants_count": $variants_count,
    "variants": $(echo "$variants" | jq -R -s -c 'split("\n") | map(select(length > 0))'),
    "configuration": $sitemap_config
}
EOF
    elif [[ "$xmlsitemap_status" == "enabled" ]]; then
        sitemap_type="xmlsitemap"
        sitemap_config=$(ddev drush config:get xmlsitemap.settings --format=json 2>/dev/null || echo '{}')

        cat <<EOF
{
    "type": "$sitemap_type",
    "module_status": "$xmlsitemap_status",
    "configuration": $sitemap_config
}
EOF
    else
        cat <<EOF
{
    "type": "none",
    "message": "No sitemap module detected (simple_sitemap or xmlsitemap)",
    "recommendation": "Install simple_sitemap module for automatic XML sitemap generation"
}
EOF
    fi
}

# ============================================
# Robots.txt Analysis
# ============================================

analyze_robotstxt() {
    local robotstxt_module=$(check_module_enabled "robotstxt")

    # Check if robots.txt file exists in webroot
    local robotstxt_exists=false
    local robotstxt_content=""
    local robotstxt_size=0

    if [[ -f "web/robots.txt" ]]; then
        robotstxt_exists=true
        robotstxt_content=$(cat web/robots.txt 2>/dev/null || echo "")
        robotstxt_size=$(wc -c < web/robots.txt 2>/dev/null || echo "0")
    elif [[ -f "docroot/robots.txt" ]]; then
        robotstxt_exists=true
        robotstxt_content=$(cat docroot/robots.txt 2>/dev/null || echo "")
        robotstxt_size=$(wc -c < docroot/robots.txt 2>/dev/null || echo "0")
    fi

    # Analyze content
    local has_sitemap=$(echo "$robotstxt_content" | grep -i "Sitemap:" | wc -l | tr -d ' ')
    local has_disallow=$(echo "$robotstxt_content" | grep -i "Disallow:" | wc -l | tr -d ' ')
    local has_allow=$(echo "$robotstxt_content" | grep -i "Allow:" | wc -l | tr -d ' ')
    local has_user_agent=$(echo "$robotstxt_content" | grep -i "User-agent:" | wc -l | tr -d ' ')

    # Escape content for JSON
    local escaped_content=$(echo "$robotstxt_content" | jq -R -s '.' 2>/dev/null || echo '""')

    cat <<EOF
{
    "module_status": "$robotstxt_module",
    "file_exists": $robotstxt_exists,
    "file_size": $robotstxt_size,
    "has_sitemap_reference": $([ "$has_sitemap" -gt 0 ] && echo "true" || echo "false"),
    "has_disallow_rules": $([ "$has_disallow" -gt 0 ] && echo "true" || echo "false"),
    "has_allow_rules": $([ "$has_allow" -gt 0 ] && echo "true" || echo "false"),
    "user_agents_count": $has_user_agent,
    "content": $escaped_content
}
EOF
}

# ============================================
# Schema.org Markup Analysis
# ============================================

analyze_schema_markup() {
    local schema_metatag=$(check_module_enabled "schema_metatag")
    local jsonld=$(check_module_enabled "jsonld")
    local schema_article=$(check_module_enabled "schema_article")
    local schema_organization=$(check_module_enabled "schema_organization")
    local schema_web_page=$(check_module_enabled "schema_web_page")

    local schema_modules_count=0
    [[ "$schema_metatag" == "enabled" ]] && ((schema_modules_count++))
    [[ "$jsonld" == "enabled" ]] && ((schema_modules_count++))
    [[ "$schema_article" == "enabled" ]] && ((schema_modules_count++))
    [[ "$schema_organization" == "enabled" ]] && ((schema_modules_count++))
    [[ "$schema_web_page" == "enabled" ]] && ((schema_modules_count++))

    cat <<EOF
{
    "modules": {
        "schema_metatag": "$schema_metatag",
        "jsonld": "$jsonld",
        "schema_article": "$schema_article",
        "schema_organization": "$schema_organization",
        "schema_web_page": "$schema_web_page"
    },
    "enabled_count": $schema_modules_count,
    "has_schema_support": $([ "$schema_modules_count" -gt 0 ] && echo "true" || echo "false")
}
EOF
}

# ============================================
# Redirect Analysis
# ============================================

analyze_redirects() {
    local redirect_status=$(check_module_enabled "redirect")
    local global_redirect_status=$(check_module_enabled "global_redirect")

    if [[ "$redirect_status" == "enabled" ]]; then
        local redirect_count=$(ddev drush sql-query "SELECT COUNT(*) FROM redirect;" 2>/dev/null | grep -E '^[0-9]+$' | head -1 | tr -d ' ' || echo "0")

        cat <<EOF
{
    "redirect_module": "$redirect_status",
    "global_redirect_module": "$global_redirect_status",
    "total_redirects": $redirect_count
}
EOF
    else
        cat <<EOF
{
    "redirect_module": "$redirect_status",
    "global_redirect_module": "$global_redirect_status",
    "message": "Redirect module not enabled - no redirect management available"
}
EOF
    fi
}

# ============================================
# Full Analysis
# ============================================

full_analysis() {
    cat <<EOF
{
    "seo_modules": $(analyze_seo_modules),
    "metatags": $(analyze_metatags),
    "url_aliases": $(analyze_url_aliases),
    "sitemap": $(analyze_sitemap),
    "robotstxt": $(analyze_robotstxt),
    "schema_markup": $(analyze_schema_markup),
    "redirects": $(analyze_redirects)
}
EOF
}

# ============================================
# Main Execution
# ============================================

case "$SECTION" in
    seo_modules)
        analyze_seo_modules
        ;;
    metatags)
        analyze_metatags
        ;;
    url_aliases)
        analyze_url_aliases
        ;;
    sitemap)
        analyze_sitemap
        ;;
    robotstxt)
        analyze_robotstxt
        ;;
    schema_markup)
        analyze_schema_markup
        ;;
    redirects)
        analyze_redirects
        ;;
    all)
        full_analysis
        ;;
    *)
        echo "{\"error\": \"Unknown section: $SECTION\"}"
        exit 1
        ;;
esac

