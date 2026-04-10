#!/usr/bin/env bash
set -euo pipefail

# Installe pullskills/pushskills, clone ~/.skills-sync si besoin, liens ~/.cursor.
#   ./install_host.sh
#
#   SKILLS_ORIGIN_URL           defaut: git@gitlab.com:point-digital/ia-skills/skills.git
#   CURSOR_SKILLS_SYNC_DIR      defaut: $HOME/.skills-sync
#   CURSOR_DIR                  defaut: $HOME/.cursor
#   CURSOR_PURGE_OLD_CURSOR_GIT=1   supprime ~/.cursor/.git sans autre confirmation
#   SHELL_RC                    ex: ~/.bashrc

CURSOR_DIR="${CURSOR_DIR:-$HOME/.cursor}"
SYNC_DIR="${CURSOR_SKILLS_SYNC_DIR:-$HOME/.skills-sync}"
SKILLS_ORIGIN_URL="${SKILLS_ORIGIN_URL:-git@gitlab.com:point-digital/ia-skills/skills.git}"
SELF_PATH="${BASH_SOURCE[0]:-$0}"
SELF_DIR="$(cd "$(dirname "$SELF_PATH")" && pwd)"

MARK_BEGIN="# >>> cursor-skills-sync >>>"
MARK_END="# <<< cursor-skills-sync <<<"
OLD_MARK_BEGIN="# >>> cursor-global sync >>>"
OLD_MARK_END="# <<< cursor-global sync <<<"

purge_old_cursor_git() {
  if [[ ! -d "$CURSOR_DIR/.git" ]]; then
    return 0
  fi
  if [[ "${CURSOR_PURGE_OLD_CURSOR_GIT:-0}" == "1" ]]; then
    rm -rf "$CURSOR_DIR/.git"
    echo "Ancien depot supprime: $CURSOR_DIR/.git"
    return 0
  fi
  echo "Avertissement: $CURSOR_DIR/.git existe (ancien modele)."
  echo "Supprimez-le ou relancez avec: CURSOR_PURGE_OLD_CURSOR_GIT=1 $SELF_PATH"
}

ensure_sync_clone() {
  if [[ -d "$SYNC_DIR/.git" ]]; then
    SYNC_DIR="$(cd "$SYNC_DIR" && pwd)"
    return 0
  fi
  if [[ -e "$SYNC_DIR" ]]; then
    echo "Erreur: $SYNC_DIR existe mais n'est pas un clone Git."
    exit 1
  fi
  git clone "$SKILLS_ORIGIN_URL" "$SYNC_DIR"
  SYNC_DIR="$(cd "$SYNC_DIR" && pwd)"
}

ensure_skill_tree() {
  mkdir -p "$SYNC_DIR/skills" "$SYNC_DIR/roles" "$SYNC_DIR/subagent" "$SYNC_DIR/hooks"
}

symlink_ok() {
  local target="$1" linkpath="$2"
  if [[ -L "$linkpath" ]]; then
    local cur
    cur="$(readlink "$linkpath")"
    if [[ "$cur" == "$target" ]]; then
      return 0
    fi
    echo "Erreur: $linkpath pointe vers $cur (attendu: $target)."
    exit 1
  fi
  if [[ -e "$linkpath" ]]; then
    echo "Erreur: $linkpath existe et n'est pas le lien attendu. Deplacez-le puis relancez."
    exit 1
  fi
  ln -s "$target" "$linkpath"
}

install_links() {
  mkdir -p "$CURSOR_DIR"
  symlink_ok "$SYNC_DIR/skills" "$CURSOR_DIR/skills"
  symlink_ok "$SYNC_DIR/roles" "$CURSOR_DIR/rules"
  symlink_ok "$SYNC_DIR/subagent" "$CURSOR_DIR/subagent"
  symlink_ok "$SYNC_DIR/hooks" "$CURSOR_DIR/hooks"
}

install_scripts() {
  mkdir -p "$CURSOR_DIR/scripts"
  install -m 0755 "$SELF_DIR/pullskills" "$CURSOR_DIR/scripts/pullskills"
  install -m 0755 "$SELF_DIR/pushskills" "$CURSOR_DIR/scripts/pushskills"
}

configure_shell_aliases() {
  local rc="${SHELL_RC:-}"
  if [[ -z "$rc" ]]; then
    if [[ -n "${ZSH_VERSION:-}" || "${SHELL##*/}" == "zsh" ]]; then
      rc="$HOME/.zshrc"
    elif [[ -n "${BASH_VERSION:-}" || "${SHELL##*/}" == "bash" ]]; then
      rc="$HOME/.bashrc"
    elif [[ -f "$HOME/.zshrc" ]]; then
      rc="$HOME/.zshrc"
    else
      rc="$HOME/.bashrc"
    fi
  fi
  touch "$rc"

  local tmp
  tmp="$(mktemp)"
  awk -v a="$OLD_MARK_BEGIN" -v b="$OLD_MARK_END" -v c="$MARK_BEGIN" -v d="$MARK_END" '
    $0 == a || $0 == c { skip=1; next }
    $0 == b || $0 == d { skip=0; next }
    !skip { print }
  ' "$rc" > "$tmp"
  mv "$tmp" "$rc"

  tmp="$(mktemp)"
  awk '
    $0 ~ /^alias pullskills=/ { next }
    $0 ~ /^alias pushskills=/ { next }
    $0 ~ /^alias pullscript=/ { next }
    $0 ~ /^alias pushskiil=/ { next }
    { print }
  ' "$rc" > "$tmp"
  mv "$tmp" "$rc"

  cat >> "$rc" <<EOF
$MARK_BEGIN
alias pullskills="\$HOME/.cursor/scripts/pullskills"
alias pushskills="\$HOME/.cursor/scripts/pushskills"
$MARK_END
EOF
  echo "Shell mis a jour: $rc (source $rc ou rouvrez un terminal)"
}

install_scripts
purge_old_cursor_git
ensure_sync_clone
ensure_skill_tree
install_links
configure_shell_aliases

echo "OK install: SYNC_DIR=$SYNC_DIR CURSOR_DIR=$CURSOR_DIR"
