# shellcheck shell=bash
#
# Cross-platform link primitives shared by install.sh and uninstall.sh.
#
# Windows grants no unprivileged POSIX symlink: Git Bash's `ln -s` silently degrades to
# a plain copy, so a linked file stops tracking the repo without ever reporting an error.
# Directory junctions and file hardlinks need no elevation, and Git Bash reports a
# junction as a symlink, so the `test -L` / `readlink` checks here stay valid for
# directories on both platforms. Files are the exception: a hardlink is not a symlink,
# so its identity is inode equality instead of a target path.
#
# Source this file, then call link_lib_init before using any of the primitives.

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) PLATFORM=windows ;;
  *)                    PLATFORM=posix   ;;
esac

PS_BIN=""

link_lib_init() {
  [ "$PLATFORM" = windows ] || return 0

  if ! command -v cygpath &>/dev/null; then
    echo "error: 'cygpath' not found -- run this script from Git Bash."
    exit 1
  fi

  local candidate
  for candidate in powershell pwsh; do
    if command -v "$candidate" &>/dev/null; then PS_BIN="$candidate"; return 0; fi
  done

  echo "error: neither 'powershell' nor 'pwsh' was found in PATH."
  echo "  they are needed to create and remove junctions and hardlinks"
  exit 1
}

# A PowerShell single-quoted string escapes a quote by doubling it.
ps_quote() { printf '%s' "${1//\'/\'\'}"; }

win_arg() { ps_quote "$(cygpath -w "$1")"; }

ps_run() { "$PS_BIN" -NoProfile -NonInteractive -Command "$1" >/dev/null; }

make_dir_link() { # src dst
  if [ "$PLATFORM" = windows ]; then
    ps_run "New-Item -ItemType Junction -Path '$(win_arg "$2")' -Target '$(win_arg "$1")' | Out-Null"
  else
    ln -s "$1" "$2"
  fi
}

make_file_link() { # src dst
  if [ "$PLATFORM" = windows ]; then
    ps_run "New-Item -ItemType HardLink -Path '$(win_arg "$2")' -Target '$(win_arg "$1")' | Out-Null"
  else
    ln -s "$1" "$2"
  fi
}

# Deletes the link itself and never its contents -- `rm` on a reparse point is not
# reliably non-recursive, so route directory unlinking through the .NET call that is.
remove_dir_link() { # dst
  if [ "$PLATFORM" = windows ]; then
    ps_run "[System.IO.Directory]::Delete('$(win_arg "$1")')"
  else
    rm "$1"
  fi
}

is_dir_linked() { # src dst
  [ -L "$2" ] && [ "$(readlink "$2")" = "$1" ]
}

is_file_linked() { # src dst
  if [ "$PLATFORM" = windows ]; then
    [ -f "$2" ] && [ "$2" -ef "$1" ]
  else
    [ -L "$2" ] && [ "$(readlink "$2")" = "$1" ]
  fi
}

# An existing backup is somebody's only copy of a file this script displaced on an
# earlier run; never write over it.
backup_path() { # dst
  if [ -e "$1.bak" ]; then
    printf '%s' "$1.bak.$(date +%Y%m%d%H%M%S)"
  else
    printf '%s' "$1.bak"
  fi
}
