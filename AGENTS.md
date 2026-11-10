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


## Bash Compatibility
**IMPORTANT**: All scripts must work with **Bash 3.2** (default `/bin/bash` on macOS).
- Do not use associative arrays (`declare -A`), `mapfile`/`readarray`, `${var,,}` or `${var^^}`
- Use plain indexed arrays with `key|value` entries and `IFS='|' read -r ...` instead


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


## Audit Speed: Cache and Reuse

**IMPORTANT**: Do not run the same slow analysis twice in one audit.

1. **ddev command cache** (`scripts/ddev_cached.sh`) - `audit.sh` puts a `ddev` wrapper at the front of `PATH`. Repeated read-only calls with identical arguments (`drush pm:list`, `drush config:status`, `composer outdated`, `composer show`) run only once. Commands that change module state (`pm:enable`, `pm:uninstall`, `cr`, ...) clear the cache.
   - Just call `ddev drush pm:list --format=json` normally in scripts - no special code needed
   - Use the same arguments everywhere (e.g., always `--format=json`, then filter with `jq`) so calls share one cache entry
   - To add another cached command, extend the `case` list in `scripts/ddev_cached.sh` (read-only commands only)
   - Disable for debugging: `DRUSCAN_NO_CACHE=1 ./audit.sh ...`

2. **Reuse of a full analysis** (`scripts/reuse_section_key.sh`) - when a section stores a full analysis and also its parts as separate keys, copy the parts from the full analysis instead of running the script again. The full analysis must be listed first in the section.
   ```bash
   "seo_analysis|full_analysis|json|bash \${BASE_DIR}/scripts/analyze_seo.sh all"
   "seo_analysis|sitemap|json|bash \${BASE_DIR}/scripts/reuse_section_key.sh full_analysis sitemap bash \${BASE_DIR}/scripts/analyze_seo.sh sitemap"
   ```
   If the full analysis failed, the fallback command (everything after the two key names) runs.

3. **One Drupal call per script** (`scripts/lib/drush_php.sh` + `scripts/php/*.php`) - every `ddev drush ...` call starts Drupal again (about 2 seconds). A script that needs many values from Drupal must collect them in ONE PHP file and run it once:
   ```bash
   SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
   source "${SCRIPT_DIR}/lib/drush_php.sh"
   drush_php "${SCRIPT_DIR}/php/my_analysis.php" 2>/dev/null                 # no arguments
   drush_php "${SCRIPT_DIR}/php/my_analysis.php" '{"key": "value"}' 2>/dev/null  # JSON available in PHP as $druscan_args
   ```
   - The PHP file starts with `<?php`, uses the bootstrapped Drupal (`\Drupal::...`) and ends with `echo json_encode($result);`
   - Never call `ddev drush` inside a loop (per bundle, per role, per table...). Use a loop in PHP and `GROUP BY` in SQL instead
   - Use `{table_name}` in SQL so table prefixes work
   - Examples: `entity_structure.php`, `user_roles.php`, `homepage.php`, `performance.php`

`${SECTION_JSON}` (exported by `audit.sh`) is the path to the JSON collected so far for the current section.


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

### Issue: Loop Ends After the First Item
**Cause:** `ddev` reads standard input. Inside `while read ... done <<< "$LIST"` it swallows the rest of the list, so the loop runs only once (no error is shown).

**Solution:** Do not call `ddev` in such loops (see "One Drupal call per script"). If you must, add `</dev/null`:
```bash
# ❌ WRONG - only the first item is processed
while IFS= read -r item; do
    ddev drush config:get "$item" --format=json
done <<< "$ITEMS"

# ✅ CORRECT
while IFS= read -r item; do
    ddev drush config:get "$item" --format=json </dev/null
done <<< "$ITEMS"
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

**IMPORTANT**: The report look is defined in ONE file: `template/drupal_audit_template/assets/report.css` (design tokens + shared styles, in the style of droptica.ai).

### How it is wired

- `index.html` (report shell: header, sidebar, iframes) loads `assets/report.css`
- Every file in `includes/` loads Bootstrap 5.3 + Bootstrap Icons from CDN and then `../assets/report.css`, and has `<body class="ds-page">`
- `report.css` maps Bootstrap variables and components (cards, tables, badges, alerts, buttons) to the tokens, so standard Bootstrap classes already look right

```html
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.1/font/bootstrap-icons.css">
<link rel="stylesheet" href="../assets/report.css">
</head>
<body class="ds-page">
  <div class="container-fluid">
    <h2 class="mb-4">Section Title</h2>
    <p>Short intro (styled as lead text).</p>
```

### Rules

1. **No `<style>` blocks and no colours or fonts in `style=""`** in `index.html` or `includes/*.html`. Layout-only inline styles (e.g., column `width`) are OK.
2. **Use tokens** (`var(--ds-*)`). A new colour, size, radius or shadow becomes a token in `report.css` first.
3. **A new component gets its CSS in `report.css`** (section "Section-specific components"), not in the include file.
4. **Use Bootstrap classes for status**: `bg-success` / `text-success` (OK), `bg-warning` (warning), `bg-danger` (critical), `bg-primary` / `bg-info` (neutral highlight), `bg-secondary` (inactive). `report.css` turns them into the report palette.
5. **Font**: DM Sans (free, loaded from Google Fonts in `report.css`). Do not add other fonts.
6. **No H1 inside sections** - the page title is `<h2>`, sub-sections are `<h3>`/`<h4>`.

### Main tokens

| Token | Value | Usage |
|-------|-------|-------|
| `--ds-navy` | `#030a3d` | Headings, header bar, text |
| `--ds-blue` | `#0039ff` | Links, accents, active state |
| `--ds-teal` | `#00e2d1` | Accents on navy |
| `--ds-surface` / `--ds-surface-2` | `#f7f8fb` / `#eef1f8` | Page background / table heads, panels |
| `--ds-ok`, `--ds-warn`, `--ds-danger` | `#0b9d86`, `#f59e0b`, `#dc2626` | Status colours (each has `-ink` for text and `-tint` for backgrounds) |
| `--ds-radius-sm/md/lg` | `6px / 10px / 16px` | Corners |

### Ready-made components (see `report.css`)

- Stat tiles: `.stats-grid` > `.stat-card` (`h3` label + `.value`), or `.score-card` > `.score-item.pass|warning|fail`
- Chips: `.badge.bg-*` (pill with light background)
- Panels: `.alert.alert-*`, `.info-box`, `.section-intro`, `.success-box`, `.warning-box`, `.error-box`
- Lists: `.info-row` (`.info-label` + `.info-value`), `.issue-card`, `.check-card`, `.recommendation-item`
- Diagrams: `<div class="diagram-section"><div class="mermaid" id="my-diagram"></div></div>`, then put the Mermaid text in with `textContent` and call `DruscanDiagram.enhance(element)` (see below)

### Mermaid diagrams

All diagrams are drawn by the shared viewer `template/drupal_audit_template/assets/diagram.js` (do not write zoom or pan code in include files):

```html
<script src="https://cdnjs.cloudflare.com/ajax/libs/mermaid/10.6.1/mermaid.min.js"></script>
<script src="../assets/diagram.js"></script>
```
```js
const host = document.getElementById('my-diagram');
host.textContent = data.mermaid_diagram;   // Mermaid definition as text
DruscanDiagram.enhance(host);              // or DruscanDiagram.enhanceAll()
```

- Tree diagrams are drawn left-to-right (`graph TD`/`TB` is changed to `graph LR`), so many items make the diagram taller instead of very wide. Add `data-direction="keep"` to keep the original direction
- The viewer shows the diagram at readable size in a tall scrollable area, with zoom in/out, Fit, 100% and Taller buttons, drag to move and Ctrl/Cmd + scroll to zoom
- Colours of the Mermaid theme are set in `diagram.js`; node colours (`style X fill:...`) come from the script or template that builds the definition

### Testing template changes

No need to run the whole audit. Rebuild the HTML of an existing report from its JSON:

```bash
bash scripts/rebuild_report_html.sh audits_reports/{timestamp}_{site_name}
# -> audits_reports/{timestamp}_{site_name}/html_preview/index.html
```

### Verification:
- Open the preview in a browser (e.g., MCP Playwright) and check the changed sections
- Check the shell at desktop width and below 768px (sidebar becomes a slide-in menu)
- Confirm no `<style>` blocks were added to include files: `grep -c "<style" template/drupal_audit_template/includes/*.html`
