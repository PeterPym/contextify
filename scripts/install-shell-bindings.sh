#!/usr/bin/env bash
set -euo pipefail

MARK="# >>> contextify keybinding >>>"
ENDMARK="# <<< contextify keybinding <<<"

SCHEME_DEFAULT="contextify"
SCHEME="${1:-$SCHEME_DEFAULT}"

remove_block() {
  local file="$1"
  [[ -f "$file" ]] || touch "$file"
  # shellcheck disable=SC2016
  sed -i '' "/$MARK/,/$ENDMARK/d" "$file"
}

install_zsh() {
  local rc="$HOME/.zshrc"
  remove_block "$rc"
  cat >>"$rc" <<EOF2
$MARK
# Contextify keybinding: Ctrl-G Ctrl-G
# Sends the current ZLE buffer (or selection) to Contextify.
function _contextify_compose() {
  local txt=""
  if [[ -n \$REGION_ACTIVE ]]; then
    integer start=\$MARK end=\$CURSOR
    if (( start > end )); then
      integer tmp=start; start=end; end=tmp
    fi
    txt="\${BUFFER[\$start+1,\$end]}"
  else
    txt="\$BUFFER"
  fi
  local b64_raw="\$(printf "%s" "\$txt" | /usr/bin/base64 | tr -d '\n')"
  local b64_enc="\$(printf "%s" "\$b64_raw" | /usr/bin/python3 -c 'import sys, urllib.parse as u; import sys; sys.stdout.write(u.quote(sys.stdin.read()))')"
  /usr/bin/open "${SCHEME}://compose?title=Compose&text64=\${b64_enc}"
  zle redisplay
}
zle -N _contextify_compose
bindkey -M emacs '^G^G' _contextify_compose
bindkey -M vicmd '^G^G' _contextify_compose
bindkey -M viins '^G^G' _contextify_compose
$ENDMARK
EOF2
  echo "Installed zsh keybinding in $rc (scheme: ${SCHEME})."
}

install_bash() {
  local rc="$HOME/.bashrc"
  remove_block "$rc"
  cat >>"$rc" <<EOF2
$MARK
# Contextify keybinding: Ctrl-G Ctrl-G
# Sends the last command line from history to Contextify.
contextify_compose() {
  local txt="\$(history 1 | sed 's/^[ ]*[0-9]\+[ ]*//')"
  local b64_raw="\$(printf "%s" "\$txt" | /usr/bin/base64 | tr -d '\n')"
  local b64_enc="\$(printf "%s" "\$b64_raw" | /usr/bin/python3 -c 'import sys, urllib.parse as u; import sys; sys.stdout.write(u.quote(sys.stdin.read()))')"
  /usr/bin/open "${SCHEME}://compose?title=Compose&text64=\${b64_enc}"
}
bind -x '"\C-g\C-g": contextify_compose'
$ENDMARK
EOF2
  echo "Installed bash keybinding in $rc (scheme: ${SCHEME})."
}

case "${SHELL##*/}" in
  zsh)
    install_zsh
    ;;
  bash)
    install_bash
    ;;
  *)
    echo "Shell $(basename "$SHELL") is not supported yet. Edit scripts/install-shell-bindings.sh to add support." >&2
    exit 1
    ;;
esac

echo "Restart your shell session or 'source' your rc file to pick up the binding."
