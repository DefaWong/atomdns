# 一键安装（AtomDNS + 定制版 sing-box）

`scripts/install.sh` 会在一台机器上一次装好 AtomDNS 和定制版 sing-box，并把两边配好：AtomDNS 做唯一一次分流决策，sing-box 用 FakeIP 接住代理流量，按 AtomDNS 指定的出口转发。原理见 [native-singbox-integration.md](contracts/native-singbox-integration.md)。

## 用法

```sh
curl -fsSL https://raw.githubusercontent.com/DefaWong/atomdns/main/scripts/install.sh | sh
```

Alpine 默认没有 curl 和 bash，可以用自带的 wget 和 sh：

```sh
wget -qO- https://raw.githubusercontent.com/DefaWong/atomdns/main/scripts/install.sh | sh
```

脚本是 POSIX `sh`，`| bash` 也能用。必须以 root 运行。

| 环境变量 | 默认值 | 说明 |
| --- | --- | --- |
| `ATOMDNS_RELEASE` | `latest` | 要安装的 Release tag |
| `ATOMDNS_REPO` | `DefaWong/atomdns` | 下载 Release 的仓库 |
| `ATOMDNS_ASSETS` | 空 | 本地目录，放好全部资产后不再下载（测试用） |
| `ATOMDNS_ROOT` | `/cus/atomdns` | AtomDNS 配置根 |
| `TPROXY_PORT` | `7895` | sing-box TProxy 端口 |

## 支持的系统

- x86_64（amd64）。两个系统用的都是静态 musl 版 AtomDNS，以及 CGO 关闭的静态 sing-box。
- Alpine（OpenRC）：用 apk 安装依赖。
- Debian 系（Debian、Ubuntu 等，systemd）：用 apt 安装依赖。

UDP 53 端口被其它程序占用（systemd-resolved 的 stub、dnsmasq 等）时，脚本会退出，请先释放端口再重跑。

## 装了什么

| 内容 | 位置 |
| --- | --- |
| 程序 | `/usr/local/bin/atomdns`、`/usr/local/bin/sing-box` |
| AtomDNS 配置 | `/cus/atomdns`（来自 `config_rust.zip`，`ui/main` 换成本 Release 的 WebUI） |
| AtomDNS 设置 | `/cus/atomdns/webinfo/settings.json`（权限 600）：`main_proxy` 指向 sing-box 的 mixed 入口，sing-box API 的地址和密钥 |
| sing-box 配置 | `/etc/sing-box/config.json`（权限 600），状态在 `/var/lib/sing-box` |
| TProxy 规则 | `/usr/local/lib/atomdns/tproxy.sh`，由 sing-box 服务在启动时加载、停止时撤销 |
| 服务 | OpenRC：`/etc/init.d/{sing-box,atomdns}`；systemd：`/etc/systemd/system/{sing-box,atomdns}.service`；都设为开机自启 |

sing-box API 的密钥是安装时随机生成的，同时写进 sing-box 配置和 AtomDNS 设置。

端口：

| 端口 | 程序 | 用途 |
| --- | --- | --- |
| `:53` | AtomDNS | DNS |
| `:9099` | AtomDNS | WebUI 和 API |
| `127.0.0.1:6666` | sing-box | FakeIP DNS（AtomDNS 的 `nocnfake` 上游） |
| `127.0.0.1:9666` | sing-box | mixed 代理（AtomDNS 的 `main_proxy`） |
| `127.0.0.1:9090` | sing-box | Clash API（带密钥） |
| `:7895` | sing-box | TProxy 入口 |

新装的 sing-box 配置里，`proxy` 分组只有 `direct`。在 WebUI 的 sing-box 页面添加节点或订阅之后，分组会按 AtomDNS 的节点列表重建。

## 主路由怎么配

先给这台机器固定 IP（静态地址或 DHCP 保留）：客户端的 DNS 和 FakeIP 路由都指向它，IP 变了两者都会失效。

1. 让客户端用这台机器做 DNS 服务器。
2. 把 FakeIP 网段 `198.18.0.0/15` 和 `fc00::/18` 路由到这台机器，可以用静态路由，也可以用策略路由。

到达这台机器、目标是 FakeIP 的 TCP/UDP 流量，会被 nftables 的 TProxy 交给 sing-box：

- `table inet atomdns_tproxy`，打 fwmark `0x1d`。
- 策略路由走表 `233`。

sing-box 按 FakeIP 反查出域名和绑定的出口：有绑定就直接走这个出口，没有就走 `proxy` 分组。本机自己发出的流量不经过 TProxy。

## 重复运行（升级）

再跑一次脚本会：

- 更新两个程序、WebUI、服务文件和 TProxy 脚本。
- 保留 `/cus/atomdns` 下已有的配置、`webinfo/settings.json` 和 `/etc/sing-box/config.json`，sing-box API 的密钥继续沿用。

AtomDNS 的在线更新源是 `DefaWong/atomdns` 的 Release（`update/mod.rs`）。在线更新只更新 AtomDNS 和 WebUI，sing-box 要重跑安装脚本才会更新。

## 卸载

```sh
# Alpine
rc-service atomdns stop; rc-service sing-box stop
rc-update del atomdns default; rc-update del sing-box default
rm -f /etc/init.d/atomdns /etc/init.d/sing-box
# Debian 系
systemctl disable --now atomdns sing-box
rm -f /etc/systemd/system/atomdns.service /etc/systemd/system/sing-box.service && systemctl daemon-reload
# 两种系统都要执行
rm -rf /usr/local/bin/atomdns /usr/local/bin/sing-box /usr/local/lib/atomdns
# 配置和数据，确认不再需要后再删
rm -rf /cus/atomdns /etc/sing-box /var/lib/sing-box
```

停止 sing-box 服务时 TProxy 规则就已经撤销了。

## Release 资产

脚本从 `https://github.com/<repo>/releases/<latest|download/tag>/` 下载以下文件，按 `SHA256SUMS` 校验：

| 资产 | 来源 |
| --- | --- |
| `atomdns-linux-amd64-musl.tar.gz` | `VARIANTS="amd64 amd64-musl" scripts/build-rust-release.sh vX.Y.Z release/rust`，或同样参数的静态 musl 构建 |
| `atomdns-webui.tar.gz` | `npm run build:package`（`webui-log`），或上面同一次发布构建 |
| `config_rust.zip` | 全新安装配置包（见 [release.md](release.md)“带配置包的发版顺序”第 7 步） |
| `sing-box-linux-amd64.tar.gz` | 由下面的打包脚本从定制版 sing-box（`DefaWong/sing-box`）编译 |
| `SHA256SUMS` | 由打包脚本生成 |

```bash
ATOMDNS_MUSL_TGZ=release/rust/atomdns-linux-amd64-musl.tar.gz \
WEBUI_TGZ=release/rust/atomdns-webui.tar.gz \
CONFIG_ZIP=/path/to/config_rust.zip \
SINGBOX_SRC=/path/to/sing-box \
  scripts/package-installer-assets.sh release/installer
```

sing-box 用它仓库 `release/DEFAULT_BUILD_TAGS_OTHERS` 里的编译标签，版本号形如 `1.14.4-reF1nd-atomdns.<提交>`。

打包脚本只构建不发布。在 `DefaWong/atomdns` 建 Release 时，上传 `release/installer` 下的全部文件，再加上 `atomdns-update-manifest.json` 和在线更新要用的程序包。建 Release 属于对外发布，需要先确认。
