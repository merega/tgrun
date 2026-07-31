#!/usr/bin/env sh
set -eu

BASE_URL=${TGRUN_BASE_URL:-https://tools.example.com/tgrun}
INSTALL_DIR=${TGRUN_INSTALL_DIR:-/usr/local/bin}
CONFIG_PATH=${TGRUN_CONFIG_PATH:-/etc/tgrun.conf}

case "$(uname -m)" in
  x86_64|amd64) arch=amd64 ;;
  aarch64|arm64) arch=arm64 ;;
  *) printf 'Unsupported architecture: %s\n' "$(uname -m)" >&2; exit 1 ;;
esac

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

curl -fsSL "$BASE_URL/tgrun-linux-$arch" -o "$tmp_dir/tgrun"
curl -fsSL "$BASE_URL/SHA256SUMS" -o "$tmp_dir/SHA256SUMS"

expected=$(awk -v file="tgrun-linux-$arch" '$2 == file {print $1}' "$tmp_dir/SHA256SUMS")
actual=$(sha256sum "$tmp_dir/tgrun" | awk '{print $1}')
[ -n "$expected" ] && [ "$expected" = "$actual" ] || {
  printf 'SHA256 verification failed\n' >&2
  exit 1
}

install -d "$INSTALL_DIR"
install -m 0755 "$tmp_dir/tgrun" "$INSTALL_DIR/tgrun"

if [ ! -e "$CONFIG_PATH" ]; then
  umask 077
  cat > "$CONFIG_PATH" <<'EOF'
bot_token=
chat_id=
thread_id=
send_output=on-error
output_lines=20
http_timeout_seconds=15
EOF
fi

printf 'Installed %s/tgrun\n' "$INSTALL_DIR"
printf 'Configure %s, then run: tgrun get-chat-id\n' "$CONFIG_PATH"
