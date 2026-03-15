# Hook System Audit Prompt

Copy-paste this into a new Claude Code session to run a full audit of the hook system.

```
Полный аудит системы хуков. Цель: найти баги, edge cases, inconsistencies.

## Что сделать

### 1. Прочитай ВСЕ файлы
Глобальные хуки (симлинки на ~/Documents/GitHub/claude-code-config/global/):
- `C:/Users/Dima/.claude/hooks/block-dangerous-git.sh`
- `C:/Users/Dima/.claude/hooks/block-protected-files.sh`
- `C:/Users/Dima/.claude/hooks/auto-lint-python.sh`

Проектные хуки investments-calculator:
- `.claude/hooks/pre-commit-review.sh`
- `.claude/hooks/auto-lint-typescript.sh`
- `.claude/hooks/check-css-variables.sh`
- `.claude/hooks/test-hooks.sh`

Проектные хуки Timesheet:
- `C:/Users/Dima/Documents/GitHub/Timesheet/.claude/hooks/pre-commit-review.sh`
- `C:/Users/Dima/Documents/GitHub/Timesheet/.claude/hooks/auto-lint-typescript.sh`

Проектные хуки ClipboardHistory:
- `C:/Users/Dima/Documents/GitHub/ClipboardHistory/.claude/hooks/pre-commit-review.sh`

settings.json (оба):
- `C:/Users/Dima/.claude/settings.json`
- `.claude/settings.json`

### 2. Запусти тесты
```bash
cd /c/Users/Dima/Documents/GitHub/investments-calculator && bash .claude/hooks/test-hooks.sh
```

### 3. Regression check
- Прочитай секцию "Audit Log" внизу этого файла — убедись что баги из прошлых аудитов не вернулись.
- Для КАЖДОГО regex в хуках — есть ли тест в test-hooks.sh? Если нет — добавь.

### 4. Consistency check
- Глобальные хуки (symlink targets в `claude-code-config/global/hooks/`) ИДЕНТИЧНЫ проектным копиям в investments-calculator `.claude/hooks/` для block-dangerous-git, block-protected-files, auto-lint-python? `diff` каждую пару.
- JSON extraction pattern одинаковый во ВСЕХ hook файлах?
- settings.json: глобальные хуки НЕ дублируются в проектных settings? (double-fire)
- Timesheet и ClipboardHistory хуки используют тот же JSON extraction?
- Cross-project feature drift: Timesheet/ClipboardHistory pre-commit-review.sh будут отличаться от investments-calculator (у inv-calc есть ruff+pytest+tsc, у Timesheet только tsc, у ClipboardHistory только ruff). Это by design — отметь различия но не выравнивай.

### 5. Для КАЖДОГО хука
- **3 false positives**: легитимные команды которые ложно блокируются — промоделируй regex
- **3 false negatives**: опасные команды которые проходят — промоделируй regex
- **Edge cases**: кавычки в JSON, chained commands (&&, ;, |), Windows paths

### 6. WHY-комментарии
- Каждый regex имеет WHY?
- Нет WHAT-комментариев (объясняющих как работает bash)?
- Не раздуто? (1 WHY на decision, не 1 на строку)

### 7. Пробелы
- Что в CLAUDE.md декларативное но не enforced хуками? Стоит ли enforce?

## Формат ответа

```
## ТЕСТЫ
## REGRESSION (баги из прошлых аудитов — вернулись?)
## CONSISTENCY
## БАГИ [файл:строка → проблема → фикс]
## FALSE POSITIVES / NEGATIVES [таблица]
## КОММЕНТАРИИ
## ПРОБЕЛЫ И ROI [таблица]
## КОНКРЕТНЫЕ ПРАВКИ [файл → было → стало]
```

## Правила
- Будь критичен — ищи баги, не хвали
- Конкретные правки с кодом, не "можно улучшить"
- Применяй ВСЕ фиксы сам, не спрашивай
- WHY к новому коду: 1 WHY на decision
- Запусти тесты после правок
- Обнови CLAUDE.md Hook Behavior секцию если поведение хуков изменилось
- НЕ добавляй новые хуки без явного запроса
- ВАЖНО: файлы в ~/.claude/hooks/ это СИМЛИНКИ на claude-code-config/global/hooks/. Правь оригиналы в claude-code-config/global/hooks/, не симлинки. Проектные копии в investments-calculator/.claude/hooks/ тоже обнови (должны быть идентичны глобальным для трёх общих хуков).
- После всех правок: `cd ~/Documents/GitHub/claude-code-config && git add -A && git commit -m "audit fixes" && git push`
- **Обнови Audit Log** внизу этого файла: дата, найденные баги, что исправлено.
```

---

## Audit Log

### 2026-03-15 — Audit #1
**Found & fixed:**
1. `.env` pattern `[a-z]+` missed uppercase variants (`.env.PRODUCTION`, `.env.LOCAL`) → fixed to `[a-zA-Z0-9]+`
2. `git checkout/restore .` pattern `(-- )?\.` missed refs before dot (`git checkout HEAD .`, `git restore --source=HEAD~1 .`) → broadened to `\b.*\s\.`
3. `block-protected-files.sh` stale comment referencing old regex → updated
4. `auto-lint-python.sh` and `block-protected-files.sh` missing JSON unescape (`\"` and `\\`) → added
5. Missing tests: double-force flag, uppercase .env, checkout HEAD ., restore --source → 8 tests added (78→86)

**New false positives (by design, marker bypass available):**
- `git restore --staged .` (safe unstage operation)
- `git checkout --ours .` (merge conflict resolution)

**Remaining false negatives (documented, low risk):**
- Variable expansion: `CMD="git push --force" && $CMD`
- Nested scripts: `bash -c "git push --force"`
- Split rm flags: `rm -f -r src/`
- Git -c flag: `git -c user.email=x push --force`

**Also done:** pytest added to pre-commit Phase 1 (blocking) in investments-calculator
