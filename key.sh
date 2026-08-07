#!/usr/bin/env bash
# Send a key press to the iPhone through the mirroring window.
# Usage: key.sh <key> [--cmd] [--shift] [--option] [--control]
#   <key>  a single letter/digit, or: return enter tab space delete backspace
#          escape esc left right up down
#
# Examples:
#   key.sh return              submit / go
#   key.sh delete              backspace in a text field
#   key.sh c --cmd             copy (Edit > Copy)
#   key.sh v --cmd             paste (Edit > Paste)
#   key.sh 1 --cmd             Home Screen (same as: iphone-control.sh home)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers/common.sh"

if [[ $# -lt 1 ]]; then
    echo "Usage: key.sh <key> [--cmd] [--shift] [--option] [--control]" >&2
    exit 1
fi

key="$1"; shift
flags=()
labels=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --cmd|--command) flags+=('$.kCGEventFlagMaskCommand'); labels+=("cmd") ;;
        --shift)         flags+=('$.kCGEventFlagMaskShift');   labels+=("shift") ;;
        --option|--alt)  flags+=('$.kCGEventFlagMaskAlternate'); labels+=("option") ;;
        --control|--ctrl) flags+=('$.kCGEventFlagMaskControl'); labels+=("control") ;;
        *) echo "Error: unknown option: $1" >&2; exit 1 ;;
    esac
    shift
done

if (( ${#flags[@]} == 0 )); then
    flags_expr="0"
else
    flags_expr=$(printf '%s|' "${flags[@]}")
    flags_expr="${flags_expr%|}"
fi

# Single printable character: resolve via the ACTIVE keyboard layout so this
# works on AZERTY/QWERTZ/etc, not just US-QWERTY. keycode_for's table is a
# fixed US-QWERTY position map and is only correct on that one layout.
# Falls back to it if the native engine cannot be built (no Xcode CLT).
code=""
if [[ "${#key}" -eq 1 ]]; then
    engine=$(input_engine "$SCRIPT_DIR/helpers" 2>/dev/null) || engine=""
    if [[ -n "$engine" ]]; then
        keyfor_out=$("$engine" keyfor "$key" 2>/dev/null) || keyfor_out=""
        if [[ -n "$keyfor_out" ]]; then
            code="${keyfor_out%% *}"
            base_flags="${keyfor_out##* }"
            # The character may itself require a modifier to produce (e.g. 'A' needs
            # Shift, or a symbol needs Shift on this layout) - fold that in too.
            if [[ "$base_flags" != "0" ]]; then
                flags_expr="${base_flags} | ${flags_expr}"
            fi
        fi
    fi
fi
if [[ -z "$code" ]]; then
    code=$(keycode_for "$key") || {
        echo "Error: unknown key: $key" >&2
        echo "Known: a-z 0-9 return enter tab space delete backspace escape esc left right up down" >&2
        exit 1
    }
fi

jxa_activate_and_run "$(jxa_key_body "$code" "$flags_expr")"

if (( ${#labels[@]} > 0 )); then
    combo=$(printf '%s+' "${labels[@]}")
    echo "Key: ${combo}${key}"
else
    echo "Key: $key"
fi
