#!/usr/bin/env bash
set -euo pipefail

RAW_BASE="https://raw.githubusercontent.com/h-zare-dev/floatip-manager/main"
TARGET="/usr/local/sbin/floatip"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

[ "${EUID}" -eq 0 ] || fail "Run the installer with sudo/root."

command -v curl >/dev/null 2>&1 \
    || fail "curl is required to install floatip-manager."

command -v bash >/dev/null 2>&1 \
    || fail "bash is required to install floatip-manager."

command -v ip >/dev/null 2>&1 \
    || fail "The 'ip' command (iproute2) is required."

command -v netplan >/dev/null 2>&1 \
    || fail "Netplan is not installed. This installer does not modify the system network stack."

TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT

echo "Downloading floatip..."
curl -fsSL "${RAW_BASE}/floatip" -o "$TMP_FILE"

[ -s "$TMP_FILE" ] || fail "Downloaded floatip script is empty."

FIRST_LINE="$(head -n 1 "$TMP_FILE")"
[ "$FIRST_LINE" = '#!/usr/bin/env bash' ] \
    || fail "Downloaded file does not look like the expected floatip script."

bash -n "$TMP_FILE" \
    || fail "Downloaded floatip script failed Bash syntax validation."

mkdir -p "$(dirname "$TARGET")"
install -m 0755 "$TMP_FILE" "$TARGET"

echo
echo "floatip-manager installed successfully."
echo "Command: $TARGET"
echo
echo "Examples:"
echo "  sudo floatip add 203.0.113.10"
echo "  sudo floatip del 203.0.113.10"
echo "  sudo floatip show"
echo
echo "Installation itself did not change any network addresses."
