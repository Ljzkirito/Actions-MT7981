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
      -exec sh -c '[ -f "$1/Makefile" ] && rm -rfv "$1"' _ {} \; 2>/dev/null || true
  done
  # Drop the symlinks that "feeds install -a" left pointing at the removed dirs.
  find package/feeds -xtype l -delete 2>/dev/null || true
}

# Replace Smartdns
# Clone the custom repo into a dedicated folder under package/ (which the build
# scans recursively), then delete the same-named package folders installed
# from feeds so the local copy is the only one.
git clone --depth=1 -b PikuZheng https://github.com/Ljzkirito/smartdns-openwrt package/smartdns-openwrt
remove_feed_duplicates package/smartdns-openwrt

# Replace luci-theme-argon
rm -rfv feeds/luci/themes/luci-theme-argon
git clone https://github.com/jerrykuku/luci-theme-argon.git feeds/luci/themes/luci-theme-argon
git -C feeds/luci/themes/luci-theme-argon checkout 1991a8e29ef6a086fb566517675edc85b1be629a

#https://github.com/immortalwrt/packages/issues/1607
#Fix Rust compilation failure（21.02 no rust)
if [ -f feeds/packages/lang/rust/Makefile ]; then
  sed -i 's/--set=llvm\.download-ci-llvm=true/--set=llvm.download-ci-llvm=false/' feeds/packages/lang/rust/Makefile
fi

# Update golang latest version
rm -rfv feeds/packages/lang/golang
git clone --depth=1 https://github.com/sbwml/packages_lang_golang feeds/packages/lang/golang

# ---------------------------------------------------------------------------
# Additional packages (workflow input ADDITIONAL_PACKAGES)
# ---------------------------------------------------------------------------
# Each selected repository is cloned into its own folder under package/ (the
# build scans package/ recursively). Any package folder installed from feeds
# with the same name is removed, so the local copy is the only one.
ADDITIONAL_PACKAGES="${ADDITIONAL_PACKAGES:-none}"

clone_passwall_packages() {
  git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/passwall-packages
  # This build already provides its own SmartDNS package; do not let the
  # passwall dependency tree introduce a second package with the same name.
  rm -rfv package/passwall-packages/smartdns
  remove_feed_duplicates package/passwall-packages
}

# ---------------------------------------------------------------------------
# Replace / fill in individual packages from sbwml/openwrt_helloworld
# ---------------------------------------------------------------------------
# Usage: fix_depends_packages {dir1,dir2}   (brace expansion, or space-separated)
#   Every name must be a directory of sbwml/openwrt_helloworld, e.g.
#   v2ray-geodata (which provides v2ray-geoip/v2ray-geosite) and
#   shadowsocks-rust. The repo is cloned once into package/depends-packages;
#   afterwards every directory that was not requested is deleted, so the clone
#   can never shadow the packages the main repo already ships. Same-named
#   directories in other local clones and in feeds are removed too, i.e. the
#   sbwml copy replaces them.
fix_depends_packages() {
  local dest="package/depends-packages"
  local -a keep=() missing=()
  local want dir name other

  if [ $# -eq 0 ]; then
    echo "警告：fix_depends_packages 未收到包目录，跳过" >&2
    return 0
  fi

  rm -rf "$dest"
  git clone --depth=1 https://github.com/sbwml/openwrt_helloworld "$dest" || {
    echo "错误：无法克隆 sbwml/openwrt_helloworld" >&2
    return 1
  }

  # Only directory names are accepted: no package/Makefile lookup.
  for want in "$@"; do
    if [ -d "$dest/$want" ]; then
      keep+=("$want")
      echo "保留 $want"
    else
      missing+=("$want")
    fi
  done

  if [ ${#missing[@]} -gt 0 ]; then
    echo "错误：sbwml/openwrt_helloworld 中没有这些包目录：${missing[*]}" >&2
    return 1
  fi

  # Delete every directory that is not one of the resolved packages (including
  # hidden ones such as .git, so the tree only contains what we asked for).
  for dir in "$dest"/*/ "$dest"/.[!.]*/; do
    [ -d "$dir" ] || continue
    name=$(basename "$dir")
    case " ${keep[*]} " in
      *" $name "*) ;;
      *)
        echo "删除未选中的包目录：$dir"
        rm -rf "$dir"
        ;;
    esac
  done

  # The sbwml copy replaces same-named packages of other local clones and feeds.
  for want in "${keep[@]}"; do
    for other in package/*/; do
      [ "${other%/}" = "$dest" ] && continue
      if [ -d "$other$want" ]; then
        echo "删除同名目录：$other$want"
        rm -rf "$other$want"
      fi
    done
  done
  remove_feed_duplicates "$dest"

  echo "从 sbwml/openwrt_helloworld 引入：${keep[*]}"
}

ADDITIONAL_CONFIG=""
case "$ADDITIONAL_PACKAGES" in
  none)
    echo "Additional packages: none, skipping"
    ;;
  helloworld)
    ADDITIONAL_CONFIG="configs/helloworld.config"
    git clone --depth=1 -b dev https://github.com/fw876/helloworld package/helloworld
    # 21.02 没有 rust 工具链：用 sbwml 的预编译 shadowsocks-rust 替换 helloworld
    # 的源码版（否则 shadowsocks-rust 的 Makefile 会因为找不到 rust-package.mk
    # 而在解析阶段失败）；v2ray-geodata 提供 v2ray-geoip / v2ray-geosite。
    # 花括号是 shell 展开，等价于 fix_depends_packages v2ray-geodata shadowsocks-rust
    fix_depends_packages {v2ray-geodata,shadowsocks-rust}
    remove_feed_duplicates package/helloworld
    ;;
  passwall)
    ADDITIONAL_CONFIG="configs/passwall.config"
    git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall package/openwrt-passwall
    remove_feed_duplicates package/openwrt-passwall
    clone_passwall_packages
    ;;
  passwall2)
    ADDITIONAL_CONFIG="configs/passwall2.config"
    git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall2 package/openwrt-passwall2
    remove_feed_duplicates package/openwrt-passwall2
    clone_passwall_packages
    ;;
  all-sbwml)
    ADDITIONAL_CONFIG="configs/all-sbwml.config"
    git clone --depth=1 https://github.com/sbwml/openwrt_helloworld package/helloworld
    remove_feed_duplicates package/helloworld
    # Keep the custom SmartDNS cloned above instead of sbwml's copy.
    rm -rf package/helloworld/smartdns
    ;;
  *)
    echo "警告：未知的 Additional packages 选项 '$ADDITIONAL_PACKAGES'，跳过" >&2
    ;;
esac

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
