#!/bin/bash
# Install global Claude Code config from this repo to ~/.claude/
# Creates symlinks so edits in ~/.claude/ auto-sync to the repo.
# Run: bash install.sh
#
# REQUIRES: Developer Mode on Windows (Settings → System → Advanced → Developer Mode)
# WHY symlinks: editing ~/.claude/CLAUDE.md edits the repo copy directly.
# Just `git commit && push` to backup — no manual copy step.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

# WHY: Git Bash on Windows needs this env var to create native NTFS symlinks.
# Without it, ln -s creates copies instead of symlinks.
export MSYS=winsymlinks:nativestrict

echo "Installing claude-code-config to $CLAUDE_DIR (via symlinks)"
echo ""

# Backup existing files (not symlinks)
for f in CLAUDE.md settings.json; do
  if [ -f "$CLAUDE_DIR/$f" ] && [ ! -L "$CLAUDE_DIR/$f" ]; then
    cp "$CLAUDE_DIR/$f" "$CLAUDE_DIR/$f.bak"
    echo "  Backed up existing $f → $f.bak"
  fi
done

# Create symlinks for global config
mkdir -p "$CLAUDE_DIR/hooks"

rm -f "$CLAUDE_DIR/CLAUDE.md"
ln -s "$SCRIPT_DIR/global/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"

rm -f "$CLAUDE_DIR/settings.json"
ln -s "$SCRIPT_DIR/global/settings.json" "$CLAUDE_DIR/settings.json"

echo "  Linked CLAUDE.md and settings.json"

# Create symlinks for global hooks
for hook in "$SCRIPT_DIR/global/hooks/"*.sh; do
  name=$(basename "$hook")
  rm -f "$CLAUDE_DIR/hooks/$name"
  ln -s "$hook" "$CLAUDE_DIR/hooks/$name"
done

echo "  Linked $(ls "$SCRIPT_DIR/global/hooks/"*.sh | wc -l) global hooks"

echo ""
echo "Done. Symlinks created:"
ls -la "$CLAUDE_DIR/CLAUDE.md" "$CLAUDE_DIR/settings.json"
ls -la "$CLAUDE_DIR/hooks/"
echo ""
echo "Edits to ~/.claude/ files now auto-sync to this repo."
echo "To push changes: cd $(pwd) && git add -A && git commit -m 'update' && git push"
