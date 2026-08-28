```
 ____  ____  _   _ ____   ____    _    _   _
|  _ \|  _ \| | | / ___| / ___|  / \  | \ | |
| | | | |_) | | | \___ \| |     / _ \ |  \| |
| |_| |  _ <| |_| |___) | |___ / ___ \| |\  |
|____/|_| \_\\___/|____/ \____/_/   \_\_| \_|

```

# DRUSCAN - Drupal Site Audit Tool

> Automated technical audit of Drupal sites. Collects structured data about modules, security, content structure, performance, and configuration.

---

## What is this for?

### Primary Use Case: Agency Transitions Without Security Risks

When transitioning a Drupal site to a new agency or requesting quotes from multiple vendors, sharing full database dumps and complete codebase access creates significant security and confidentiality concerns:

- **The Problem:** You need 3-5 agencies to provide accurate estimates, but don't want to expose sensitive data, proprietary code, API keys, or customer information to multiple external parties.

- **The Solution:** DRUSCAN generates a comprehensive technical audit report that includes everything needed for accurate estimation (architecture, modules, complexity, technical debt) without exposing actual database content, custom code logic, or sensitive credentials.

**What vendors get:**
- Complete module inventory and dependencies
- Content architecture and entity relationships
- Performance and security metrics
- Code quality statistics (lines, complexity, test coverage)
- Configuration overview and technical requirements

**What stays protected:**
- Actual database content and user data
- Proprietary custom code and business logic
- API keys and integration credentials
- Server access and deployment details
- Private files and media assets

### Other Use Cases

- **Security assessment** - Check for vulnerabilities and outdated modules
- **Technical debt estimation** - Assess maintenance costs and upgrade complexity
- **Performance analysis** - Identify bottlenecks and optimization opportunities
- **Quality verification** - Check if current agency follows best practices
- **Documentation** - Generate comprehensive technical documentation of the site

## Setup

Before running audit, link your Drupal site:

1. **Ensure site runs under DDEV** - Your Drupal site must be running locally with DDEV

2. **Create symlink to your site:**
   ```bash
   cd drupal_sites
   ln -s /path/to/your/ddev/drupal/site site-name
   ```

3. **Verify structure:**
   ```
   drupal_sites/
   └── site-name/        # symlink to your DDEV project
       ├── web/          # or docroot/
       ├── composer.json
       └── ...
   ```

That's it! Now you can run the audit.

## Usage Options

### Option 1: Full AI-Powered Workflow (Recommended)

Use with [Cursor IDE](https://cursor.com) for complete audit analysis:

**What you get:**
- ✅ Automated data collection from your Drupal site
- ✅ AI-generated executive summaries and recommendations
- ✅ Technical findings analysis and interpretation
- ✅ Actionable improvement suggestions

**Usage:**
- Open project in Cursor IDE
- In chat, type: `/drupal-audit [site-name] [production-url]`
- Wait 10-15 minutes for complete analysis

### Option 2: Standalone Script (Manual Analysis)

Run audit scripts directly from terminal:

```bash
# Full audit (all sections)
./audit.sh site-name https://production-site.com

# Single section only
./audit.sh site-name https://production-site.com section-name

# Examples
./audit.sh mysite.com https://mysite.com
./audit.sh mysite.com https://mysite.com code_quality_tools
```

**Parameters:**
- `site-name` (required) - Name of the symlink in `drupal_sites/` directory
- `production-url` (required) - Production URL for testing (used by performance and accessibility sections)
- `section-name` (optional) - Audit only specific section (e.g., `drupal_modules`, `code_quality_tools`)

**What you get:**
- ✅ Structured JSON data with all technical information
- ✅ HTML report template
- ❌ No AI-powered analysis or summaries (manual review required)

**Output location:**
```
audits_reports/{timestamp}_{site-name}/
├── json/       # Structured audit data
└── html/       # Report template
```

## What Gets Audited

System checks 20+ areas including:
- Modules (core/contrib/custom) with code analysis
- Security updates and modified files
- Content types, taxonomies, media, users
- Views, menus, workflows, permissions
- Cron jobs, external integrations, APIs
- Database errors, performance issues
- Multilingual setup, tests coverage

See `commands_registry.sh` for full list.


## Requirements

**Required:**
- **DDEV** - Site must run under DDEV locally
- **jq** - JSON processor (`brew install jq` on macOS)
- **Drupal 8/9/10/11** - Modern Drupal versions only. Drupal 12 is not verified yet; it is scheduled for release in December 2026.

**Optional (for full analysis):**
- **Lighthouse CLI** - Performance analysis (`npm install -g lighthouse`)
- **Pa11y CLI** - Accessibility analysis (`npm install -g pa11y`)

---

## Project Structure

For developers who want to extend or modify the audit:

- **`audit.sh`** - Main orchestration script
- **`commands_registry.sh`** - Registry of all audit commands (easy to extend)
- **`./scripts/`** - Helper scripts for complex analysis
- **`./template/`** - HTML report template
- **Output:** `audits_reports/{timestamp}_{site-name}/` - JSON data + HTML

---

## Contributing

Found a bug or have an idea for improvement?

- **Report issues** - Open an issue to report bugs or suggest features
- **Submit pull requests** - Fork the repo and submit a PR with your improvements
- **Share feedback** - Let us know how you're using DRUSCAN

We welcome contributions of all kinds - bug fixes, new audit commands, documentation improvements, or feature suggestions.

---

## License

MIT. See [LICENSE](LICENSE). You can use it in commercial projects, fork it and change it.

---

## About

Built by [Droptica](https://www.droptica.com) - Drupal development and consulting agency.
