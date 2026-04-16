#!/usr/bin/env bash
set -euo pipefail

# Installation du sync skills avec la structure suivante:
# - Donnees sous ~/.skills-sync/{skills,roles,subagent,hooks}
# - Liens ~/.cursor/{skills,rules,subagent,hooks} -> ~/.skills-sync/{skills,roles,subagent,hooks}

CURSOR_DIR="${CURSOR_DIR:-$HOME/.cursor}"
SYNC_DIR="${CURSOR_SKILLS_SYNC_DIR:-$HOME/.skills-sync}"
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
    return 0
  fi
  if [[ -e "$SYNC_DIR" ]]; then
    echo "Erreur: $SYNC_DIR existe mais n'est pas un clone Git."
    exit 1
  fi
  git clone "$SKILLS_ORIGIN_URL" "$SYNC_DIR"
  SYNC_DIR="$(cd "$SYNC_DIR" && pwd)"
}

ensure_target_tree() {
  mkdir -p "$SYNC_DIR/skills" "$SYNC_DIR/roles" "$SYNC_DIR/subagent" "$SYNC_DIR/hooks"
}

# Migration de layout: ancien skills/skills/* -> skills/*
migrate_old_nested_layout() {
  local nested="$SYNC_DIR/skills/skills"
  if [[ -d "$nested" ]]; then
    rsync -a "$nested/" "$SYNC_DIR/skills/"
    rm -rf "$nested"
    echo "install: migration depot: skills/skills/* -> skills/*"
  fi
  for name in roles subagent hooks; do
    local old="$SYNC_DIR/skills/$name"
    if [[ -d "$old" && -d "$SYNC_DIR/$name" ]]; then
      rsync -a "$old/" "$SYNC_DIR/$name/"
      rm -rf "$old"
      echo "install: migration depot: skills/$name -> $name"
    fi
  done
}

# Fusionne le contenu local dans le clone, puis cree le lien symbolique.
# 1. Si host_dir est un repertoire (pas un lien): rsync contenu -> sync_dir, puis rm -rf host_dir.
# 2. Si host_dir est deja un lien vers sync_dir: rien a faire.
# 3. Si host_dir est un lien vers ailleurs: supprimer le lien.
# 4. Creer le lien host_dir -> sync_dir.
link_cursor_dir() {
  local host_dir="$1"
  local sync_dir="$2"
  mkdir -p "$sync_dir"

  if [[ -L "$host_dir" ]]; then
    local current_target
    current_target="$(readlink "$host_dir")"
    if [[ "$current_target" == "$sync_dir" ]]; then
      echo "install: lien deja OK: $(printf '%q' "$host_dir") -> $(printf '%q' "$sync_dir")"
      return 0
    fi
    echo "install: ancien lien $(printf '%q' "$host_dir") -> $(printf '%q' "$current_target") (sera remplace)"
    rm -f "$host_dir"
  elif [[ -d "$host_dir" ]]; then
    rsync -a "$host_dir/" "$sync_dir/"
    echo "install: contenu local copie dans le clone: $(printf '%q' "$host_dir") -> $(printf '%q' "$sync_dir")"
    rm -rf "$host_dir"
  elif [[ -e "$host_dir" ]]; then
    echo "Erreur: $host_dir existe et n'est pas un repertoire."
    exit 1
  fi

  ln -sfn "$sync_dir" "$host_dir"
  echo "install: lien cree: $(printf '%q' "$host_dir") -> $(printf '%q' "$sync_dir")"
}

install_links() {
  mkdir -p "$CURSOR_DIR"
  link_cursor_dir "$CURSOR_DIR/skills" "$SYNC_DIR/skills"
  link_cursor_dir "$CURSOR_DIR/rules" "$SYNC_DIR/roles"
  link_cursor_dir "$CURSOR_DIR/subagent" "$SYNC_DIR/subagent"
  link_cursor_dir "$CURSOR_DIR/hooks" "$SYNC_DIR/hooks"
}

install_scripts() {
  mkdir -p "$CURSOR_DIR/scripts"
  install -m 0755 "$SELF_DIR/pullskills" "$CURSOR_DIR/scripts/pullskills"
  install -m 0755 "$SELF_DIR/pushskills" "$CURSOR_DIR/scripts/pushskills"
}

pull_before_links() {
  if git -C "$SYNC_DIR" pull --rebase --autostash origin "$SKILLS_BRANCH"; then
    echo "install: git pull OK (origin/$SKILLS_BRANCH)."
  else
    echo "Avertissement: git pull a echoue dans $SYNC_DIR — resoudre puis pullskills." >&2
  fi
}

install_commit_and_push() {
  git -C "$SYNC_DIR" add -A -- skills roles subagent hooks
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
migrate_old_nested_layout
pull_before_links
install_links
install_scripts
install_commit_and_push
configure_shell_aliases

echo "OK install: SYNC_DIR=$SYNC_DIR CURSOR_DIR=$CURSOR_DIR"
echo "  ~/.cursor/skills   -> ~/.skills-sync/skills"
echo "  ~/.cursor/rules    -> ~/.skills-sync/roles"
echo "  ~/.cursor/subagent -> ~/.skills-sync/subagent"
echo "  ~/.cursor/hooks    -> ~/.skills-sync/hooks"
