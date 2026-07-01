# 🚀 TCP/UDP 网络深度调优脚本

> 一键优化 VPS 作为网络中转服务器的内核参数、拥塞控制、缓冲区与连接跟踪，专为跨境高丢包/高延迟链路设计。
>
> 本项目基于 [666shen/tcp-dashboard](https://github.com/666shen/tcp-dashboard) 改进，修复了原版多处 bug 并补充了关键调优参数。

![Shell](https://img.shields.io/badge/Shell-Bash-green?logo=gnubash&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue)
![Platform](https://img.shields.io/badge/Platform-Linux%204.9%2B-orange)

---

## 📋 功能概览

| 模块 | 说明 |
|------|------|
| **IPv4 优先解析** | 通过 `gai.conf` 将 DNS 解析优先级设为 IPv4，避免 IPv6 默认路由绕路导致的握手卡顿 |
| **BBR + FQ** | 启用 Google BBR 拥塞控制 + Fair Queue 队列调度，降低跨境丢包重传、提升单线程吞吐 |
| **生产级内核调优** | 动态计算缓冲区（基于总内存 5%）、扩容连接队列、开启 IP 转发、调优 conntrack 连接跟踪表 |
| **网卡多核分发 (RPS)** | 将网卡软中断从单核分发到所有 CPU 核心，消除 SoftIRQ 瓶颈 |
| **一键回退** | 清理所有独立配置文件，将内存参数恢复为系统默认值 |

## ✨ 核心调优参数一览

<details>
<summary>点击展开完整参数列表</summary>

```
# 拥塞控制
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# IP 转发（中转必须）
net.ipv4.ip_forward = 1

# 连接队列
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535

# TCP 缓冲区（动态计算，此处为示例值）
net.core.rmem_max = 53687091        # 总内存 5%
net.core.wmem_max = 53687091
net.ipv4.tcp_rmem = 4096 87380 53687091
net.ipv4.tcp_wmem = 4096 65536 53687091

# UDP 缓冲区（Hysteria2/QUIC）
net.ipv4.udp_mem = 65536 131072 262144

# 跨境链路专项
net.ipv4.tcp_notsent_lowat = 16384  # 降低 TTFB
net.ipv4.tcp_mtu_probing = 1       # 解决 PMTUD 黑洞
net.ipv4.tcp_ecn = 2               # 被动响应 ECN，不主动请求
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_fastopen = 3

# Conntrack 连接跟踪（动态计算）
net.netfilter.nf_conntrack_max = 动态
net.netfilter.nf_conntrack_tcp_timeout_established = 7200

# 文件句柄
* soft nofile 1048576
* hard nofile 1048576
```

</details>

---

## 🛠️ 部署方法

### 方法一：GitHub Raw 链接（推荐）

```bash
bash <(curl -sL https://raw.githubusercontent.com/Madhatter2099/TCP-Optimize/main/tcp.sh)
```

> [!TIP]
> 安装后，脚本会自动保存到 `/usr/local/bin/tcp.sh` 并创建快捷命令。以后只需输入 `t` 即可打开面板。

### 方法二：jsDelivr CDN 加速（备用）

[jsDelivr](https://www.jsdelivr.com/) 是 GitHub 的全球 CDN 镜像，当 `raw.githubusercontent.com` 不可达时使用：

```bash
bash <(curl -sL https://cdn.jsdelivr.net/gh/Madhatter2099/TCP-Optimize@main/tcp.sh)
```

### 方法三：手动下载

```bash
wget -O /usr/local/bin/tcp.sh https://raw.githubusercontent.com/Madhatter2099/TCP-Optimize/main/tcp.sh
chmod +x /usr/local/bin/tcp.sh
ln -sf /usr/local/bin/tcp.sh /usr/local/bin/t
t
```

---

## 📖 使用说明

### 交互式面板

安装完成后，输入 `t` 打开面板：

```
==================================================
         TCP/UDP 网络深度调优与性能看板 v2.0
  github.com/Madhatter2099/TCP-Optimize
                   快捷命令: t
==================================================
  1. 设置 IPv4 优先解析     [已激活]  解决 IPv6 绕路卡顿
  2. 开启 BBR + FQ          [已激活]  降低丢包/提升吞吐
  3. 生产级内核调优         [已激活]  缓冲区/连接/转发/conntrack
  4. 网卡多核分发 (RPS)     [未开启]  消除单核 SoftIRQ 瓶颈
  5. 一键回退到默认设置
  6. 检查并强制同步更新脚本
  7. 彻底卸载面板脚本
  0. 退出脚本
--------------------------------------------------
  算法: bbr | 队列: fq | 句柄: 1048576 | 转发: 1
--------------------------------------------------
```

### 推荐执行顺序

1. **选 3**（生产级内核调优）— 这会自动包含 BBR + FQ + 缓冲区 + conntrack + IP 转发，是最核心的一步
2. **选 1**（IPv4 优先）— 如果你的 VPS 有 IPv6 且出口路由不佳
3. **选 4**（网卡多核分发）— 如果你的 VPS ≥ 2 核心

> [!NOTE]
> 选项 3 已经包含了 BBR + FQ 的配置，所以**不需要**单独再执行选项 2。选项 2 适用于只想开 BBR 而不做其他调优的场景。

### 卸载

```bash
t
# 选择 7，会自动回退所有配置并删除脚本
```

---

## ⚙️ 系统要求

| 要求 | 说明 |
|------|------|
| 操作系统 | Debian 9+ / Ubuntu 18.04+ / CentOS 7+ / AlmaLinux / Rocky |
| 内核版本 | ≥ 4.9（BBR 支持）；≥ 6.12 自动获得 BBRv3 |
| 权限 | root |
| 依赖 | `curl`（必须）、`ethtool`（网卡优化模块会自动安装） |

---

## ❓ FAQ

<details>
<summary><b>BBRv3 怎么才能用上？</b></summary>

BBRv3 已经合并进 Linux 6.12+ 主线内核。只要你的内核版本 ≥ 6.12，设置 `tcp_congestion_control = bbr` 就是 BBRv3，无需额外操作。脚本会自动检测并显示你当前的 BBR 版本。

如果想在老内核上用 BBRv3，需要安装 [xanmod](https://xanmod.org/) 等自定义内核。

</details>

<details>
<summary><b>为什么 ECN 设置为 2 而不是 1？</b></summary>

`tcp_ecn = 1` 会让服务器作为客户端发起连接时，在 SYN 包中主动请求 ECN 协商。跨境链路上，大量中间设备会丢弃带 ECN 标记的 SYN 包，导致连接建立失败。

`tcp_ecn = 2` 表示服务端只被动响应 ECN 请求，不主动发起，兼容性更好。

</details>

<details>
<summary><b>RPS 和 RSS 有什么区别？</b></summary>

- **RSS（Receive Side Scaling）** 是硬件特性，需要网卡支持多队列。物理机常见。
- **RPS（Receive Packet Steering）** 是纯软件方案，通过哈希将数据包分发到不同 CPU 处理。

VPS 通常使用 virtio 虚拟网卡，只有 1 个 RX 队列，不支持硬件 RSS。RPS 是 VPS 环境下消除单核软中断瓶颈的最佳方案。

</details>

<details>
<summary><b>重启后配置还在吗？</b></summary>

- **sysctl 参数**（BBR、缓冲区、conntrack 等）：✅ 持久化在 `/etc/sysctl.d/` 下，重启后自动生效。
- **文件句柄限制**：✅ 持久化在 `/etc/security/limits.d/` 下。
- **RPS/RFS**：❌ 不持久化，重启后需重新执行选项 4。如需持久化，可将命令写入 `/etc/rc.local` 或 systemd 服务。
- **MSS Clamp (iptables)**：❌ 不持久化，重启后需重新执行选项 3，或使用 `iptables-persistent` 保存。

</details>

<details>
<summary><b>适合什么代理协议？</b></summary>

本脚本对所有基于 TCP/UDP 的代理协议都有效：

| 协议 | 受益最大的参数 |
|------|---------------|
| VLESS / VMess / Trojan | BBR + 缓冲区 + tcp_notsent_lowat + tcp_fastopen |
| Reality | BBR + tcp_mtu_probing + MSS Clamp |
| Hysteria2 / TUIC | UDP 缓冲区 + udp_mem |
| WireGuard | ip_forward + 缓冲区 |

</details>

---

## 📄 License

[MIT](LICENSE)

本项目基于 [666shen/tcp-dashboard](https://github.com/666shen/tcp-dashboard)（MIT License）改进。
