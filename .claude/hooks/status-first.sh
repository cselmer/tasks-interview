#!/bin/sh
# Claude Code PostToolUse hook for Edit|Write|MultiEdit that keeps request specs
# status-first (CLAUDE.md, Testing). Also runs by hand on spec paths:
#   .claude/hooks/status-first.sh spec/requests/tasks_spec.rb
# Only follow_redirect! resets the status, so a second request in the same
# example and reads through helper methods are not linted.

if [ $# -eq 0 ]; then
  if [ -t 0 ]; then
    echo "usage: status-first.sh SPEC_FILE..." >&2
    exit 1
  fi

  file_path=$(sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)
  case $file_path in
    *spec/requests/*_spec.rb) set -- "$file_path" ;;
    *) exit 0 ;;
  esac
fi

awk '
function indentation(line) {
  match(line, /^[ \t]*/)
  return RLENGTH
}

/^[ \t]*$/ { next }
in_example && indentation($0) <= example_indent { in_example = 0 }

!in_example && /^[ \t]*it[ \t(].* do([ \t]*\|[^|]*\|)?[ \t]*$/ {
  in_example = 1
  asserted = 0
  reported = 0
  example_indent = indentation($0)
  example_line = FNR
  next
}

!in_example || /^[ \t]*#/ { next }

/follow_redirect!/ { asserted = 0 }
/have_http_status/ { asserted = 1 }

/response\.body|assert_select|parsed_body/ && !asserted && !reported {
  printf "status-first: %s:%d reads the response before asserting its status (example at line %d). Add expect(response).to have_http_status(...) first, and again after follow_redirect! (CLAUDE.md, Testing).\n", FILENAME, FNR, example_line
  reported = 1
  violations++
}

END { if (violations) exit 2 }
' "$@" >&2
