# DRUSCAN - Instructions for AI Agents

DRUSCAN is an automated technical audit tool for Drupal sites, written in Bash. This file holds the project rules for AI coding agents.

## Agent Files Layout

- `AGENTS.md` - project rules (this file). `CLAUDE.md` is a symlink to it.
- `.agents/skills/` - agent skills in the [Agent Skills](https://agentskills.io/specification) format. `.claude/skills` is a symlink to it.
- `.agents/skills/drupal-audit/SKILL.md` - runs a full audit and writes the AI analysis into the HTML report.

When adding a skill, create `.agents/skills/<skill-name>/SKILL.md` with `name` (same as the directory name) and `description` in the YAML frontmatter. Do not edit `CLAUDE.md` or `.claude/skills` directly - they are symlinks.

## Always use this approach:

- Use simple words in output.
- Do not say anything inaccurate. If you don't know something, say so. You can also use MCP Perplexity to find answers.
- If something can be done with a script, then create a temporary script in ./tmp/ directory and run this script.
- If something is complex, then create a list of subtasks in ./tmp/todo_[some-description].md and add list of subtasks, use markdown checklist to mark what is done
- Remember the use case of this project/repository


## Project Naming Convention
**IMPORTANT**: The project name is always written as **DRUSCAN** (all uppercase).
- Use "DRUSCAN" in all documentation, code comments, and output
- Never use variations like "DruScan", "Druscan", or "druscan"


## Content Quality Rule
**IMPORTANT**: Keep audit reports concise and focused on value:
- Shorten tables - show only relevant data, not everything available
- Avoid producing unnecessary content that has no value for the reader
- Focus on actionable insights and findings
- Summarize large datasets instead of displaying complete outputs
- Only include details that support decision-making or reveal important issues


## Drupal Version Compatibility
**IMPORTANT**: All audit scripts are designed for **Drupal 8, 9, 10, 11** only.
- Scripts use `watchdog` table (standard in Drupal 8+)
- Commands use Drush 11+ syntax
- Database schema is based on Drupal 8+ structure
- **Drupal 7 is NOT supported** by these audit scripts


## Use case
- **Primary:** Hand over system from one company/agency to another WITHOUT exposing sensitive data, proprietary code, or database content (safe sharing with 3-5 agencies for accurate quotes)
- Check if developer/agency is doing a good job
- Check if system is secure and could be improved
- Estimate maintenance costs and technical debt
- Plan upgrade path to newer Drupal version
- Assess performance bottlenecks and scalability issues
- Verify compliance with accessibility and data protection standards


## Date Verification Rule
**CRITICAL**: Before writing ANY date to .md files, ALWAYS check the current system date first using `date` command. Never use example dates or assume the current date.



## Audit Automation Architecture

The audit system uses **two main files**:
1. **`audit.sh`** - Main orchestration script
2. **`commands_registry.sh`** - Central registry of all audit commands

### How It Works

**`audit.sh`** performs:
- Creates timestamped output directory: `audits_reports/{timestamp}_{site_name}/`
- Copies HTML template to output directory
- Detects Drupal document root (web/ or docroot/)
- Loads command definitions from `commands_registry.sh`
- Executes commands and saves results to JSON files
- Validates JSON output and adds metadata
- Tracks failed commands: prints errors and warnings in the final summary and saves details (command, exit code, stderr) to `audits_reports/{timestamp}_{site_name}/errors.log`
- Exit codes: `0` = OK, `1` = audit did not run (bad parameters, unknown section, DDEV not accessible), `2` = audit completed with errors

**`commands_registry.sh`** contains:
- Array of command definitions in format: `"section_name|key|type|command"`
- All audit commands organized by section

### Usage

```bash
# Run all sections
./audit.sh site_name production_url

# Run single section only
./audit.sh site_name production_url section_name

# Examples
./audit.sh droptica.com https://droptica.com
./audit.sh droptica.com https://droptica.com code_quality_tools

# Results saved to: audits_reports/{timestamp}_site_name/
```

**Parameters:**
- `site_name` (required) - Name of symlink in `drupal_sites/` directory
- `production_url` (required) - Production URL for testing (used by `performance` and `accessibility` sections)
- `section_name` (optional) - Specific section to audit (e.g., `drupal_modules`, `code_quality_tools`)


## Adding Commands to Registry

### Command Format

```bash
"section_name|key|type|command"
```

**Parameters:**
- `section_name` - Output file name (without extension)
- `key` - Unique identifier for this data point
- `type` - Either `json` (parsed as JSON) or `text` (stored as string)
- `command` - Shell command to execute (must use `ddev` prefix)

### Examples

```bash
# Simple text output
"system_information|php_version|text|ddev exec php -v"

# JSON output
"system_information|drush_status|json|ddev drush status --format=json"

# Using jq with DOCROOT variable
"drupal_modules|custom_count|text|find \${DOCROOT}/modules/custom -name '*.info.yml' 2>/dev/null | wc -l | tr -d ' '"

# SQL query with escaping
"entity_structure|content_types|json|ddev drush sql-query \"SELECT type, COUNT(*) FROM node_field_data GROUP BY type\" --format=json"

# Fallback for optional features
"hacked_check|status|text|ddev drush hacked:list-projects 2>/dev/null || echo 'Hacked module not installed'"
```

### Common Mistakes

```bash
# ❌ WRONG - Missing quotes
drupal_modules|enabled|json|ddev drush pm:list --format=json

# ❌ WRONG - Not escaping inner quotes
"entity_structure|types|json|ddev drush sql-query "SELECT * FROM node""

# ❌ WRONG - Hardcoded path (use DOCROOT variable)
"custom_modules|list|text|ls -1 web/modules/custom/"

# ❌ WRONG - Not using ddev prefix
"system_info|version|text|drush status"
```

### Escaping Rules

1. **Outer quotes**: Always use double quotes `"` for array entry
2. **Inner quotes**: Escape with backslash `\"` for SQL queries
3. **Variables**: Use `\${VARNAME}` for DOCROOT and BASE_DIR
4. **Pipes and redirects**: No escaping needed (`|`, `>`, `2>/dev/null`)

### Best Practices

1. **Keep commands simple** - Avoid overly complex one-liners
2. **Use error suppression** - Add `2>/dev/null` to prevent error clutter
3. **Add fallbacks** - Use `|| echo 'fallback message'` for optional features
4. **Test incrementally** - `./audit.sh droptica.com section_name`
5. **Always use DOCROOT** - Don't hardcode `web/` or `docroot/`
6. **Move complex logic to `./scripts/`** - If command exceeds 200 characters

### When to Use Helper Scripts in `./scripts/`

Move logic to `./scripts/` when:
- Command requires loops or conditional logic
- Multiple file reads/writes are needed
- Logic exceeds 200 characters in single line
- Need to build complex JSON structures from multiple sources

**Example:**
```bash
# ❌ TOO COMPLEX for commands_registry.sh
"drupal_modules|custom|json|MODULES='[]'; for dir in modules/custom/*/; do...[100+ lines]...done"

# ✅ CORRECT - Use helper script
"drupal_modules|custom|json|bash \${BASE_DIR}/scripts/analyze_custom_modules.sh"
```

### Variables Available in Commands

- `${DOCROOT}` - Detected document root (e.g., `web` or `docroot`)
- `${BASE_DIR}` - Project root directory
- All commands run from: `drupal_sites/{site_name}/` directory


## JSON Output Optimization

**CRITICAL**: Keep JSON output concise and developer-focused.

### Optimization Principles

1. **Filter unnecessary fields** - Only include fields developers need
2. **Remove verbose metadata** - Avoid fields like `autoload`, `source`, `dist`
3. **Categorize logically** - Group by purpose (core/contrib/custom)
4. **Aim for 60-70% size reduction** without losing essential information

### Example

```bash
# ❌ UNOPTIMIZED - Returns all fields (100+ lines per module)
"drupal_modules|enabled|json|ddev drush pm:list --status=enabled --format=json"

# ✅ OPTIMIZED - Returns only essential fields
"drupal_modules|enabled_core|json|ddev drush pm:list --status=enabled --format=json 2>/dev/null | jq 'to_entries | map(select(.value.package == \"Core\")) | map({key: .key, value: {name: .value.name, version: .value.version, package: .value.package, type: .value.type}}) | from_entries'"
```

### What to KEEP vs REMOVE

**✅ KEEP (Essential):**
- Name, version, description
- Package/category information
- Enabled/disabled status
- Dependencies (direct only)
- PHP/Drupal version requirements
- Custom code analysis (lines, functions, entities)

**❌ REMOVE (Unnecessary):**
- Full autoload configuration
- Git source URLs
- Distribution metadata
- All transitive dependencies
- Internal Drupal paths


## Common Issues and Solutions

### Issue: jq Number Conversion Error
**Cause:** Commands like `wc -l` output numbers with leading spaces

**Solution:** Remove spaces before passing to jq
```bash
# ❌ WRONG
find ... | wc -l | jq 'tonumber'

# ✅ CORRECT
find ... | wc -l | tr -d ' ' | jq 'tonumber'
```

### Issue: Complex Command Escaping
**Solution:** Use helper script in `./scripts/` for complex logic
```bash
# ✅ CORRECT
"section|key|json|bash \${BASE_DIR}/scripts/helper_script.sh"
```

### Issue: Path Issues After cd
**Cause:** `audit.sh` changes to `drupal_sites/$SITE_NAME` before executing

**Solution:** Always use `${DOCROOT}` or paths relative to site root
```bash
# ✅ CORRECT
"section|key|text|cat \${DOCROOT}/sites/default/settings.php"
```


## Section Naming Convention

**IMPORTANT**: Use descriptive section names WITHOUT numeric prefixes.

```bash
# ❌ WRONG - Numeric prefixes
"01_system_information|key|type|command"

# ✅ CORRECT - Descriptive names only
"system_information|key|type|command"
```

**Why no prefixes?**
- Easier to reference: `./audit.sh droptica.com drupal_modules`
- No renumbering when adding/removing sections
- Cleaner filenames: `drupal_modules.json` not `02_drupal_modules.json`

### Section Organization

```bash
COMMANDS=(
    # ============================================
    # Section: System Information
    # ============================================
    "system_information|php_version|text|ddev exec php -v"

    # ============================================
    # Section: Drupal Modules
    # ============================================
    "drupal_modules|statistics_total|text|..."
)
```


## Testing New Registry Commands

**IMPORTANT**: Always test new commands incrementally before full audit run.

### Testing Process:
1. **Test single section only** - Run audit with section name parameter:
   ```bash
   ./audit.sh site_name production_url section_name
   ```
2. **Verify HTML output** - Use MCP Playwright to open generated HTML and verify that:
   - All JSON data is properly displayed in the HTML template
   - Tables render correctly with all data
   - No missing or broken sections
3. **Iterate until working** - Fix issues and rerun test until section displays correctly

### Example Workflow:
```bash
# Add new command to commands_registry.sh
"seo_analysis|meta_tags|json|bash \${BASE_DIR}/scripts/analyze_seo.sh"

# Test only this section
./audit.sh droptica.com https://droptica.com seo_analysis

# Open in browser using MCP Playwright
# Verify JSON data shows correctly in HTML
# Fix issues, repeat until working
```


## Time Estimation Standards

**IMPORTANT**: Use Fibonacci-based time estimates for consistency and realistic planning.

### Rules:
1. **NEVER include pricing information** in audit reports (PLN, EUR, USD, etc.)
2. **ONLY provide time estimates** in hours using Fibonacci sequence
3. Use **ranges** for uncertainty, not single values

### Fibonacci Sequence for Estimates:
- Use these values ONLY: **1, 2, 3, 5, 8, 13, 20, 40, 100**
- Never use: 4, 6, 7, 9, 10, 11, 12, 14, 15, 16, etc.

### Examples of Correct Ranges:
- ✅ `1-2h` - Very small task
- ✅ `2-3h` - Small task
- ✅ `3-5h` - Medium-small task
- ✅ `5-8h` - Medium task (half day to full day)
- ✅ `8-13h` - Large task (1-2 days)
- ✅ `13-20h` - Very large task (2-3 days)
- ✅ `20-40h` - Epic task (1 week)
- ✅ `40-100h` - Project-level task (2-4 weeks)

### Examples of WRONG Estimates:
- ❌ `4-8h` - Should be `3-5h` or `5-8h`
- ❌ `16-32h` - Should be `13-20h` or `20-40h`
- ❌ `10h` - Should be range like `8-13h`
- ❌ `15,000-30,000 PLN` - NEVER include pricing

### Why Fibonacci?
- Natural reflection of uncertainty growth
- Prevents false precision (no "14.5h" estimates)
- Aligns with agile planning practices
- Forces realistic scoping of work

### Application:
- Use in summary documents (PODSUMOWANIE.md, EXECUTIVE_SUMMARY.md)
- Use in action items (ACTION_ITEMS.md)
- Use in HTML reports
- Use when discussing effort with stakeholders


## HTML Template Styling Standard

**IMPORTANT**: All HTML files in `template/drupal_audit_template/includes/` must follow the Droptica branding standard.

### Required Elements:

1. **Bootstrap CSS Link:**
   ```html
   <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
   <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.1/font/bootstrap-icons.css">
   ```

2. **CSS Variables (Droptica Branding):**
   ```css
   :root {
     --droptica-primary: #0039FF;
     --droptica-success: #10B981;
     --droptica-warning: #F59E0B;
     --droptica-danger: #DC2626;
   }
   ```

3. **Standard H2 Styling:**
   ```css
   h2 {
     color: var(--droptica-primary);
     border-bottom: 2px solid var(--droptica-primary);
     padding-bottom: 10px;
   }
   ```

4. **Body Styling:**
   ```css
   body {
     font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
     background-color: #f8f9fa;
     padding: 20px;
   }
   ```

5. **Card Styling:**
   ```css
   .card {
     border: none;
     box-shadow: 0 2px 8px rgba(0,0,0,0.1);
   }
   ```

### Allowed Colors:

**Droptica Brand Colors (use ONLY these):**
- `var(--droptica-primary)` - #0039FF (main blue) - for headers, borders, primary elements
- `var(--droptica-success)` - #10B981 (green) - ONLY for success states/badges
- `var(--droptica-warning)` - #F59E0B (orange) - ONLY for warning states/badges
- `var(--droptica-danger)` - #DC2626 (red) - ONLY for error states/badges

**Neutral Colors (allowed for backgrounds/text):**
- `#f8f9fa` - light gray background
- `#ffffff` / `#fff` - white
- `#e0e0e0`, `#ecf0f1`, `#dee2e6` - borders and dividers
- `#333`, `#555`, `#6c757d`, `#7f8c8d`, `#2c3e50` - text colors
- `rgba(0, 57, 255, 0.02)` to `rgba(0, 57, 255, 0.15)` - light blue tints for backgrounds

**What NOT to Use:**
- ❌ Custom colors: #3498db, #8e44ad, #e67e22, #27ae60, #d5f4e6, #229954, etc.
- ❌ Color gradients with custom colors (use solid `var(--droptica-primary)` instead)
- ❌ CSS reset with `* { margin: 0; padding: 0; }`
- ❌ H1 tags (use H2 instead)

### Verification:
- Test HTML files visually using MCP Playwright
- Check all headers use Droptica blue (#0039FF)
- Verify no custom hex colors (except neutral grays)
- Confirm Bootstrap icons work correctly
