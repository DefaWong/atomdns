#!/usr/bin/env bash
# Collects the assets that scripts/install.sh downloads from a DefaWong/atomdns release.
#
#   ATOMDNS_MUSL_TGZ=release/rust/atomdns-linux-amd64-musl.tar.gz \
#   WEBUI_TGZ=release/rust/atomdns-webui.tar.gz \
#   CONFIG_ZIP=/path/to/config_rust.zip \
#   SINGBOX_SRC=../../golang/sing-box \
#     scripts/package-installer-assets.sh release/installer
#
# Builds the customized sing-box for linux/amd64 (static, CGO disabled) from SINGBOX_SRC,
# copies the other assets and writes SHA256SUMS. It only builds; publishing a release
# is a separate, confirmed step (docs/rust/installer.md).
set -euo pipefail

OUT="${1:?output directory is required}"
: "${ATOMDNS_MUSL_TGZ:?path to atomdns-linux-amd64-musl.tar.gz}"
: "${WEBUI_TGZ:?path to atomdns-webui.tar.gz}"
: "${CONFIG_ZIP:?path to config_rust.zip}"
: "${SINGBOX_SRC:?path to the customized sing-box checkout}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
SINGBOX_SRC="$(cd "$SINGBOX_SRC" && pwd)"

tar -tzf "$ATOMDNS_MUSL_TGZ" | grep -qx atomdns || { echo "$ATOMDNS_MUSL_TGZ has no top-level atomdns" >&2; exit 1; }
tar -tzf "$WEBUI_TGZ" | grep -qx index.html || { echo "$WEBUI_TGZ has no top-level index.html" >&2; exit 1; }
unzip -l "$CONFIG_ZIP" | grep -q ' config_custom.yaml$' || { echo "$CONFIG_ZIP has no config_custom.yaml" >&2; exit 1; }

TAGS="$(cat "$SINGBOX_SRC/release/DEFAULT_BUILD_TAGS_OTHERS")"
LDFLAGS_SHARED="$(cat "$SINGBOX_SRC/release/LDFLAGS")"
BASE_TAG="$(git -C "$SINGBOX_SRC" describe --tags --abbrev=0)"
VERSION="${BASE_TAG#v}-atomdns.$(git -C "$SINGBOX_SRC" rev-parse --short HEAD)"
if [ -n "$(git -C "$SINGBOX_SRC" status --porcelain --untracked-files=no)" ]; then
  echo "warning: $SINGBOX_SRC has uncommitted changes" >&2
fi

BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT
echo "building sing-box ${VERSION}"
(
  cd "$SINGBOX_SRC"
  GOTOOLCHAIN=local CGO_ENABLED=0 GOOS=linux GOARCH=amd64 GOAMD64=v1 go build -trimpath -tags "$TAGS" \
    -ldflags "-X 'github.com/sagernet/sing-box/constant.Version=${VERSION}' ${LDFLAGS_SHARED} -s -w -buildid=" \
    -o "$BUILD/sing-box" ./cmd/sing-box
)
# macOS bsdtar would add extended-attribute headers that GNU/busybox tar warn about.
TAR_FLAGS=()
if tar --version 2>/dev/null | grep -q bsdtar; then TAR_FLAGS=(--no-xattrs --no-mac-metadata); fi
COPYFILE_DISABLE=1 tar "${TAR_FLAGS[@]}" -czf "$OUT/sing-box-linux-amd64.tar.gz" -C "$BUILD" sing-box

cp "$ATOMDNS_MUSL_TGZ" "$OUT/atomdns-linux-amd64-musl.tar.gz"
cp "$WEBUI_TGZ" "$OUT/atomdns-webui.tar.gz"
cp "$CONFIG_ZIP" "$OUT/config_rust.zip"
cp "$ROOT/scripts/install.sh" "$OUT/install.sh"

(
  cd "$OUT"
  if command -v sha256sum >/dev/null; then SUM=(sha256sum); else SUM=(shasum -a 256); fi
  "${SUM[@]}" atomdns-linux-amd64-musl.tar.gz sing-box-linux-amd64.tar.gz atomdns-webui.tar.gz config_rust.zip >SHA256SUMS
  cat SHA256SUMS
)
echo "assets in $OUT"
