#!/bin/bash
#
# Copyright (c) 2019-2020 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#

# ---------------------------------------------------------------------------
# Upstream repositories (edit here to switch to a mirror or a fork)
# ---------------------------------------------------------------------------
SBWML_REPO="https://github.com/sbwml/openwrt_helloworld"
SSRP_REPO="https://github.com/fw876/helloworld"
PW1_REPO="https://github.com/Openwrt-Passwall/openwrt-passwall"
PW2_REPO="https://github.com/Openwrt-Passwall/openwrt-passwall2"
PWP_REPO="https://github.com/Openwrt-Passwall/openwrt-passwall-packages"

# ---------------------------------------------------------------------------
# Remove feed copies of packages provided by a locally cloned repo
# ---------------------------------------------------------------------------
remove_feed_duplicates() {
  local repo_dir="$1" pkgdir pkgname
  [ -d "$repo_dir" ] || return 0
  for pkgdir in "$repo_dir"/*/; do
    [ -f "$pkgdir/Makefile" ] || continue
    pkgname=$(basename "$pkgdir")
    [ -n "$pkgname" ] || continue
    find feeds -type d -name "$pkgname" -prune \
      -exec sh -c '[ -f "$1/Makefile" ] && rm -rf "$1" && echo "removed $1"' _ {} \; 2>/dev/null || true
  done
  # Drop the symlinks that "feeds install -a" left pointing at the removed dirs.
  find package/feeds -xtype l -delete 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Remove the upx invocations from the given package directories
# ---------------------------------------------------------------------------
# Some packages compress their binaries with upx at build time (xray-core and
# mihomo in helloworld, for example). The compressed binaries are bigger pain
# than they are worth: upx builds a host tool first, some of its outputs fail
# on certain kernels/filesystems, and the runtime decompression hides the real
# binary size. Only the directories passed in are rewritten, so the
# uncompressed binary that was already copied next to it is installed instead.
# Usage: remove_upx_calls <pkg-dir>...
remove_upx_calls() {
  [ "$#" -gt 0 ] || { echo "remove_upx_calls: 用法: remove_upx_calls <pkg-dir>..." >&2; return 1; }
  local dir file count=0
  # "$(STAGING_DIR_HOST)/bin/upx ..." and a bare "upx -..." invocation.
  local pat='STAGING_DIR[^[:space:]]*/bin/upx|(^|[[:space:];:()])upx[[:space:]]+-'

  for dir in "$@"; do
    [ -d "$dir" ] || { echo "跳过 upx 清理（目录不存在）：$dir"; continue; }
    while IFS= read -r file; do
      grep -qE "$pat" "$file" || continue
      # Drop the upx command line and the "upx/host" build dependency.
      sed -i -E -e "\#$pat#d" \
               -e '/^[[:space:]]*PKG_BUILD_DEPENDS/ s#[[:space:]]+upx/host##g' "$file"
      echo "移除 upx 命令：$file"
      count=$((count + 1))
    done < <(find "$dir" -type f -name Makefile)
  done
  echo "已清理 $count 个 Makefile 中的 upx 命令"
}

# ---------------------------------------------------------------------------
# Replace local packages with the copies from an upstream repository
# ---------------------------------------------------------------------------
# Usage: replace_from_repo <repo-url> <dest-dir> <pkg>...
#   <repo-url> : git URL to clone (shallow, depth=1)
#   <dest-dir> : directory that holds the local packages to overwrite
#   <pkg>...   : package folder names to copy over from <repo-url>
#
# A package that does not exist upstream is skipped with a message instead of
# failing, so the same call keeps working when upstream drops or renames one.
# The clone goes to a temp dir that is always removed; set REPO_REF to clone a
# specific branch/tag.
replace_from_repo() {
  local repo="$1" dest="$2" ref="${REPO_REF:-}"
  local clone_dir pkg clone_args=(--depth=1)
  shift 2

  clone_dir=$(mktemp -d)
  [ -n "$ref" ] && clone_args+=(-b "$ref")
  git clone "${clone_args[@]}" "$repo" "$clone_dir"

  for pkg in "$@"; do
    if [ -d "$clone_dir/$pkg" ]; then
      echo "Replace $pkg ,removed $dest/$pkg"
      rm -rf "${dest:?}/$pkg"
      cp -a "$clone_dir/$pkg" "$dest/"
    else
      echo "Skip $pkg（上游 $repo 中不存在）"
    fi
  done

  rm -rf "$clone_dir"
  echo "处理完成：$*"
}

# Replace Smartdns
git clone --depth=1 -b PikuZheng https://github.com/Ljzkirito/smartdns-openwrt package/smartdns-custom
remove_feed_duplicates package/smartdns-custom

# Replace luci-theme-argon
rm -rf feeds/luci/themes/luci-theme-argon && echo "removed feeds/luci/themes/luci-theme-argon"
git clone https://github.com/jerrykuku/luci-theme-argon.git feeds/luci/themes/luci-theme-argon
git -C feeds/luci/themes/luci-theme-argon checkout 1991a8e29ef6a086fb566517675edc85b1be629a

# Update golang latest version
rm -rf feeds/packages/lang/golang && echo "removed feeds/packages/lang/golang"
git clone --depth=1 https://github.com/sbwml/packages_lang_golang feeds/packages/lang/golang

# Update rust latest version
rm -rf feeds/packages/lang/rust
git clone https://github.com/sbwml/packages_lang_rust feeds/packages/lang/rust

# ---------------------------------------------------------------------------
# Additional packages (workflow input ADDITIONAL_PACKAGES)
# ---------------------------------------------------------------------------
# Each selected repository is cloned into its own folder under package/ (the
# build scans package/ recursively). Any package folder installed from feeds
# with the same name is removed, so the local copy is the only one.
ADDITIONAL_PACKAGES="${ADDITIONAL_PACKAGES:-none}"
ADDITIONAL_CONFIGS=()

# This script runs with ImmortalWrt/ as the working directory (the workflow
# cds there before calling it), but CONFIG_FILE is a file name under configs/
# in the Actions-MT7981 repo root. Resolve it once to an absolute path so
# sed/cat and the existence check below work regardless of the current
# directory.
WORKSPACE="${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CONFIG_PATH="$WORKSPACE/configs/$CONFIG_FILE"
[ -f "$CONFIG_PATH" ] || { echo "错误：找不到配置文件 $CONFIG_PATH" >&2; exit 0; }

case "$ADDITIONAL_PACKAGES" in
  helloworld)
    ADDITIONAL_CONFIGS+=(helloworld.config)
    git clone --depth=1 -b dev "$SSRP_REPO" package/helloworld
	# package/helloworld/shadowsocks-libev has a dependency on 'firewall4'
	rm -rf package/helloworld/shadowsocks-libev && echo "removed package/helloworld/shadowsocks-libev"
	replace_from_repo "$SBWML_REPO" package/helloworld v2ray-geodata kcptun shadowsocks-rust shadow-tls tuic-client naiveproxy
	remove_upx_calls package/helloworld/mihomo package/helloworld/xray-core
	remove_feed_duplicates package/helloworld
    ;;
  passwall)
    ADDITIONAL_CONFIGS+=(passwall.config)
    git clone --depth=1 "$PW1_REPO" package/passwall-luci
    git clone --depth=1 "$PWP_REPO" package/passwall-packages
    rm -rf package/passwall-packages/smartdns && echo "Removed passwall-packages/smartdns"
    rm -rf feeds/luci/applications/{luci-app-passwall,luci-app-passwall2}
    replace_from_repo "$SBWML_REPO" package/passwall-packages shadowsocks-rust shadow-tls shadowsocksr-libev
    remove_feed_duplicates package/passwall-packages
    ;;
  passwall2)
    ADDITIONAL_CONFIGS+=(passwall2.config)
    git clone --depth=1 "$PW2_REPO" package/passwall-luci
    git clone --depth=1 "$PWP_REPO" package/passwall-packages
    rm -rf package/passwall-packages/smartdns && echo "Removed passwall-packages/smartdns"
    rm -rf feeds/luci/applications/{luci-app-passwall,luci-app-passwall2}
    replace_from_repo "$SBWML_REPO" package/passwall-packages shadowsocks-rust shadow-tls shadowsocksr-libev
    remove_feed_duplicates package/passwall-packages
    ;;
  all-sbwml)
    ADDITIONAL_CONFIGS+=(helloworld.config passwall.config passwall2.config)
    git clone --depth=1 "$SBWML_REPO" package/helloworld
    # 用 fw876/helloworld 的 mosdns 覆盖 sbwml 源里的同名包
    replace_from_repo "$SSRP_REPO" package/helloworld mosdns
    rm -rf package/helloworld/{smartdns,dae,luci-app-dae,daed,luci-app-daed,luci-app-homeproxy,momo,luci-app-momo,nikki,luci-app-nikki,shadowsocks-libev}
    sed -i 's/libopenssl-legacy/libopenssl/g' package/helloworld/shadowsocksr-libev/Makefile
    remove_feed_duplicates package/helloworld
    ;;
  *)
    sed -i "/CONFIG_PACKAGE_kmod-tun/d" "$CONFIG_PATH"
    echo "Additional packages: none, removed kmod-tun in $CONFIG_PATH"
    ;;
esac

# Append the config fragments selected by the case branch above to CONFIG_PATH
# (already resolved to an absolute path), keeping the order they were listed
# in. The workflow later moves CONFIG_FILE to ImmortalWrt/.config, so this
# runs while the repo root is still reachable.
for cfg in "${ADDITIONAL_CONFIGS[@]}"; do
  CONFIG_FRAGMENT="$WORKSPACE/configs/$cfg"
  [ -f "$CONFIG_FRAGMENT" ] || { echo "错误：找不到配置文件 $CONFIG_FRAGMENT" >&2; exit 1; }
  printf '\n' >> "$CONFIG_PATH"
  echo "追加 $CONFIG_FRAGMENT 到 $CONFIG_PATH"
  cat "$CONFIG_FRAGMENT" >> "$CONFIG_PATH"
done
