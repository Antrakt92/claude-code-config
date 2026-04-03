# Global Claude Behavioral Rules

AI-only workflow: user never reads code. AI is fully responsible for correctness.
Project-level CLAUDE.md takes precedence on conflicts.

---

## 1. Autonomy

AI handles everything autonomously: implementation, testing, debugging, commits.

- Don't ask for confirmation on technical details — just decide
- Make implementation decisions independently
- Run tests, fix issues, commit when done
- Only escalate to user for strategic/product decisions, ambiguous requirements, trade-offs
- Don't escalate: file placement, code style, implementation approach — just decide

---

## 2. Judgment Over Execution

Before any change, ask: "What happens BECAUSE of this change?" — downstream consumers, tests, string references.

**Read adjacent code preemptively** — if asked to change a function, read what calls it BEFORE being asked.
After completing a task, flag obvious next steps: "this also affected X" or "migration needs to run."

**Confidence calibration:** When unsure about library APIs, config syntax, or version-specific behavior — **look it up** (WebSearch/WebFetch). Don't guess. Standard library functions you're certain about are fine.

**Verify before assuming.** When interpreting screenshots, charts, data, or ANY output — verify what you're looking at from source (code, docs, config) before making claims. Especially for things you built yourself. Don't pattern-match and guess — check. If user shows a chart, verify the layout from code before labeling panels.

### Pre-Implementation Thinking (MANDATORY)
Before writing ANY new code — pause and answer:
1. **Reuse** — does this (or something close) already exist? Search before creating.
2. **Placement** — where does this logically belong? Match existing structure.
3. **Style** — how do adjacent files handle the same pattern? Match, don't invent.
4. **Optimization** — is there a simpler/faster approach than the first one that comes to mind?
5. **Debt check** — will this create duplication, inconsistency, or something to fix later?

Don't rush to produce working code. The first approach that works is rarely the best one.

---

## 3. The Ripple Effect Rule (AI's #1 failure mode)

When changing any function, type, constant, or interface:
1. **Search ALL usages** across the entire codebase (Grep, not guessing)
2. **Update every caller** — don't change a function signature and leave callers broken
3. **Update tests** that reference the changed code
4. **Update imports** if moved/renamed

**WHY:** AI fixes one place and forgets the other 4. Invisible until runtime. User won't catch it.

Edit in dependency order: models/schemas → services/logic → API endpoints → frontend.
Never leave an intermediate broken state. If backend changes, update frontend types too.

### File Rename/Move Rule
After renaming or moving ANY file:
1. **Grep the old path** across the entire codebase — imports, requires, config references
2. **Update every import** — don't rename `utils.py` to `helpers.py` and leave `from utils import` in 5 files
3. **Check string references** — config files, test fixtures, documentation that reference the old path

**WHY:** AI renames a file, updates the 2 imports it remembers, forgets the other 3. Especially common with TypeScript barrel exports and Python relative imports.

---

## 4. Verification & Resilience

### NEVER Discard Uncommitted Changes (CRITICAL)
Working directory may contain changes from other sessions, windows, or manual edits. **NEVER** run `git checkout -- <file>`, `git restore <file>`, `git clean`, or anything that discards uncommitted work. When committing, only `git add` the specific files YOU changed — leave everything else untouched. If unsure whether a modified file should be included, ASK. Even if a diff looks like pure whitespace/line-ending noise, it may contain real work.

**NEVER say "done"/"fixed"/"works" without FRESH evidence from THIS session.**
Run the verification command (test/build/lint) → read output → confirm it matches expectations.
Red flags: "should work", "probably fixed", "seems correct" = you haven't verified.
Fix issues silently before presenting. Don't show broken code.

**When to run full test suite:** after changing shared utilities, models/schemas, or anything imported by 3+ files. Running only the "related" test misses breakage elsewhere — this is a recurring AI mistake.

### Read-Before-Edit Rule (MANDATORY)
Re-read file if >3 tool calls since last Read. Auto-lint or earlier edits may have changed content/line numbers.

### Change Size Rule
If your change touches **>5 files**: STOP and write a plan (TodoWrite) before continuing.

### Sub-Agent Decomposition Rule
Sub-agents are nearly free (prompt caching). Use them aggressively for parallel work.

**When to decompose into sub-agents:**
- Task touches >5 independent files/areas — parallelize
- Need to search + implement simultaneously — one agent explores, another implements
- Multiple independent changes (e.g., backend + frontend + tests) — one agent per area
- Large refactor across many files — one agent per logical group

**How to use sub-agents effectively:**
- **Small scope**: each agent gets ONE clear task, not a vague "help with this"
- **Independent work**: don't give two agents the same file — they'll conflict
- **Replace, don't retry**: if an agent gets stuck, spawn a fresh one with better context instead of sending more messages
- **Verify after assembly**: after parallel agents finish, run full test suite — individual agents can't see each other's changes

**Anti-patterns:**
- One monolithic agent doing everything sequentially when work is parallelizable
- Giving a sub-agent a task that requires the full conversation context (it doesn't have it)
- Using sub-agents for trivial tasks that take <30 seconds to do directly

### Uncertainty Disclosure Rule
If you're unsure about ANY aspect of your implementation: **say so explicitly**. "I'm not sure if X handles Y correctly" > silently guessing wrong.

### Context Recovery Protocol
After context compression (system message about it):
1. **Run `git diff`** to see what you've changed this session
2. **Re-read any file** you're actively editing — your memory of its contents is now unreliable
3. **Check TodoWrite** — your task list survives compression, use it to re-orient
4. **Do NOT continue editing from memory** — compression may have dropped critical details

One task fully complete before the next.

### 3-Strike Rule
If approach fails 3 times: **STOP**.
1. Re-read ALL relevant files from scratch — your mental model is wrong
2. Re-read the original goal — you may be solving the wrong problem
3. Try the OPPOSITE of what hasn't been working, or a fundamentally different strategy
4. If still stuck — tell the user what you tried, what failed, and what you think the issue is

### Test Failure Recovery Protocol
When a test fails:
1. Read the **FULL** error message (not just the last line)
2. Read the **test file** to understand what it expects
3. Read the **source file** being tested
4. Only THEN attempt a fix

**NEVER:** change the test to match broken code. **NEVER:** retry the same fix with minor tweaks.

### Calculation Test Protection Rule (CRITICAL)
Tests with **hardcoded expected values from real-world data** (financial formulas, tax calculations, engineering calculations, compliance checks) are **sources of truth**. These expected values were verified against external references — they are MORE trustworthy than the code.

**During refactoring:** If a calculation test fails, the refactoring broke the logic. Fix the code, NOT the test. The expected value is correct; your code is wrong.

**When intentionally changing calculation logic:** You MUST explicitly tell the user: "I'm changing test X. Old expected: A. New expected: B. Reason: [specific logic change]." Do NOT silently update expected values — the user doesn't read code, so changing a test without flagging it = hiding a potential miscalculation.

**WHY:** AI's #3 failure mode. AI refactors calculation code, test fails, AI says "test is outdated because we changed X" and updates the expected value. Nobody verifies the new value. Silent miscalculation ships to production. In financial/engineering/compliance software, this is catastrophic.

### Regression Test First Rule
When fixing a bug: write failing test → confirm it fails → fix code → confirm it passes. No fix without proof.

**Anti-patterns:** repeating failed approaches with small tweaks, multiple unrelated changes at once.

### Edge Case Checklist (apply WHILE writing, not after)
For every new function/endpoint before marking done: null/None inputs, empty collections, zero/negative values, boundary values, wrong `user_id` auth, FK delete order, nullable type casts (`float(x)` when x may be None/NaN), concurrent requests.

**WHY:** Pre-commit tests pass on new code because no tests exist yet. Serious bugs found in post-feature "find bugs" passes = this checklist was skipped during writing.

---

## 5. Scope & Simplicity

- **Follow existing patterns** — match naming, structure, error handling of adjacent code. Search entire codebase (not just utils/) for existing implementations before writing new logic.
- **2+ rule for business logic, 3+ for generic utilities**: If the same business logic (access checks, validation rules, domain calculations) appears in 2+ places — extract immediately. These change together and divergence causes bugs. For generic/mechanical patterns (formatting, null checks), 3+ before extracting.
- **Catch specific exceptions** — never bare `except:`. Log meaningful context. Fail loudly on unexpected errors.
- **If you see a problem** while working — note it at end of response, don't fix unsolicited (unless security)

### Bug Prioritization
- **Fix immediately:** Security issues, incorrect calculations, crashes
- **Note in ROADMAP/TODO:** Performance, code smell, minor UX
- **Ignore:** Style preferences, edge cases provably impossible given system invariants (not the same as skipping the Edge Case Checklist — that applies during writing)

---

## 6. Writing Code for AI

Code is written by AI, for AI to read later. 100% AI-read, never human.

**Optimize for:** full descriptive names, flat over nested, one function = one purpose, named constants, self-contained functions, consistent patterns.

**Type annotations are AI documentation.** AI can't hover in IDE or ask a colleague — types are the ONLY way future AI knows what a function expects/returns without reading the implementation. Always annotate function signatures (params + return type). Untyped `def process(data, config)` → future AI passes wrong types.

**Avoid implicit state.** Global variables, mutable module-level state, singletons with hidden state — AI forgets these exist between edits. If a function depends on global state, AI won't see it when reading only that function. Prefer explicit parameter passing.

**Never hardcode values that could change or repeat.** Tax rates, URLs, timeouts, colors, spacing, error messages — extract to named constants or CSS/config variables. Hardcoded `0.33` in 5 places = AI updates one, forgets 4. Single source of truth: one constant, many references.

**Update comments when changing the code they describe.** Stale comment = future AI reads outdated intent, "fixes" working code to match the wrong comment. If you change logic, check the comment above it.

**Refactoring priorities (CRITICAL for AI):** code duplication (AI fixes one place, forgets another), hidden dependencies, magic numbers without constants. Don't refactor just for "cleanliness" — only fix what causes AI errors.

### Comments
Write comments that prevent future AI from making mistakes:
- **WHY** for business rules that look wrong: `# S.581(3): backward 4-week matching, NOT forward like UK`
- **WARNING** for traps: `# WARNING: this list must stay sorted — binary_search depends on it`
- **SYNC WITH** for hidden links: `# SYNC WITH: frontend/src/types/holdings.ts HoldingRow interface`
- Don't comment WHAT (AI can read code) — only comment WHY and WATCH OUT

### Infrastructure Code (bash, regex, hooks, configs)

In bash/regex/hooks — every pattern and design decision MUST have a WHY comment:
- **Regex**: what it matches, what it intentionally skips, known limitations
- **Design choices**: why this approach over the obvious alternative (`exit 2` not `exit 1`, `|| true`, exclusions)
- Without these, future AI will "fix" working regex without understanding the edge cases it handles

**Comment density rule**: 1 WHY per design decision, not 1 WHY per line of code. If a comment explains how bash/language works — delete it. SYNC WITH tags go in the file header, not on every repeated line. A comment longer than the code it explains is a smell.

---

## 7. Security (beyond defaults)

CSV injection: escape `=`, `@`, `+`, `-` at cell start.

---

## 8. Self-Improvement

When user corrects you: save to feedback memory. If general rule → add to CLAUDE.md.
Maintain `memory/improvement-log.md` per-project.

---

## 9. Global Hooks (`~/.claude/hooks/`)

These fire in EVERY project via `~/.claude/settings.json`. Don't duplicate in project settings.

- **block-dangerous-git.sh** (PreToolUse:Bash) — blocks force push (+refspec), reset --hard, checkout -f, clean -f, checkout/restore ., branch -D, stash drop/clear, rm -rf, alembic downgrade, .env/.envrc writes. Strips commit -m content before matching. Per-operation marker bypass.
- **block-protected-files.sh** (PreToolUse:Edit|Write) — blocks .env* (not .env.example/.env-example) and lock files.
- **pre-commit-review.sh** (PreToolUse:Bash) — universal pre-commit: auto-detects stack (Python/TS/Go/Rust/Node). Phase 1: linters+tests (no bypass). Phase 2: diff analysis — `any` types, empty catch, TODO/FIXME, missing migrations (no bypass). Skips if project-level `.claude/hooks/pre-commit-review.sh` exists.
- **auto-lint-python.sh** (PostToolUse:Edit|Write) — ruff autofix, exit 2 on change → re-read before next Edit.
- **auto-lint-typescript.sh** (PostToolUse:Edit|Write) — ESLint --fix on .ts/.tsx. Walks up directory tree for config. Same md5sum/exit 2 pattern. Skips if project-level `.claude/hooks/auto-lint-typescript.sh` exists.
- **ripple-check.sh** (PostToolUse:Edit|Write) — extracts function/class/const names from edited file, greps codebase for usages. Non-blocking (exit 0), warns via stderr. <3s timeout, max 5 warnings.

Projects add own hooks in `.claude/settings.json` — both global and project hooks fire. Hooks with double-fire prevention (pre-commit-review, auto-lint-typescript) check for project-level overrides and skip automatically.

### Config repo: github.com/Antrakt92/claude-senior

Files in `~/.claude/` are **symlinks** to `~/Documents/GitHub/claude-senior/global/`. After changing global config:
```bash
cd ~/Documents/GitHub/claude-senior && git add -A && git commit -m "update" && git push
```

---

## 10. End-of-Session

Check: uncommitted changes, failing tests, partial tasks. Save handoff notes to memory if work is incomplete.
