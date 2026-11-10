#!/bin/bash
# Central registry of all audit commands
# Format: "section_name|key|type|command"
# Types: json (parsed as JSON object), text (treated as string)

COMMANDS=(
    # ============================================
    # Section: System Information
    # ============================================
    "system_information|drush_status|json|ddev drush status --format=json"
    "system_information|php_version|text|ddev exec php -v"
    "system_information|drupal_version|text|ddev drush core:status --field=drupal-version"

    # ============================================
    # Section: Drupal Modules
    # ============================================
    "drupal_modules|statistics_total|text|ddev drush pm:list --format=json 2>/dev/null | jq '. | length'"
    "drupal_modules|statistics_enabled|text|ddev drush pm:list --status=enabled --format=json 2>/dev/null | jq '. | length'"
    "drupal_modules|statistics_disabled|text|ddev drush pm:list --status=disabled --format=json 2>/dev/null | jq '. | length'"
    "drupal_modules|statistics_custom|text|find \${DOCROOT}/modules/custom -name '*.info.yml' 2>/dev/null | wc -l | tr -d ' '"
    "drupal_modules|statistics_contrib|text|find \${DOCROOT}/modules/contrib -name '*.info.yml' 2>/dev/null | wc -l | tr -d ' '"
    "drupal_modules|enabled_modules_core|json|ddev drush pm:list --status=enabled --format=json 2>/dev/null | jq 'to_entries | map(select(.value.package == \"Core\")) | map({key: .key, value: {name: .value.name, version: .value.version, package: .value.package, type: .value.type}}) | from_entries'"
    "drupal_modules|enabled_modules_contrib|json|ddev drush pm:list --status=enabled --format=json 2>/dev/null | jq 'to_entries | map(select(.value.path | contains(\"/contrib/\"))) | map({key: .key, value: {name: .value.name, version: .value.version, package: .value.package, type: .value.type}}) | from_entries'"
    "drupal_modules|enabled_modules_custom|json|ddev drush pm:list --status=enabled --format=json 2>/dev/null | jq 'to_entries | map(select(.value.path | contains(\"/custom/\"))) | map({key: .key, value: {name: .value.name, version: .value.version, package: .value.package, type: .value.type}}) | from_entries'"
    "drupal_modules|composer_drupal_core|json|ddev composer show drupal/core --format=json 2>/dev/null | jq '{name: .name, version: .versions[0], php_requirement: (.requires.php // \"unknown\")}'"
    "drupal_modules|composer_direct_dependencies|json|ddev composer show --direct 'drupal/*' --format=json 2>/dev/null | jq '[.installed[] | {name: .name, version: .version, description: .description}]'"
    "drupal_modules|patches_count|text|ddev exec cat composer.json 2>/dev/null | jq -r '.extra.patches // {} | [.[]] | flatten | length' 2>/dev/null || echo '0'"
    "drupal_modules|patches_list|json|ddev exec cat composer.json 2>/dev/null | jq -c '.extra.patches // {}' 2>/dev/null || echo '{}'"
    "drupal_modules|custom_modules|json|bash \${BASE_DIR}/scripts/analyze_custom_modules.sh"

    # ============================================
    # Section: Updates Check
    # Critical: Shows which vulnerabilities affect ENABLED vs DISABLED modules
    # ============================================
    "updates_check|security_analysis|json|bash \${BASE_DIR}/scripts/analyze_security_updates.sh"
    "updates_check|composer_validate|text|ddev composer validate 2>&1"
    "updates_check|outdated_drupal_packages|json|ddev composer outdated 'drupal/*' --format=json 2>/dev/null || echo '{}'"
    "updates_check|outdated_all_packages_count|text|ddev composer outdated --format=json 2>/dev/null | jq '.installed | length' 2>/dev/null || echo '0'"

    # ============================================
    # Section: Hacked Module Check
    # Auto-installs Hacked module if missing
    # Cross-references modifications with composer.json patches
    # ============================================
    "hacked_module_check|integrity_analysis|json|bash \${BASE_DIR}/scripts/analyze_hacked_modules.sh"

    # ============================================
    # Section: Recommended Modules (SEO, Security, Performance)
    # Checks installation status of all recommended module sets
    # Module lists defined in: scripts/recommended_modules_registry.sh
    # Easy to extend with new module sets!
    # ============================================
    "modules_recommendations|analysis|json|bash \${BASE_DIR}/scripts/analyze_recommended_modules.sh all"

    # ============================================
    # Section: Drupal Themes
    # Analyzes installed themes (core/contrib/custom)
    # Shows default theme, admin theme, and custom theme details
    # ============================================
    "drupal_themes|statistics_total|text|ddev drush pm:list --type=theme --format=json 2>/dev/null | jq '. | length'"
    "drupal_themes|statistics_enabled|text|ddev drush pm:list --type=theme --status=enabled --format=json 2>/dev/null | jq '. | length'"
    "drupal_themes|statistics_core|text|find \${DOCROOT}/core/themes -maxdepth 1 -name '*.info.yml' 2>/dev/null | wc -l | tr -d ' '"
    "drupal_themes|statistics_contrib|text|find \${DOCROOT}/themes/contrib -name '*.info.yml' 2>/dev/null | wc -l | tr -d ' '"
    "drupal_themes|statistics_custom|text|find \${DOCROOT}/themes/custom -name '*.info.yml' 2>/dev/null | wc -l | tr -d ' '"
    "drupal_themes|default_theme|json|ddev drush config:get system.theme --format=json 2>/dev/null | jq '{default: .default, admin: .admin}'"
    "drupal_themes|all_themes|json|ddev drush pm:list --type=theme --format=json 2>/dev/null | jq 'to_entries | map({key: .key, value: {name: .value.name, version: .value.version, status: .value.status, path: .value.path}}) | from_entries'"
    "drupal_themes|core_themes|json|ddev drush pm:list --type=theme --format=json 2>/dev/null | jq 'to_entries | map(select(.value.path | startswith(\"core/themes/\"))) | map({key: .key, value: {name: .value.name, version: .value.version, status: .value.status}}) | from_entries'"
    "drupal_themes|contrib_themes|json|ddev drush pm:list --type=theme --format=json 2>/dev/null | jq 'to_entries | map(select(.value.path | startswith(\"themes/contrib/\"))) | map({key: .key, value: {name: .value.name, version: .value.version, status: .value.status}}) | from_entries'"
    "drupal_themes|custom_themes|json|bash \${BASE_DIR}/scripts/analyze_custom_themes.sh"

    # ============================================
    # Section: Entity Structure
    # Comprehensive analysis of Drupal entity system:
    # - Entity types and bundles
    # - Field configurations
    # - Record counts (total, last year, last month)
    # - Custom entities from custom modules
    # - Mermaid.js diagram for visualization
    # ============================================

    # Overall entity statistics
    "entity_structure|statistics_content_types_count|text|bash \${BASE_DIR}/scripts/get_entity_data.sh content_types_count"
    "entity_structure|statistics_total_nodes|text|ddev drush sql-query \"SELECT COUNT(*) FROM node_field_data\" 2>/dev/null | head -1 | tr -d ' '"
    "entity_structure|statistics_taxonomy_vocabs_count|text|bash \${BASE_DIR}/scripts/get_entity_data.sh taxonomy_vocabs_count"
    "entity_structure|statistics_total_terms|text|ddev drush sql-query \"SELECT COUNT(*) FROM taxonomy_term_field_data\" 2>/dev/null | head -1 | tr -d ' '"
    "entity_structure|statistics_total_users|text|ddev drush sql-query \"SELECT COUNT(*) FROM users_field_data\" 2>/dev/null | head -1 | tr -d ' '"
    "entity_structure|statistics_media_types_count|text|bash \${BASE_DIR}/scripts/get_entity_data.sh media_types_count"
    "entity_structure|statistics_total_media|text|ddev drush sql-query \"SELECT COUNT(*) FROM media_field_data\" 2>/dev/null | head -1 | tr -d ' '"

    # Content types with detailed statistics
    "entity_structure|content_types_list|json|ddev drush eval \"echo json_encode(array_keys(\\Drupal::service('entity_type.bundle.info')->getBundleInfo('node')));\" 2>/dev/null"
    "entity_structure|content_types_with_counts|json|bash \${BASE_DIR}/scripts/get_entity_data.sh content_types_with_counts"

    # Taxonomy vocabularies with statistics
    "entity_structure|taxonomy_vocabs_list|json|ddev drush eval \"echo json_encode(array_keys(\\Drupal::service('entity_type.bundle.info')->getBundleInfo('taxonomy_term')));\" 2>/dev/null"
    "entity_structure|taxonomy_with_counts|json|bash \${BASE_DIR}/scripts/get_entity_data.sh taxonomy_with_counts"

    # Media types with statistics
    "entity_structure|media_types_list|json|ddev drush eval \"echo json_encode(array_keys(\\Drupal::service('entity_type.bundle.info')->getBundleInfo('media')));\" 2>/dev/null || echo '[]'"
    "entity_structure|media_with_counts|json|bash \${BASE_DIR}/scripts/get_entity_data.sh media_with_counts"

    # Paragraph types (if paragraphs module is enabled)
    "entity_structure|paragraph_types_list|json|ddev drush eval \"if (\\Drupal::moduleHandler()->moduleExists('paragraphs')) { echo json_encode(array_keys(\\Drupal::service('entity_type.bundle.info')->getBundleInfo('paragraph'))); } else { echo '[]'; }\" 2>/dev/null"

    # User statistics and roles
    "entity_structure|users_statistics|json|bash \${BASE_DIR}/scripts/get_entity_data.sh users_statistics"
    "entity_structure|user_roles|json|bash \${BASE_DIR}/scripts/get_entity_data.sh user_roles"

    # Canvas entity statistics (if canvas module is enabled)
    "entity_structure|canvas_enabled|text|ddev drush eval \"echo \\Drupal::moduleHandler()->moduleExists('canvas') ? '1' : '0';\" 2>/dev/null"
    "entity_structure|canvas_statistics|json|bash \${BASE_DIR}/scripts/get_entity_data.sh canvas_statistics"

    # Comprehensive entity structure analysis (uses helper script)
    "entity_structure|full_analysis|json|bash \${BASE_DIR}/scripts/analyze_entity_structure.sh"

    # ============================================
    # Section: Menu Structure
    # Analyzes Drupal menu system:
    # - All menus (machine name, label, description, items count)
    # - Main menu structure as JSON tree (with hierarchy)
    # - Mermaid.js diagram for visualization
    # - Statistics (total menus, items per menu, max depth)
    # ============================================
    "menu_structure|all_menus|json|bash \${BASE_DIR}/scripts/analyze_menu_structure.sh all_menus"
    "menu_structure|main_menu_tree|json|bash \${BASE_DIR}/scripts/analyze_menu_structure.sh main_menu_tree"
    "menu_structure|statistics|json|bash \${BASE_DIR}/scripts/analyze_menu_structure.sh statistics"
    "menu_structure|mermaid_diagram|text|bash \${BASE_DIR}/scripts/analyze_menu_structure.sh mermaid_diagram"

    # ============================================
    # Section: Views
    # Analyzes Drupal Views system:
    # - All views with detailed configuration
    # - Statistics (total, enabled, custom, with relationships)
    # - Routes (page displays with paths)
    # - Blocks (block displays with block IDs)
    # - Display types, exposed filters, items per page
    # - Base entity types and relationships
    # ============================================
    "views|full_analysis|json|bash \${BASE_DIR}/scripts/analyze_views.sh all"
    "views|statistics|json|bash \${BASE_DIR}/scripts/analyze_views.sh statistics"
    "views|routes_list|json|bash \${BASE_DIR}/scripts/analyze_views.sh routes"
    "views|blocks_list|json|bash \${BASE_DIR}/scripts/analyze_views.sh blocks"

    # ============================================
    # Section: Workflows
    # Analyzes Drupal Workflows and Content Moderation:
    # - Workflows module and Content Moderation module status
    # - All workflows with states and transitions
    # - Entity type to workflow assignments
    # - Content distribution by moderation state
    # - Statistics (total workflows, states, transitions)
    # ============================================
    "workflows|full_analysis|json|bash \${BASE_DIR}/scripts/analyze_workflows.sh"

    # ============================================
    # Section: Cron Jobs
    # Analyzes Drupal cron system:
    # - Last cron run status and timing
    # - Ultimate Cron module status and jobs
    # - hook_cron implementations (core/contrib/custom)
    # - Queue workers (all and cron-based)
    # - Recent cron errors from watchdog
    # - Statistics (implementations count, queue workers, jobs)
    # ============================================
    "cron_jobs|full_analysis|json|bash \${BASE_DIR}/scripts/analyze_cron.sh"
    "cron_jobs|requirements|text|ddev drush core:requirements --severity=1 2>/dev/null | grep -i cron || echo 'No critical cron-related requirements issues'"

    # ============================================
    # Section: External Integrations
    # Analyzes all external system integrations:
    # - Modules related to APIs, REST, webhooks, integrations
    # - REST module configuration and resources
    # - JSON:API endpoints (content types, media, taxonomy, users)
    # - OAuth and authentication modules
    # - Webhook modules and custom routes
    # - Queue workers (integration points)
    # - HTTP client usage (Guzzle, cURL, file_get_contents)
    # - Third-party libraries (non-Drupal dependencies)
    # - Payment gateways (Commerce, Stripe, PayPal)
    # - Email services (SMTP, SendGrid, Mailchimp)
    # - Social media integrations
    # - Analytics (Google Analytics, GTM, Matomo)
    # - Search services (Solr, Elasticsearch, Algolia)
    # - External storage (S3, Azure, CDN)
    # ============================================
    "external_integrations|full_analysis|json|bash \${BASE_DIR}/scripts/analyze_external_integrations.sh"

    # ============================================
    # Section: Homepage Configuration
    # Comprehensive analysis of Drupal homepage:
    # - Homepage path and type detection (default, static node, view-based, custom route)
    # - Page Manager and Panels configuration
    # - Layout Builder usage on homepage
    # - Blocks placed on homepage (by region)
    # - Homepage metadata (site name, slogan, aliases)
    # - Page builder modules status (Layout Builder, Paragraphs, etc.)
    # - Statistics (blocks count, homepage type, installed modules)
    # ============================================
    "homepage_configuration|full_analysis|json|bash \${BASE_DIR}/scripts/analyze_homepage.sh"

    # ============================================
    # Section: Database Logs (dblog)
    # Analyzes Drupal database logs (watchdog table):
    # - Watchdog table verification
    # - Total log entries count
    # - Log entries by severity (0-7: Emergency to Debug)
    # - Error count (severity 0-3: Emergency, Alert, Critical, Error)
    # - Errors grouped by type (module/component)
    # - Top 50 most frequent errors with counts
    # - Recent errors (last 50 entries)
    # - Exports detailed logs to tmp/ directory for analysis
    # Note: Only works with Drupal 8+ (uses watchdog table)
    # ============================================
    "database_logs|watchdog_table_exists|text|ddev drush sql-query \"SHOW TABLES LIKE 'watchdog';\" 2>/dev/null | grep -q 'watchdog' && echo '1' || echo '0'"
    "database_logs|total_entries|text|ddev drush sql-query \"SELECT COUNT(*) FROM watchdog;\" 2>/dev/null | grep -E '^[0-9]+$' | head -1 | tr -d ' '"
    "database_logs|entries_by_severity|json|ddev drush php-eval \"\\\$db = \\Drupal::database(); \\\$query = \\\$db->query('SELECT severity, COUNT(*) as count FROM {watchdog} GROUP BY severity ORDER BY severity'); \\\$results = []; \\\$sev_names = ['0-Emergency', '1-Alert', '2-Critical', '3-Error', '4-Warning', '5-Notice', '6-Info', '7-Debug']; foreach (\\\$query as \\\$row) { \\\$results[] = ['severity' => \\\$sev_names[\\\$row->severity] ?? \\\$row->severity . '-Unknown', 'count' => (int)\\\$row->count]; } echo json_encode(\\\$results);\" 2>/dev/null"
    "database_logs|error_count|text|ddev drush sql-query \"SELECT COUNT(*) FROM watchdog WHERE severity <= 3;\" 2>/dev/null | grep -E '^[0-9]+$' | head -1 | tr -d ' '"
    "database_logs|errors_by_type|json|ddev drush php-eval \"\\\$db = \\Drupal::database(); \\\$query = \\\$db->query('SELECT type, COUNT(*) as count FROM {watchdog} WHERE severity <= 3 GROUP BY type ORDER BY count DESC LIMIT 20'); \\\$results = []; foreach (\\\$query as \\\$row) { \\\$results[] = ['type' => \\\$row->type, 'count' => (int)\\\$row->count]; } echo json_encode(\\\$results);\" 2>/dev/null"
    "database_logs|detailed_analysis|json|bash \${BASE_DIR}/scripts/analyze_database_logs.sh full_analysis"

    # ============================================
    # Section: Automated Tests
    # Comprehensive analysis of automated tests in Drupal 8+:
    # - Test framework detection (PHPUnit, Behat, Codeception)
    # - PHPUnit tests by type (Unit, Kernel, Functional, FunctionalJavascript)
    # - Tests in custom modules and themes
    # - Behat feature files (.feature)
    # - Codeception tests (Cept, Cest)
    # - Test coverage statistics (modules with/without tests)
    # - Composer testing packages and scripts
    # - Coverage percentage calculation
    # ============================================
    "automated_tests|full_analysis|json|bash \${BASE_DIR}/scripts/analyze_automated_tests.sh"
    "automated_tests|phpunit_config_exists|text|[ -f phpunit.xml ] || [ -f phpunit.xml.dist ] && echo '1' || echo '0'"
    "automated_tests|behat_config_exists|text|[ -f behat.yml ] || [ -f behat.yml.dist ] && echo '1' || echo '0'"
    "automated_tests|codeception_config_exists|text|[ -f codeception.yml ] || [ -f codeception.dist.yml ] && echo '1' || echo '0'"

    # ============================================
    # Section: User Roles and Permissions
    # Comprehensive analysis of user management and access control:
    # - User statistics (total, active, blocked, recent activity)
    # - All roles with weights, permissions, and user assignments
    # - Permissions grouped by category (admin, content, access, usage)
    # - Detailed role assignments (usernames for custom roles)
    # - Security analysis (admin users, multi-role users, blocked users)
    # - Summary statistics (roles count, custom vs system)
    # ============================================
    "user_roles|statistics_total_users|text|ddev drush sql-query \"SELECT COUNT(*) FROM users_field_data WHERE uid > 0;\" 2>/dev/null | grep -E '^[0-9]+\$' | head -1 | tr -d ' '"
    "user_roles|statistics_active_users|text|ddev drush sql-query \"SELECT COUNT(*) FROM users_field_data WHERE uid > 0 AND status = 1;\" 2>/dev/null | grep -E '^[0-9]+\$' | head -1 | tr -d ' '"
    "user_roles|statistics_blocked_users|text|ddev drush sql-query \"SELECT COUNT(*) FROM users_field_data WHERE uid > 0 AND status = 0;\" 2>/dev/null | grep -E '^[0-9]+\$' | head -1 | tr -d ' '"
    "user_roles|statistics_total_roles|text|ddev drush role:list --format=json 2>/dev/null | jq '. | length'"
    "user_roles|full_analysis|json|bash \${BASE_DIR}/scripts/analyze_user_roles.sh"

    # ============================================
    # Section: Multisite and Multi-Domain
    # Comprehensive analysis of multi-domain and multisite configurations:
    # - Domain module detection (installation, status, records)
    # - Domain Access module status
    # - Domain-related modules and their status
    # - Multisite directory structure analysis
    # - sites.php configuration detection
    # - Site-specific directories and settings files
    # - Summary: single vs multi-domain vs multisite setup
    # ============================================
    "multisite_domain|full_analysis|json|bash \${BASE_DIR}/scripts/analyze_multisite_domain.sh"
    "multisite_domain|domain_module_check|text|ddev drush pm:list --format=json 2>/dev/null | jq -r 'to_entries[] | select(.key == \"domain\") | .value.status' || echo 'not_installed'"
    "multisite_domain|sites_directory_check|text|[ -d \${DOCROOT}/sites ] && echo '1' || echo '0'"
    "multisite_domain|sites_php_exists|text|[ -f \${DOCROOT}/sites/sites.php ] && echo '1' || echo '0'"

    # ============================================
    # Section: Multilingual Support
    # Comprehensive analysis of Drupal multilingual capabilities:
    # - Language module status (foundation for multilingual)
    # - Core translation modules (content, interface, config translation)
    # - Installed languages with details (code, name, direction, weight, default)
    # - Language statistics (total languages configured)
    # - Translatable content types with node counts per language
    # - Translated content statistics (nodes by language)
    # - Contrib multilingual modules (Lingotek, TMGMT, etc.)
    # - Language detection and switching configuration
    # Note: Requires Language module to be enabled
    # ============================================
    "multilingual|full_analysis|json|bash \${BASE_DIR}/scripts/analyze_multilingual.sh"
    "multilingual|language_module_status|text|ddev drush pm:list --format=json 2>/dev/null | jq -r 'to_entries[] | select(.key == \"language\") | .value.status' || echo 'not_enabled'"
    "multilingual|installed_languages_count|text|ddev drush eval \"echo count(\\Drupal::languageManager()->getLanguages());\" 2>/dev/null || echo '1'"
    "multilingual|default_language|text|ddev drush eval \"echo \\Drupal::languageManager()->getDefaultLanguage()->getId();\" 2>/dev/null || echo 'en'"

    # ============================================
    # Section: Composer and Codebase Synchronization
    # Critical: Detects manual additions to contrib directories bypassing Composer
    # Uses composer.lock to include ALL dependencies (direct + transitive)
    # - Accounts for modules from installation profiles (Droopler, Open Intranet)
    # - Modules in filesystem but not in composer.lock (manually added)
    # - Themes in filesystem but not in composer.lock (manually added)
    # - Packages in composer.lock but missing from filesystem
    # - Sync status (synced/minor_issues/major_issues)
    # - Actionable recommendations for fixing sync issues
    # Helps detect: manual FTP uploads, git commits of contrib code, incomplete deployments
    # ============================================
    "composer_codebase_sync|full_analysis|json|bash \${BASE_DIR}/scripts/analyze_composer_codebase_sync.sh"
    "composer_codebase_sync|composer_validate|text|ddev composer validate --no-check-publish 2>&1 | head -20"
    "composer_codebase_sync|composer_lock_exists|text|[ -f composer.lock ] && echo '1' || echo '0'"
    "composer_codebase_sync|composer_outdated_count|text|ddev composer outdated 'drupal/*' --format=json 2>/dev/null | jq '.installed | length' 2>/dev/null || echo '0'"

    # ============================================
    # Section: Performance Analysis
    # ============================================
    # Comprehensive performance analysis: frontend (Lighthouse) + backend (configuration)
    # FRONTEND: Uses Google Lighthouse - FCP, Speed Index, LCP, TTI, TBT, CLS
    # BACKEND: Cache config, database indexes, PHP settings, performance modules,
    #          views analysis, code analysis, CSS/JS aggregation, image optimization
    # Requires: lighthouse CLI for frontend (npm install -g lighthouse)
    # Note: Set BASE_URL for frontend analysis: export BASE_URL="https://your-site.com"
    # ============================================
    "performance|frontend_analysis|json|bash \${BASE_DIR}/scripts/analyze_performance.sh \"\${BASE_URL:-}\" frontend"
    # Sub-keys below are copied from backend_analysis (already computed) instead of running the script again
    # (fallback: run the script for that part if the full analysis failed)
    "performance|backend_analysis|json|bash \${BASE_DIR}/scripts/analyze_performance.sh \"\" backend"
    "performance|cache_configuration|json|bash \${BASE_DIR}/scripts/reuse_section_key.sh backend_analysis cache_configuration bash \${BASE_DIR}/scripts/analyze_performance.sh \"\" cache_config"
    "performance|database_indexes|json|bash \${BASE_DIR}/scripts/reuse_section_key.sh backend_analysis database_indexes bash \${BASE_DIR}/scripts/analyze_performance.sh \"\" database_indexes"
    "performance|php_settings|json|bash \${BASE_DIR}/scripts/reuse_section_key.sh backend_analysis php_settings bash \${BASE_DIR}/scripts/analyze_performance.sh \"\" php_settings"
    "performance|performance_modules|json|bash \${BASE_DIR}/scripts/reuse_section_key.sh backend_analysis performance_modules bash \${BASE_DIR}/scripts/analyze_performance.sh \"\" performance_modules"
    "performance|views_performance|json|bash \${BASE_DIR}/scripts/reuse_section_key.sh backend_analysis views_performance bash \${BASE_DIR}/scripts/analyze_performance.sh \"\" views_analysis"
    "performance|code_performance|json|bash \${BASE_DIR}/scripts/reuse_section_key.sh backend_analysis code_performance bash \${BASE_DIR}/scripts/analyze_performance.sh \"\" code_analysis"
    "performance|css_js_aggregation|json|bash \${BASE_DIR}/scripts/reuse_section_key.sh backend_analysis css_js_aggregation bash \${BASE_DIR}/scripts/analyze_performance.sh \"\" aggregation"
    "performance|image_optimization|json|bash \${BASE_DIR}/scripts/reuse_section_key.sh backend_analysis image_optimization bash \${BASE_DIR}/scripts/analyze_performance.sh \"\" image_optimization"

    # ============================================
    # Section: Configuration Management
    # Comprehensive analysis of Drupal configuration sync and management:
    # - Config directory location and verification (../config/sync or custom path)
    # - Config sync status (differences between filesystem and database)
    # - Config Split module: environment-specific configuration splits
    # - Config Ignore module: patterns excluded from config sync
    # - Config Filter module: config transformation middleware
    # - Config Readonly module: production config lock status (CRITICAL for prod)
    # - Config Devel module: dev-only tools (WARNING if enabled in production)
    # - All config-related modules inventory
    # - Statistics: file counts, database configs, sync differences
    # Purpose: Ensure config management best practices and detect config drift
    # ============================================
    # Sub-keys below are copied from full_analysis (already computed) instead of running the script again
    # (fallback: run the script for that part if the full analysis failed)
    "configuration_management|full_analysis|json|bash \${BASE_DIR}/scripts/analyze_config_management.sh full_analysis"
    "configuration_management|config_directory|json|bash \${BASE_DIR}/scripts/reuse_section_key.sh full_analysis config_directory bash \${BASE_DIR}/scripts/analyze_config_management.sh config_directory"
    "configuration_management|sync_status|json|bash \${BASE_DIR}/scripts/reuse_section_key.sh full_analysis sync_status bash \${BASE_DIR}/scripts/analyze_config_management.sh sync_status"
    "configuration_management|statistics|json|bash \${BASE_DIR}/scripts/reuse_section_key.sh full_analysis statistics bash \${BASE_DIR}/scripts/analyze_config_management.sh statistics"

    # ============================================
    # Section: Accessibility (WCAG 2.1)
    # ============================================
    # Uses Pa11y to analyze website accessibility compliance with WCAG 2.1 Level AA
    # Tests homepage for accessibility issues and generates detailed report
    # Measures: Errors, warnings, WCAG principles breakdown, accessibility score
    # Requires: pa11y CLI (npm install -g pa11y) and BASE_URL environment variable
    # Note: Set BASE_URL before running: export BASE_URL="https://your-site.com"
    # ============================================
    "accessibility|analysis|json|bash \${BASE_DIR}/scripts/analyze_accessibility.sh \${BASE_URL:-}"

    # ============================================
    # Section: Code Quality Tools
    # ============================================
    # Analyzes code quality and static analysis tools configuration
    # Checks for: PHPStan, Psalm, PHPCS, PHPMD, PHP CS Fixer, Phan, Rector, etc.
    # Detects: Config files, composer packages, DDEV commands, CI/CD integration
    # Shows: Tool name, description, configuration status, file locations
    # Purpose: Assess code quality automation and static analysis maturity
    # ============================================
    "code_quality_tools|analysis|json|bash \${BASE_DIR}/scripts/analyze_code_quality_tools.sh"

    # ============================================
    # Section: Git Repository
    # ============================================
    # Comprehensive analysis of git repository and version control practices
    # Checks for: Repository existence, branches (local/remote), main branch detection
    # Workflow detection: Git Flow, Feature Branch, Environment-based, Trunk-based
    # Commit history: Recent commits, frequency, signed commits, conventional commits
    # Contributors: Total, active contributors, top contributors by commit count
    # Repository health: Essential files (.gitignore, README, CONTRIBUTING, CODEOWNERS)
    # CI/CD: GitHub Actions, GitLab CI, Jenkins configuration detection
    # Releases: Tags count, latest release
    # Activity status: Days since last commit, activity level
    # Recommendations: Best practices and improvements for repository management
    # Purpose: Assess version control maturity and collaboration practices
    # ============================================
    "git_repository|full_analysis|json|bash \${BASE_DIR}/scripts/analyze_git_repository.sh"

    # ============================================
    # Section: Legal Compliance
    # ============================================
    # Analyzes website legal compliance (GDPR/RODO, cookies, privacy)
    # Checks for: Cookie consent banners (PL + EN)
    # Privacy policy links and accessibility (PL + EN)
    # GDPR/RODO compliance mentions
    # Detects popular cookie libraries: Cookiebot, OneTrust, CookieConsent, etc.
    # Provides compliance score and actionable recommendations
    # Requires: curl and BASE_URL environment variable
    # Note: Set BASE_URL before running: export BASE_URL="https://your-site.com"
    # Purpose: Ensure legal compliance with EU data protection regulations
    # ============================================
    "legal_compliance|analysis|json|bash \${BASE_DIR}/scripts/analyze_legal_compliance.sh \${BASE_URL:-}"

    # ============================================
    # Section: Backup Strategy
    # ============================================
    # Comprehensive analysis of backup configuration and practices:
    # - Backup and Migrate module (status, configuration, destinations, schedules)
    # - Custom backup scripts in project root, /scripts, and .ddev directories
    # - DDEV snapshots configuration and count
    # - Private file path for secure backup storage
    # - Composer scripts related to backups
    # - Documentation files mentioning backup procedures
    # - Other backup-related modules (backup_db, backup_files, ultimate_cron)
    # - Database backup command availability (drush sql-dump)
    # - Cron jobs detection (limited in DDEV, requires server analysis)
    # Note: Server-side backup scripts often not detectable from codebase
    # Recommendation: Separate production server configuration analysis needed
    # Purpose: Assess backup preparedness and disaster recovery capabilities
    # ============================================
    "backup_strategy|full_analysis|json|bash \${BASE_DIR}/scripts/analyze_backup_strategy.sh"

    # ============================================
    # Section: SEO Analysis
    # ============================================
    # Comprehensive SEO configuration and best practices analysis:
    # - SEO modules status (metatag, pathauto, simple_sitemap, redirect, etc.)
    # - Metatags configuration (global defaults, entity types, Open Graph, Twitter Cards)
    # - URL aliases and Pathauto patterns (automatic URL generation)
    # - Sitemap.xml generation (simple_sitemap or xmlsitemap modules)
    # - Robots.txt file analysis (rules, sitemap reference, crawler access)
    # - Schema.org structured data markup (schema_metatag, jsonld modules)
    # - Redirect management (redirect, global_redirect modules)
    # Purpose: Ensure search engine optimization and discoverability
    # ============================================
    # Sub-keys below are copied from full_analysis (already computed) instead of running the script again
    # (fallback: run the script for that part if the full analysis failed)
    "seo_analysis|full_analysis|json|bash \${BASE_DIR}/scripts/analyze_seo.sh all"
    "seo_analysis|seo_modules|json|bash \${BASE_DIR}/scripts/reuse_section_key.sh full_analysis seo_modules bash \${BASE_DIR}/scripts/analyze_seo.sh seo_modules"
    "seo_analysis|metatags|json|bash \${BASE_DIR}/scripts/reuse_section_key.sh full_analysis metatags bash \${BASE_DIR}/scripts/analyze_seo.sh metatags"
    "seo_analysis|url_aliases|json|bash \${BASE_DIR}/scripts/reuse_section_key.sh full_analysis url_aliases bash \${BASE_DIR}/scripts/analyze_seo.sh url_aliases"
    "seo_analysis|sitemap|json|bash \${BASE_DIR}/scripts/reuse_section_key.sh full_analysis sitemap bash \${BASE_DIR}/scripts/analyze_seo.sh sitemap"
    "seo_analysis|robotstxt|json|bash \${BASE_DIR}/scripts/reuse_section_key.sh full_analysis robotstxt bash \${BASE_DIR}/scripts/analyze_seo.sh robotstxt"
    "seo_analysis|schema_markup|json|bash \${BASE_DIR}/scripts/reuse_section_key.sh full_analysis schema_markup bash \${BASE_DIR}/scripts/analyze_seo.sh schema_markup"
    "seo_analysis|redirects|json|bash \${BASE_DIR}/scripts/reuse_section_key.sh full_analysis redirects bash \${BASE_DIR}/scripts/analyze_seo.sh redirects"
)
