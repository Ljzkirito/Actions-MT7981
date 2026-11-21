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
SMARTDNS_DIR=package/smartdns-openwrt
rm -rf "$SMARTDNS_DIR"
git clone --depth=1 -b PikuZheng https://github.com/Ljzkirito/smartdns-openwrt "$SMARTDNS_DIR"

remove_feed_duplicates "$SMARTDNS_DIR"

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
  git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/openwrt-passwall-packages
  remove_feed_duplicates package/openwrt-passwall-packages
  # This build already provides its own SmartDNS package; do not let the
  # passwall dependency tree introduce a second package with the same name.
  rm -rf package/openwrt-passwall-packages/smartdns
}

case "$ADDITIONAL_PACKAGES" in
  none|"")
    echo "Additional packages: none, skipping"
    ;;
  helloworld)
    git clone --depth=1 https://github.com/fw876/helloworld package/helloworld
    remove_feed_duplicates package/helloworld
    ;;
  passwall)
    git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall package/openwrt-passwall
    remove_feed_duplicates package/openwrt-passwall
    clone_passwall_packages
    ;;
  passwall2)
    git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall2 package/openwrt-passwall2
    remove_feed_duplicates package/openwrt-passwall2
    clone_passwall_packages
    ;;
  all-sbwml)
    git clone --depth=1 https://github.com/sbwml/openwrt_helloworld package/helloworld
    remove_feed_duplicates package/helloworld
    # Keep the custom SmartDNS cloned above instead of sbwml's copy.
    rm -rf package/helloworld/smartdns
    ;;
  *)
    echo "警告：未知的 Additional packages 选项 '$ADDITIONAL_PACKAGES'，跳过" >&2
    ;;
esac
