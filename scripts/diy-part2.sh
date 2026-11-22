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
# Remove every upx invocation from the package Makefiles
# ---------------------------------------------------------------------------
# Several packages compress their binaries with upx at build time (xray-core
# and mihomo in helloworld, for example). The compressed binaries are bigger
# pain than they are worth: upx builds a host tool first, some of its outputs
# fail on certain kernels/filesystems, and the runtime decompression hides the
# real binary size. This deletes the upx command lines from every Makefile in
# package/ and feeds/ while leaving the upx package itself untouched, so the
# uncompressed binary that was already copied next to it is installed instead.
remove_upx_calls() {
  local root file count=0
  # "$(STAGING_DIR_HOST)/bin/upx ..." and a bare "upx -..." invocation.
  local pat='STAGING_DIR[^[:space:]]*/bin/upx|(^|[[:space:];:()])upx[[:space:]]+-'

  for root in package feeds; do
    [ -d "$root" ] || continue
    while IFS= read -r file; do
      # Never touch the upx package that provides the host tool itself.
      case "$file" in
        */upx/Makefile|*/upx-*/Makefile|*/upx_*/Makefile) continue ;;
      esac
      grep -qE "$pat" "$file" || continue
      # Drop the upx command line and the "upx/host" build dependency.
      sed -i -E -e "\#$pat#d" \
               -e '/^[[:space:]]*PKG_BUILD_DEPENDS/ s#[[:space:]]+upx/host##g' "$file"
      echo "移除 upx 命令：$file"
      count=$((count + 1))
    done < <(find "$root" -type f -name Makefile)
  done
  echo "已清理 $count 个 Makefile 中的 upx 命令"
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
ADDITIONAL_CONFIG=""
case "$ADDITIONAL_PACKAGES" in
  none)
    echo "Additional packages: none, skipping"
    ;;
  helloworld)
    ADDITIONAL_CONFIG="configs/helloworld.config"
    git clone --depth=1 -b dev https://github.com/fw876/helloworld package/helloworld
	# package/helloworld/shadowsocks-libev has a dependency on 'firewall4'
	rm -rf package/helloworld/shadowsocks-libev && echo "removed package/helloworld/shadowsocks-libev"
	# 要替换的包，按需增删这一行即可
	replace=(v2ray-geodata kcptun shadowsocks-rust shadow-tls tuic-client naiveproxy)
	sbwml_dir=$(mktemp -d)
	git clone --depth=1 https://github.com/sbwml/openwrt_helloworld "$sbwml_dir"
	# 源里有就替换，没有就跳过，不报错
	for p in "${replace[@]}"; do
	  if [ -d "$sbwml_dir/$p" ]; then
		echo "Replace $p ,removed package/helloworld/$p"
		rm -rf "package/helloworld/$p"
		cp -a "$sbwml_dir/$p" package/helloworld/
	  else
		echo "Skip $p（sbwml 源中不存在）"
	  fi
	done
	rm -rf "$sbwml_dir"
	echo "处理完成：${replace[*]}"
	remove_feed_duplicates package/helloworld
    ;;
  passwall)
    ADDITIONAL_CONFIG="configs/passwall.config"
    git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall package/luci-passwall
    git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/passwall-packages
    rm -rf package/passwall-packages/smartdns
    rm -rf feeds/luci/applications/luci-app-passwall
    remove_feed_duplicates package/passwall-packages
    ;;
  passwall2)
    ADDITIONAL_CONFIG="configs/passwall2.config"
    git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall2 package/luci-passwall2
    git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/passwall-packages
    rm -rf package/passwall-packages/smartdns
    rm -rf feeds/luci/applications/luci-app-passwall
    remove_feed_duplicates package/passwall-packages
    ;;
  all-sbwml)
    ADDITIONAL_CONFIG="configs/all-sbwml.config"
    git clone --depth=1 https://github.com/sbwml/openwrt_helloworld package/helloworld
    mosdns_dir=$(mktemp -d)
	git clone --depth=1 https://github.com/fw876/helloworld "$mosdns_dir"
	if [ -d "$mosdns_dir/mosdns" ]; then
	  rm -rf package/helloworld/mosdns && echo "removed package/helloworld/mosdns"
	  cp -a "$mosdns_dir/mosdns" package/helloworld/
	else
	  echo "跳过 mosdns（fw876/helloworld 中不存在）"
	fi
    rm -rf package/helloworld/smartdns && echo "removed package/helloworld/smartdns"
    rm -rf "$mosdns_dir"
    remove_feed_duplicates package/helloworld
    ;;
  *)
    echo "警告：未知的 Additional packages 选项 '$ADDITIONAL_PACKAGES'，跳过" >&2
    ;;
esac

# Strip upx from every package Makefile (cloned repositories and feeds).
remove_upx_calls

# Append the matching config fragment to CONFIG_FILE. The workflow later moves
# CONFIG_FILE to ImmortalWrt/.config, so this runs while the repo root is still
# reachable through GITHUB_WORKSPACE.
if [ -n "$ADDITIONAL_CONFIG" ]; then
  WORKSPACE="${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
  CONFIG_PATH="$WORKSPACE/$CONFIG_FILE"
  CONFIG_FRAGMENT="$WORKSPACE/$ADDITIONAL_CONFIG"
  [ -f "$CONFIG_PATH" ] || {
    echo "错误：找不到配置文件 $CONFIG_PATH" >&2
    exit 1
  }
  [ -f "$CONFIG_FRAGMENT" ] || {
    echo "错误：找不到配置文件 $CONFIG_FRAGMENT" >&2
    exit 1
  }
  echo >> "$CONFIG_PATH"
  echo "追加 $CONFIG_FRAGMENT 到 $CONFIG_PATH"
  cat "$CONFIG_FRAGMENT" >> "$CONFIG_PATH"
fi
