# Actions-MT7981

[![Build mt7981](https://github.com/Ljzkirito/Actions-MT7981/actions/workflows/Build_mt7981.yml/badge.svg)](https://github.com/Ljzkirito/Actions-MT7981/actions/workflows/Build_mt7981.yml)

使用 GitHub Actions 云编译 **ImmortalWrt**（MediaTek MT7981 / Filogic 820）固件。一次构建同时产出 **360 T7** 与 **小米 WR30U** 两台设备的固件，并自动发布到 Releases。

- 源码：[padavanonly/immortalwrt-mt798x-6.6](https://github.com/padavanonly/immortalwrt-mt798x-6.6)、[Yuzhii0718/immortalwrt-mt798x-6.6-padavanonly](https://github.com/Yuzhii0718/immortalwrt-mt798x-6.6-padavanonly)，分支 `openwrt-24.10-6.6`。
- 基于 ImmortalWrt 24.10 + MTK SDK（Linux 6.6 内核、MTK 闭源 Wi-Fi 驱动），**不是** OpenWrt 主线，请勿与官方 ImmortalWrt/OpenWrt 固件混用。
- 工作流派生自 [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt)。

## 固件特性

- **双源码可选**：`padavanonly` 原版或 `Yuzhii0718` 分支（分支均为 `openwrt-24.10-6.6`）。
- **双设备单次构建**：同时生成 360 T7 与 WR30U 的 sysupgrade 固件。
- **可配固件选项**：LAN IP/掩码、256M 内存压缩、zram-swap、IPTV（msd_lite + omcproxy）、MTK HQoS。
- **默认基础包**：SmartDNS、Argon 主题、UPnP、WOL、定时重启等。
- **构建加速**：可选 `cachewrtbuild` 缓存 toolchain。
- **Rust 包免编译**：`shadowsocks-rust`、`shadow-tls`、`tuic-client` 等需要 Rust 交叉编译的包，构建时替换为 [sbwml/openwrt_helloworld](https://github.com/sbwml/openwrt_helloworld) 提供的预编译包，省去在 CI 上编译 Rust 的时间。
- **自动发布**：Release 标签为时间戳，附带构建信息与 `build.config`；自动清理旧 Release 与旧 workflow 运行记录。

## 支持的设备

| 设备 | 设备 profile | 分区 |
| --- | --- | --- |
| 360 T7（Qihoo） | `qihoo-360-t7-108M` | 108M |
| 小米 WR30U | `xiaomi_mi-router-wr30u-112m` | 112M |

> **刷机前提**：仅适用于 108M/112M 大分区（stock/custom partition layout + MTK-NMBM）。请先刷入配套的 BL2 + U-Boot：
> - [hanwckf/bl-mt798x](https://github.com/hanwckf/bl-mt798x)
> - [Yuzhii0718/bl-mt798x-dhcpd](https://github.com/Yuzhii0718/bl-mt798x-dhcpd)（Variant：`default`，Version：`SP1`或`2025`）

## 快速开始

1. Fork 本仓库。
2. 在 Fork 后的仓库进入 **Actions** 页，启用 workflows。
3. 选择左侧 **Build mt7981** → **Run workflow**，按需填写参数后运行。
4. 构建完成后在 **Releases** 下载固件。

工作流**仅支持手动触发**（`workflow_dispatch`）。

## 输入参数

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `REPO` | `Yuzhii0718` | 源码仓库：`padavanonly` 或 `Yuzhii0718` |
| `ADDITIONAL_PACKAGES` | `none` | `none` / `helloworld` / `passwall` / `passwall2` / `all-sbwml` |
| `LanIP` | `192.168.6.1/24` | LAN 地址（CIDR）。仅接受 RFC 1918 私有地址，前缀需在 `/8`、`/12`、`/16`（按网段）到 `/30` 之间，且不能是网络/广播地址；非法输入会告警并回退默认值 |
| `MEMORY_SHRINK_AGGRESS` | `true` | `CONFIG_MTK_MEMORY_SHRINK_AGGRESS`，256M 内存设备建议开启 |
| `ZRAM_SWAP` | `false` | 安装 `zram-swap`（自动带上 `kmod-zram`） |
| `IPTV_PACKAGES` | `false` | 安装 `luci-app-msd_lite` + `luci-app-omcproxy` |
| `MTKHQOS` | `false` | 安装 `luci-app-eqos-mtk` + `mtkhqos_util` |
| `Cache` | `false` | 使用 `HiGarfield/cachewrtbuild` 缓存 toolchain |

## 构建流程

| 步骤 | 内容 | 超时 |
| --- | --- | --- |
| Check Server Performance | 打印 CPU/内存/磁盘信息 | - |
| Initialization environment | `scripts/init.sh` 安装依赖：GCC 13、LLVM 23、Go 1.27、Node 24、UPX 5.3.0、`po2lmo`、`padjffs2` 等；仅支持 Ubuntu 24.04 (noble) | 30 min |
| Clone source code | `git clone -b openwrt-24.10-6.6 --depth=1` 到 `/workdir/ImmortalWrt` 并软链 | - |
| Apply patches | 按文件名顺序对 `patch/<REPO>/*.patch` 执行 `patch -p1 --batch --forward` | - |
| Cache Toolchain | 仅 `Cache=true` 时执行 | - |
| Load custom feeds (DIY_P1) | `scripts/diy-part1.sh`：用 `odhcp6c` + `odhcpd-ipv6only` 替换 `ipv6helper`，并关闭 LAN DHCPv6（仅保留 RA/SLAAC） | - |
| Update / Install feeds | `./scripts/feeds update -a && ./scripts/feeds install -a` | - |
| Load custom configuration (DIY_P2) | `scripts/diy-part2.sh`：替换 SmartDNS、Argon 主题、Go/Rust 版本，克隆所选插件集并追加配置片段 | - |
| Configure firmware options | `scripts/configure-firmware.sh`：重写固件选项并替换 `config_generate` 中的 LAN IP/掩码 | - |
| Download package | 复制 `.config`，`make defconfig`，`make download -j8`，清理 `dl/` 中小于 1KB 的失败下载 | 90 min |
| Compile the firmware | `make -j$(nproc)`，失败时回退 `make -j1 V=s` | 180 min |
| Organize & Upload | 删除 `bin/.../packages`，上传固件目录 artifact | - |
| Generate release tag | 标签 `YYYY.MM.DD-HHMM`，生成 `release.txt`（含源码仓库/分支/commit、配置、内核版本、输入参数、BL2/U-Boot 说明） | - |
| Upload firmware to release | 上传 `immortalwrt*.bin` 与 `build.config` | - |
| Remove old Releases and Workflows | 保留最近 10 个 Release，删除 10 天前的 workflow 运行记录 | - |

## 构建产物

- **Artifact**
  - `ImmortalWrt_firmware_mt7981_<YYYYMMDDHHMM>`：固件目录（默认）。
  - `ImmortalWrt_bin_mt7981_<YYYYMMDDHHMM>`：完整 `bin/`，仅当仓库变量 `UPLOAD_BIN_DIR=true` 时上传（默认 `false`）。
- **Release**
  - 标签：`YYYY.MM.DD-HHMM`。
  - 资产：`immortalwrt*.bin`、`build.config`（本次构建使用的完整配置，便于复现）。
  - 说明：包含内核版本（从 `include/kernel-6.6` 解析）、源码 commit 链接、各输入参数与 BL2/U-Boot 搭配建议。

## 仓库结构

```
.
├── .github/workflows/Build_mt7981.yml  # 唯一的工作流，手动触发
├── .gitattributes                      # 统一 LF 行尾
├── configs/
│   ├── mt7981-Yuzhii0718.config        # Yuzhii0718 源码的构建配置
│   ├── mt7981-padavanonly.config       # padavanonly 源码的构建配置
│   ├── helloworld.config               
│   ├── passwall.config                 
│   └── passwall2.config                
├── patch/
│   ├── Yuzhii0718/*.patch              # 选择 Yuzhii0718 时按序应用
│   ├── padavanonly/*.patch             # 选择 padavanonly 时按序应用
│   └── delete/*.patch                  # 已撤下的补丁，仅存档，不参与构建
├── scripts/
│   ├── init.sh                         # 构建依赖安装（Ubuntu 24.04、root）
│   ├── diy-part1.sh                    # feeds update 之前执行
│   ├── diy-part2.sh                    # feeds install 之后执行
│   └── configure-firmware.sh           # 固件选项 / LAN IP 处理
└── LICENSE                             # MIT
```

### configs 说明

`mt7981-*.config` 是**差分式配置**（类似 `diffconfig.sh` 的输出），只记录与上游默认值的差异，最终由 `make defconfig` 补全。因此其中看不到 `dnsmasq`、`firewall` 等默认包属于正常现象。

### 补丁说明

| 目录 | 补丁 | 作用 |
| --- | --- | --- |
| `Yuzhii0718` | `001` | iwinfo mtk：修复 UCI 字符串 use-after-free |
| | `002` | iwinfo mtk：修复扫描缓冲区长度与 SSID 越界 |
| | `003` | mt_wifi：Supported Channels IE 过大时不再拒绝关联 |
| `padavanonly` | `001` | autocore：增加读取交换机端口状态的权限 |
| | `002` | autocore：修复 issue #353，GSW 交换机改用 `swconfig` 读取每端口流量 |
| | `003` | mt_wifi rrm：修复 SSID 格式化越界（`snprintf`） |
| | `004` | 将 360 T7 设备名改为 Qihoo |
| `delete` | `000` | PPP 拆除时轮询等待 `wan_6` 消失（已撤下） |
| | `003` | 修复 RRM `snprintf` 读越界（已撤下，由 `padavanonly/003` 取代） |

## 自定义指南

### 1. 修改默认配置

直接编辑 `configs/mt7981-<REPO>.config`，或在本地 `make menuconfig` 后执行 `./scripts/diffconfig.sh > seed.config`，将差异合并进去。

```bash
git clone -b openwrt-24.10-6.6 --depth=1 https://github.com/Yuzhii0718/immortalwrt-mt798x-6.6-padavanonly.git
cd immortalwrt-mt798x-6.6-padavanonly
./scripts/feeds update -a && ./scripts/feeds install -a
cp defconfig/mt7981-ax3000.config .config
make menuconfig && make defconfig
./scripts/diffconfig.sh > seed.config
```

### 2. 换包源 / 增删插件

`scripts/diy-part2.sh` 顶部集中了所有上游地址，改这里即可切换镜像或分支。

脚本提供的辅助函数：

- `replace_from_repo <repo> <dest> <pkg>...`：用上游同名包覆盖本地包，可配合 `REPO_REF` 指定分支/标签。
- `remove_feed_duplicates <dir>`：删除 feeds 中与本地克隆重名的包及失效软链。
- `remove_upx_calls <dir>...`：删除 Makefile 中的 `upx` 调用与 `upx/host` 依赖（空间足够，无需upx压缩）。

### 3. 新增补丁

把 `git format-patch` 生成的补丁放进 `patch/<REPO>/`，以 `NNN-描述.patch` 命名（按文件名排序应用）。补丁必须能 `patch -p1` 应用；应用失败会因 `set -e` 直接终止构建。

### 4. 自定义 feeds

在仓库根目录放置 `feeds.conf.default`，工作流会在执行 `diy-part1.sh` 前用它替换上游同名文件。

### 5. 切换产物策略

编辑 `.github/workflows/Build_mt7981.yml` 的 `env`：

- `UPLOAD_BIN_DIR: true`：额外上传完整 `bin/`。
- `UPLOAD_RELEASE: false`：只上传 artifact，不发布 Release。
- `REPO_BRANCH`：上游分支（需与源码仓库实际分支一致）。

## 注意事项

1. **仅手动触发**：工作流没有 `push`/`schedule` 触发器。
2. **构建时长**：全量编译通常 1.5–2.5 小时，插件越多越慢；编译步骤上限 180 分钟。
3. **首次登录**：默认 LAN 为 `192.168.6.1`，root 密码为空，请首次登录后立即设置。
4. **固件不通用**：ImmortalWrt 24.10 + Linux 6.6 内核 + 闭源 Wi-Fi 驱动，仅适配上述两台设备及对应 U-Boot/分区布局。
5. **上游漂移**：feeds、插件仓库或分支变更可能导致构建失败，需同步更新 `diy-part2.sh` 中的地址/提交。
6. **Release 清理**：仅保留最近 10 个 Release；更早的固件请自行备份。

## 参考与致谢

- [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt) 与[中文教程](https://p3terx.com/archives/build-openwrt-with-github-actions.html)
- [padavanonly/immortalwrt-mt798x-6.6](https://github.com/padavanonly/immortalwrt-mt798x-6.6)、[Yuzhii0718/immortalwrt-mt798x-6.6-padavanonly](https://github.com/Yuzhii0718/immortalwrt-mt798x-6.6-padavanonly)
- [sbwml/openwrt_helloworld](https://github.com/sbwml/openwrt_helloworld)、[fw876/helloworld](https://github.com/fw876/helloworld)
- [Openwrt-Passwall](https://github.com/Openwrt-Passwall)、[jerrykuku/luci-theme-argon](https://github.com/jerrykuku/luci-theme-argon)
- [Ljzkirito/smartdns-openwrt](https://github.com/Ljzkirito/smartdns-openwrt)（`PikuZheng` 分支）
- [HiGarfield/cachewrtbuild](https://github.com/HiGarfield/cachewrtbuild)、[ophub/delete-releases-workflows](https://github.com/ophub/delete-releases-workflows)
- [softprops/action-gh-release](https://github.com/softprops/action-gh-release)、[actions/upload-artifact](https://github.com/actions/upload-artifact)
- [OpenWrt](https://github.com/openwrt/openwrt)、[ImmortalWrt](https://github.com/immortalwrt/immortalwrt)
- 差分配置思路：[coolsnowwolf/lede#2288](https://github.com/coolsnowwolf/lede/issues/2288)
- 磁盘清理： [klttr/ActionsBuildOpenWRT](https://github.com/klttr/ActionsBuildOpenWRT)

## License

[MIT](LICENSE) © 2023 Ljzkirito；工作流骨架基于 [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt)（MIT）。
