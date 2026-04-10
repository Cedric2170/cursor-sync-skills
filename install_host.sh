#!/usr/bin/env bash
set -euo pipefail

# Installe pullskills/pushskills, clone ~/.skills-sync si besoin, et synchronise ~/.cursor.
# skills, rules, subagent, hooks: repertoires reels fusionnes avec skills-sync (rsync sans --delete;
# jamais rm -rf sur les dossiers Cursor — les fichiers uniquement locaux sont conserves).
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
MIGRATION_DONE=0

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

# Fusionne un repertoire ~/.cursor avec le clone Git: aucun --delete, pas de remplacement par lien seul.
# host_dir: ex. ~/.cursor/skills ; sync_dir: ex. ~/.skills-sync/skills (rules <-> roles).
install_cursor_merge() {
  local host_dir="$1"
  local sync_dir="$2"
  mkdir -p "$sync_dir"
  if [[ -e "$host_dir" ]]; then
    if [[ ! -d "$host_dir" ]]; then
      echo "Erreur: $host_dir existe et n'est pas un repertoire (ni lien vers repertoire)."
      exit 1
    fi
    rsync -a "$host_dir/" "$sync_dir/"
  fi
  if [[ -L "$host_dir" ]]; then
    echo "Migration: $host_dir etait un lien — remplace par un repertoire (fusion avec $sync_dir)."
    rm -f "$host_dir"
    MIGRATION_DONE=1
  fi
  mkdir -p "$host_dir"
  rsync -a "$sync_dir/" "$host_dir/"
}

install_links() {
  mkdir -p "$CURSOR_DIR"
  install_cursor_merge "$CURSOR_DIR/skills" "$SYNC_DIR/skills"
  install_cursor_merge "$CURSOR_DIR/rules" "$SYNC_DIR/roles"
  install_cursor_merge "$CURSOR_DIR/subagent" "$SYNC_DIR/subagent"
  install_cursor_merge "$CURSOR_DIR/hooks" "$SYNC_DIR/hooks"
}

commit_migration_if_needed() {
  if [[ "$MIGRATION_DONE" != "1" ]]; then
    return 0
  fi
  if [[ ! -d "$SYNC_DIR/.git" ]]; then
    return 0
  fi
  git -C "$SYNC_DIR" add -A
  if git -C "$SYNC_DIR" diff --staged --quiet; then
    echo "Migration: rien de nouveau a commiter (deja a jour)."
    return 0
  fi
  local host
  host="$(hostname -s 2>/dev/null || hostname)"
  host="${host//[^a-zA-Z0-9._-]/_}"
  git -C "$SYNC_DIR" commit -m "${host}-install_host-migration-locals"
  echo "Migration enregistree dans Git (commit local). Envoyez avec: pushskills"
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
    # Anciens alias (avec espaces possibles) + fautes de frappe ; re-ajoutes dans le bloc marque.
    /^[[:space:]]*alias[[:space:]]+pullskills=/ { next }
    /^[[:space:]]*alias[[:space:]]+pushskills=/ { next }
    /^[[:space:]]*alias[[:space:]]+pullscript=/ { next }
    /^[[:space:]]*alias[[:space:]]+pushskiil=/ { next }
    # Ancien depot ~/.cursor : scripts nommes pullscripts-*/pushscripts-*
    /^[[:space:]]*alias[[:space:]]+pullscripts-master=/ { next }
    /^[[:space:]]*alias[[:space:]]+pushscripts-master=/ { next }
    /^[[:space:]]*alias[[:space:]]+pullscripts-slave=/ { next }
    /^[[:space:]]*alias[[:space:]]+pushscripts-slave=/ { next }
    # Tout alias qui pointe encore vers ces fichiers (ex. pullskills -> pushscripts-master)
    /^[[:space:]]*alias[[:space:]]+/ && $0 ~ /\/\.cursor\/scripts\/(push|pull)scripts-(master|slave)/ { next }
    { print }
  ' "$rc" > "$tmp"
  mv "$tmp" "$rc"

  cat >> "$rc" <<EOF
$MARK_BEGIN
alias pullskills="\$HOME/.cursor/scripts/pullskills"
alias pushskills="\$HOME/.cursor/scripts/pushskills"
$MARK_END
EOF
  echo "Shell mis a jour: $rc"
  echo "  Ouvrez un nouveau terminal ou: source $(printf '%q' "$rc")"
  echo "  (les alias pullskills/pushskills en memoire pointaient peut-etre encore vers pushscripts-master.)"
}

install_scripts
purge_old_cursor_git
ensure_sync_clone
ensure_skill_tree
install_links
commit_migration_if_needed
configure_shell_aliases

echo "OK install: SYNC_DIR=$SYNC_DIR CURSOR_DIR=$CURSOR_DIR"
