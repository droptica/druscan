---
name: drupal-audit
description: Runs a full DRUSCAN audit of a Drupal site and writes the AI analysis into the HTML report (executive summary and action items). Use when the user asks to audit a Drupal site, run DRUSCAN, or generate a Drupal audit report for a site linked in drupal_sites/. Needs the site name and the production URL.
license: MIT
compatibility: Run from the DRUSCAN repository root. Requires bash, jq and DDEV with the audited site running locally. Lighthouse CLI and Pa11y CLI are optional (performance and accessibility sections).
---

# Drupal Audit Tool

## Prerequisites

1. **Required Parameters**: You need both values below. If either is missing, stop and ask the user for it.
   - `[site_name]` - name of the symlink in `./drupal_sites/` (e.g., `mysite.com`)
   - `[production_url]` - production URL starting with `http://` or `https://` (e.g., `https://mysite.com`), used by the performance, accessibility and legal compliance sections
2. **Site Check**: Verify that `./drupal_sites/[site_name]` exists. If not, stop and tell the user to link the site first (see README "Setup").
3. **Template Review**: Familiarize yourself with template structure in:
   - `./template/drupal_audit_template/index.html` - main report structure
   - `./template/drupal_audit_template/includes/*.html` - section templates with placeholder guidance

## Execution Steps

### 1. Run Audit Script

Run from the repository root:

```bash
./audit.sh [site_name] [production_url]
```

**Note for AI/LLM:** The audit script execution may take **5-15 minutes** depending on site complexity (number of modules, content volume, database size). Be patient and wait for the script to complete. Do not assume it has failed if it takes several minutes.

### 2. Capture Report Path
- Extract the generated report path from script output (e.g., `./audits_reports/2025-10-08_05-57-05_droptica.com`)
- Store this path as `[report_path]` for subsequent steps

### 3. Analyze JSON Data Systematically

Review ALL JSON files in `[report_path]/json/` and identify:

**Critical Issues:**
- Security vulnerabilities (outdated modules, hacked checks, permissions)
- Performance bottlenecks (large datasets, inefficient views, cron issues)
- Data integrity problems (broken references, missing configs)
- Compliance gaps (accessibility, GDPR)

**Technical Debt:**
- Deprecated code patterns
- Unused modules or configurations
- Complex custom code that could be simplified
- Missing documentation or tests

**Positive Findings:**
- Well-structured custom modules
- Good use of contrib modules
- Proper multilingual setup
- Clean content architecture

**Metrics & Statistics:**
- Module counts (core/contrib/custom)
- Content volume (nodes, media, taxonomies)
- User roles and permissions complexity
- Update availability

### 4. Generate Executive Summary (Analysis)

Fill `[report_path]/html/includes/executive_summary.html` with:

**Structure (replace ALL placeholder boxes):**
1. **Overview** (2-3 paragraphs)
   - Overall health rating (Excellent/Good/Fair/Needs Improvement)
   - High-level assessment of architecture, security, performance
   - Site's readiness for future growth/changes

2. **Critical Findings** (3-5 bullet points)
   - Most urgent issues requiring immediate attention
   - Impact: What breaks or risks if not addressed
   - Use specific data from JSON files

3. **Positive Highlights** (2-4 bullet points)
   - Well-implemented features worth acknowledging
   - Strengths to maintain and build upon

4. **Key Metrics** (5-8 metrics in table or list)
   - Drupal version and PHP version
   - Total modules: X (Y custom, Z contrib)
   - Content types: X types, Y total nodes
   - Security updates available: X critical, Y recommended
   - Other relevant statistics from JSON data

5. **Top Priorities** (5-10 items)
   - Actionable items ranked by urgency + impact
   - Format: Brief description + Why it matters
   - Link to detailed sections

**Tone:** Business-friendly, clear, avoid deep technical jargon

### 5. Generate Action Items (Task List)

⚠️ **CRITICAL: AVOID REPETITION** - Do NOT repeat content from Executive Summary!

Fill `[report_path]/html/includes/action_items.html` with **ONE SIMPLE TABLE**:

**Structure (ultra-simple - 3 elements only):**

**1. Summary Stats Cards** (4 cards)
- Count of Critical items
- Count of High priority items
- Count of Medium priority items
- Total estimated effort (hours)

**2. Action Items Table** (10-20 rows)
- **Format:** Single expandable table with ALL recommendations
- **Columns:** # | Action | Priority | Effort | When | Details
- **Sort:** Critical → High → Medium → Low
- **Main row:** Short action title (max 60 chars)
- **Expanded row:** What, Why, How (detailed steps)
- **Timeline (When column):**
  - Week 1 = Critical (security, broken functionality)
  - Week 2-3 = High (updates, core)
  - Week 4+ = Medium (improvements)
  - Month 2+ = Low (nice-to-have)

**3. Next Audit Date** (1 sentence)
- Calculate 6 months from audit date

**That's it. Nothing more.**

---

**❌ DO NOT CREATE SEPARATE SECTIONS FOR:**
- ❌ "Implementation Timeline" (it's in the "When" column)
- ❌ "Quick Action Checklist" (critical items are at top of table)
- ❌ "Next Steps" (they're in the action items)
- ❌ "Overall Assessment" (it's in Executive Summary)
- ❌ "Notable Achievements" (it's in Executive Summary)
- ❌ "Areas Requiring Attention" (it's in Executive Summary)

**✅ CONTENT RULES:**
- ONE table with ALL actions - no separate lists/sections
- Keep TOTAL page length under 250 lines HTML
- Target reading time: 3-5 minutes maximum
- Every action = one row in table
- All details in expandable section (Bootstrap collapse)
- Use color coding: Critical=red, High=orange, Medium=blue, Low=gray

**Tone:** Ultra-concise, action-focused

### 6. Quality Checks

Before completing:

**Content Quality:**
- ✓ All placeholder boxes replaced with actual content
- ✓ Specific data from JSON files referenced (not generic statements)
- ✓ Recommendations are actionable (not vague like "improve performance")
- ✓ Priorities justified with clear rationale
- ✓ Professional tone maintained throughout
- ✓ Balanced perspective (acknowledge both positives and issues)

**No Repetition (CRITICAL):**
- ✓ Action Items page does NOT repeat Executive Summary content
- ✓ No "Overall Assessment" or "Notable Achievements" in Action Items
- ✓ No "Areas Requiring Attention" duplicating Critical Findings
- ✓ No separate Timeline/Checklist/Next Steps sections (just ONE table)
- ✓ No descriptive text above/below the table - just the list

**Conciseness:**
- ✓ Action Items page under 200 lines HTML (just stats + one table + next audit)
- ✓ Executive Summary page under 400 lines HTML
- ✓ ONE table with ALL action items (no separate sections)
- ✓ Expandable rows for details (Bootstrap collapse)
- ✓ Reading time: 3-5 minutes for Action Items, 5-7 minutes for Executive Summary
- ✓ Action Items has NO descriptive text - only the table

**Technical:**
- ✓ HTML structure intact (no broken tags)
- ✓ Bootstrap collapse/accordion working correctly
- ✓ All badges, icons, and styling applied consistently

## Definition of Done

Two separate files with **zero repetition**:

**File 1: Executive Summary (Analysis)**
- ✅ File: `[report_path]/html/includes/executive_summary.html`
- ✅ Purpose: Descriptive analysis of current state
- ✅ Contains: Overview, Critical Findings, Positive Highlights, Key Metrics, Top Priorities
- ✅ Under 400 lines HTML
- ✅ Reading time: 5-7 minutes
- ✅ Tone: Business-friendly, analytical

**File 2: Action Items (Task List)**
- ✅ File: `[report_path]/html/includes/action_items.html`
- ✅ Purpose: Concrete task list with priorities
- ✅ Contains ONLY: Summary stats (4 cards), ONE action table (expandable), Next audit date
- ✅ Under 200 lines HTML
- ✅ Reading time: 3-5 minutes
- ✅ Tone: Direct, action-focused
- ✅ **Does NOT repeat** Executive Summary content
- ✅ **NO descriptive text** above or below the table

**Both Files:**
- ✅ All content directly derived from `[report_path]/json/*` analysis
- ✅ Action items prioritized with specific effort estimates (hours)
- ✅ Technical accuracy verified against JSON data
- ✅ Bootstrap collapse used for expandable details
- ✅ **100% different content** - no overlap between files

## Verification (Optional)

If a browser tool is available (e.g., MCP Playwright):
- Open `[report_path]/html/index.html` in browser
- Navigate through all sections to verify:
  - Executive Summary renders correctly
  - Recommendations section displays properly
  - No placeholder content remains visible
  - Professional appearance maintained
