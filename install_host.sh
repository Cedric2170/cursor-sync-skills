#!/usr/bin/env bash
set -euo pipefail

# Installation du sync skills avec structure:
# - Donnees skills sous ~/.skills-sync/skills/{skills,roles,subagent,hooks}
# - Scripts sous ~/.skills-sync/scripts
# - Liens ~/.cursor/* vers ces chemins

CURSOR_DIR="${CURSOR_DIR:-$HOME/.cursor}"
SYNC_DIR="${CURSOR_SKILLS_SYNC_DIR:-$HOME/.skills-sync}"
DATA_DIR="$SYNC_DIR/skills"
SCRIPTS_DIR="$SYNC_DIR/scripts"
SKILLS_BRANCH="${SKILLS_BRANCH:-main}"
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
    DATA_DIR="$SYNC_DIR/skills"
    SCRIPTS_DIR="$SYNC_DIR/scripts"
    return 0
  fi
  if [[ -e "$SYNC_DIR" ]]; then
    echo "Erreur: $SYNC_DIR existe mais n'est pas un clone Git."
    exit 1
  fi
  git clone "$SKILLS_ORIGIN_URL" "$SYNC_DIR"
  SYNC_DIR="$(cd "$SYNC_DIR" && pwd)"
  DATA_DIR="$SYNC_DIR/skills"
  SCRIPTS_DIR="$SYNC_DIR/scripts"
}

ensure_target_tree() {
  mkdir -p "$DATA_DIR/skills" "$DATA_DIR/roles" "$DATA_DIR/subagent" "$DATA_DIR/hooks" "$SCRIPTS_DIR"
}

# Migration de layout: racine -> skills/*
migrate_root_to_data_dir() {
  local name src dst
  for name in skills roles subagent hooks; do
    src="$SYNC_DIR/$name"
    dst="$DATA_DIR/$name"
    if [[ -e "$src" && "$src" != "$dst" ]]; then
      mkdir -p "$dst"
      if [[ -d "$src" ]]; then
        rsync -a "$src/" "$dst/"
        rm -rf "$src"
      else
        mv "$src" "$dst"
      fi
      echo "install: migration depot: $name -> skills/$name"
    fi
  done
}

copy_if_real_dir() {
  local host_dir="$1"
  local sync_dir="$2"
  mkdir -p "$sync_dir"
  if [[ -e "$host_dir" && ! -L "$host_dir" ]]; then
    if [[ ! -d "$host_dir" ]]; then
      echo "Erreur: $host_dir existe et n'est pas un repertoire."
      exit 1
    fi
    rsync -a "$host_dir/" "$sync_dir/"
    echo "install: copie vers clone: $(printf '%q' "$host_dir") -> $(printf '%q' "$sync_dir")"
  fi
}

symlink_cursor_to_sync() {
  local host_path="$1"
  local sync_path="$2"
  if [[ -e "$host_path" || -L "$host_path" ]]; then
    rm -rf "$host_path"
  fi
  ln -sfn "$sync_path" "$host_path"
  echo "install: lien: $(printf '%q' "$host_path") -> $(printf '%q' "$sync_path")"
}

install_symlinks() {
  mkdir -p "$CURSOR_DIR"
  copy_if_real_dir "$CURSOR_DIR/skills" "$DATA_DIR/skills"
  copy_if_real_dir "$CURSOR_DIR/rules" "$DATA_DIR/roles"
  copy_if_real_dir "$CURSOR_DIR/subagent" "$DATA_DIR/subagent"
  copy_if_real_dir "$CURSOR_DIR/hooks" "$DATA_DIR/hooks"
  copy_if_real_dir "$CURSOR_DIR/scripts" "$SCRIPTS_DIR"

  symlink_cursor_to_sync "$CURSOR_DIR/skills" "$DATA_DIR/skills"
  symlink_cursor_to_sync "$CURSOR_DIR/rules" "$DATA_DIR/roles"
  symlink_cursor_to_sync "$CURSOR_DIR/subagent" "$DATA_DIR/subagent"
  symlink_cursor_to_sync "$CURSOR_DIR/hooks" "$DATA_DIR/hooks"
  symlink_cursor_to_sync "$CURSOR_DIR/scripts" "$SCRIPTS_DIR"
}

install_scripts() {
  mkdir -p "$SCRIPTS_DIR"
  install -m 0755 "$SELF_DIR/pullskills" "$SCRIPTS_DIR/pullskills"
  install -m 0755 "$SELF_DIR/pushskills" "$SCRIPTS_DIR/pushskills"
}

pull_after_links() {
  if git -C "$SYNC_DIR" pull --rebase --autostash origin "$SKILLS_BRANCH"; then
    echo "install: git pull OK (origin/$SKILLS_BRANCH)."
  else
    echo "Avertissement: git pull a echoue dans $SYNC_DIR — resoudre puis pullskills." >&2
  fi
}

install_commit_and_push() {
  git -C "$SYNC_DIR" add -A -- skills scripts
  if ! git -C "$SYNC_DIR" diff --staged --quiet; then
    local host
    host="$(hostname -s 2>/dev/null || hostname)"
    host="${host//[^a-zA-Z0-9._-]/_}"
    git -C "$SYNC_DIR" commit -m "${host}-install-layout-sync"
    echo "install: commit cree (layout + fusion)."
  else
    echo "install: rien a commiter."
  fi

  if [[ "${CURSOR_INSTALL_SKIP_PUSH:-0}" == "1" ]]; then
    echo "install: push ignore (CURSOR_INSTALL_SKIP_PUSH=1)."
    return 0
  fi
  if git -C "$SYNC_DIR" push --progress origin "HEAD:${SKILLS_BRANCH}"; then
    echo "install: git push OK."
  else
    echo "Avertissement: git push a echoue — essayez plus tard: pushskills" >&2
  fi
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

  cat >> "$rc" <<EOF
$MARK_BEGIN
alias pullskills="\$HOME/.cursor/scripts/pullskills"
alias pushskills="\$HOME/.cursor/scripts/pushskills"
$MARK_END
EOF

  echo "Shell mis a jour: $rc"
  echo "  Ouvrez un nouveau terminal ou: source $(printf '%q' "$rc")"
}

purge_old_cursor_git
ensure_sync_clone
ensure_target_tree
migrate_root_to_data_dir
install_symlinks
install_scripts
pull_after_links
install_commit_and_push
configure_shell_aliases

echo "OK install: SYNC_DIR=$SYNC_DIR CURSOR_DIR=$CURSOR_DIR"
echo "  ~/.cursor/skills -> ~/.skills-sync/skills/skills"
echo "  ~/.cursor/rules  -> ~/.skills-sync/skills/roles"
echo "  ~/.cursor/subagent -> ~/.skills-sync/skills/subagent"
echo "  ~/.cursor/hooks -> ~/.skills-sync/skills/hooks"
echo "  ~/.cursor/scripts -> ~/.skills-sync/scripts"
