#!/bin/bash
set -euo pipefail

# 本脚本由 Actions 在 OpenWrt 源码根目录执行
DIY_DIR="$(cd "$(dirname "$0")" && pwd)"

# Adjust source code
patch -p1 -f < "$DIY_DIR/luci.patch"

# Clone existing packages
mkdir -p clone

git clone --depth=1 \
  https://github.com/ophub/luci-app-amlogic \
  clone/amlogic

git clone --depth=1 \
  https://github.com/Openwrt-Passwall/openwrt-passwall \
  clone/passwall

git clone --depth=1 \
  https://github.com/Zerogiven-OpenWRT-Packages/luci-app-podman \
  feeds/luci/applications/luci-app-podman

# Replace existing LuCI packages
rm -rf \
  feeds/luci/applications/luci-app-daed \
  feeds/luci/applications/luci-app-passwall

cp -a clone/amlogic/luci-app-amlogic \
  feeds/luci/applications/

cp -a clone/passwall/luci-app-passwall \
  feeds/luci/applications/

sed -i '/luci-app-attendedsysupgrade/d' \
  feeds/luci/collections/luci/Makefile

# Fetch the reviewed daeuniverse package definitions
DAEUNIVERSE_COMMIT=8c6ed9bd00a99d7662cfd5bf15fb4eed393ce689

git init clone/daeuniverse
git -C clone/daeuniverse remote add origin \
  https://github.com/daeuniverse/openwrt-packages.git

git -C clone/daeuniverse fetch --depth=1 origin \
  "$DAEUNIVERSE_COMMIT"

git -C clone/daeuniverse checkout --detach FETCH_HEAD

# Import only honk and its shared LuCI/BTF packages.
# Leave the distribution's dae package unchanged.
mkdir -p package/daeuniverse

for pkg in \
  honk \
  luci-app-honk \
  luci-lib-daeuniverse \
  vmlinux-btf-builtin
do
  cp -a "clone/daeuniverse/$pkg" package/daeuniverse/
done

# This N1 image uses eth0 directly for its LAN instead of an OpenWrt bridge.
sed -i 's/lan_interface: br-lan/lan_interface: eth0/' \
  package/daeuniverse/honk/files/config.dae

# OpenWrt's package build PATH can put its staged Cargo ahead of rustup.
# honk selects pinned stable/nightly toolchains, so keep rustup's proxies first.
python3 - <<'PY'
from pathlib import Path

build_script = Path("package/daeuniverse/honk/build.sh")
text = build_script.read_text()
marker = "set -eu\n"
if text.count(marker) != 1:
    raise SystemExit("honk/build.sh: expected one set -eu marker")
text = text.replace(
    marker,
    marker + 'export PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"\n',
    1,
)
build_script.write_text(text)
PY

# The honk Makefile requires sources at honk/src.
# Match the tag expected by the pinned package Makefile.
git clone --depth=1 --branch v0.1.0-beta.6 \
  https://github.com/daeuniverse/honk.git \
  package/daeuniverse/honk/src

# Clean temporary package checkouts
rm -rf clone
