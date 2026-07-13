# 🚀 TCP/UDP 网络深度调优脚本

> 一键优化 VPS 作为网络中转服务器的内核参数、拥塞控制、缓冲区与连接跟踪，专为跨境高丢包/高延迟链路设计。
>
> 本项目基于 [666shen/tcp-dashboard](https://github.com/666shen/tcp-dashboard) 改进，v2.1 版本新增工作负载模板、基准测试与持久化服务。

![Shell](https://img.shields.io/badge/Shell-Bash-green?logo=gnubash&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue)
![Platform](https://img.shields.io/badge/Platform-Linux%204.9%2B-orange)
![Version](https://img.shields.io/badge/Version-v2.1--Enhanced-purple)

---

## ✨ v2.1 更新

新增功能：

| 新增/改进 | 说明 | 菜单位置 |
|-----------|------|----------|
| **工作负载配置模板 (Profiles)** | 一键应用 4 种实用场景模板（轻量 Web、高并发代理/VPN、游戏/低延迟、最大吞吐国际链路），自动调整缓冲区、conntrack、UDP 参数等 | **选项 8** |
| **网络性能基准测试** | 实时展示当前关键内核参数 + 简单 ping 测试 + 推荐验证命令（iperf3 / mtr / ss），让用户直观看到优化效果 | **选项 9** |
| **RPS + MSS Clamp 持久化** | 新增 systemd oneshot 服务（`rps-optimize.service` / `mss-clamp.service`），重启后自动生效 | 选项 3 / 4 成功后询问 |
| **BBR 版本描述修正** | 明确说明 Linux 主线内核目前仍为 BBRv1（含部分 v2 改进），BBRv3 需 patch 或特定内核 | 选项 2 |
| 菜单与交互优化 | 新增选项 8、9，状态检测更完善，卸载时同步清理持久化服务 | - |

> **推荐新用户直接使用选项 8（工作负载模板）**，大多数代理/VPN 用户选择「高并发代理/VPN」模板即可获得优秀效果。

---

## 📋 功能概览

| 模块 | 说明 | v2.1 状态 |
|------|------|-----------|
| **IPv4 优先解析** | 通过 `gai.conf` 优先返回 A 记录，避免 IPv6 绕路卡顿 | 保留 |
| **BBR + FQ** | Google BBR 拥塞控制 + fq 队列调度 | 保留 + 版本说明修正 |
| **生产级内核调优** | 动态缓冲区（总内存 5%）、连接队列、IP 转发、conntrack 调优 | 保留 |
| **网卡多核分发 (RPS)** | 软中断多核分发，消除单核瓶颈 | **新增持久化服务** |
| **工作负载配置模板** | 4 种场景一键优化 | **v2.1 新增** |
| **网络性能基准测试** | 参数展示 + ping 测试 + 验证命令 | **v2.1 新增** |
| **一键回退** | 清理配置并删除持久化服务 | 增强 |

---

## 🛠️ 部署方法

保持原有三种方式不变（GitHub Raw / jsDelivr / 手动下载），安装后输入 `t` 即可打开面板。


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

### 交互式面板（v2.1 版本）

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
  8. 工作负载配置模板 (Profiles)     一键应用推荐参数
  9. 网络性能基准测试               查看当前状态与验证提升
  10. 退出脚本
--------------------------------------------------
  算法: bbr | 队列: fq | 句柄: 1048576 | 转发: 1
--------------------------------------------------

### 推荐执行顺序（v2.1）

1. **选项 8**（工作负载配置模板）—— **新用户首选**，根据用途一键应用最优参数
2. **选项 3**（生产级内核调优）—— 需要更激进自定义时使用
3. **选项 4**（RPS）—— 多核 VPS 推荐开启，并创建持久化服务
4. **选项 1**（IPv4 优先）—— IPv6 出口不佳时使用
5. **选项 9**（基准测试）—— 随时查看当前状态与验证效果

> 选项 3 已包含 BBR + FQ，无需单独执行选项 2。

---

## ⚙️ 系统要求

- 操作系统：Debian 9+ / Ubuntu 18.04+ / CentOS 7+ / AlmaLinux / Rocky
- 内核：≥ 4.9（支持 BBR）
- 权限：root
- 依赖：`curl`（必须）、`ethtool`（会自动安装）、`systemd`（持久化服务需要）

---

## ❓ FAQ

<details>
<summary><b>BBRv3 怎么才能用上？</b></summary>

Linux **主线内核目前仍为 BBRv1（含部分 v2 改进）**。脚本 v2.1 已修正原版错误描述。

- 内核 ≥ 6.12 时会显示支持较新 BBR 实现，但仍需注意主线限制。
- 想使用完整 BBRv3，请安装带 patch 的内核（如 Xanmod、zen-kernel）或手动编译 Google 官方 BBRv3 模块。

</details>

<details>
<summary><b>RPS 和 MSS Clamp 重启后还在吗？（v2.1 重要更新）</b></summary>

**v2.1 已解决此痛点**：

- **RPS/RFS**：开启后可创建 `rps-optimize.service`，重启自动生效。
- **MSS Clamp**：开启后可创建 `mss-clamp.service`，重启自动生效。
- sysctl 参数和 limits 原本就已持久化。
- 回退（选项 5）和卸载（选项 7）会自动停止并删除这两个 systemd 服务。

</details>

<details>
<summary><b>为什么推荐使用「工作负载配置模板」（选项 8）？</b></summary>

不同用途对参数需求差异很大：

- **高并发代理/VPN**：更大 UDP 缓冲 + 更高 conntrack + 更激进回收（适合 Hysteria2/Xray）
- **游戏/低延迟**：更小缓冲 + 更激进 `tcp_notsent_lowat`
- **最大吞吐国际链路**：最大缓冲区设置

模板会自动为你调整最合适的参数组合，比手动调优更安全高效。

</details>

<details>
<summary><b>如何验证优化是否有效？</b></summary>

使用 **选项 9（网络性能基准测试）**：

- 实时展示当前 CC、缓冲区大小、conntrack 使用率、RPS 状态等关键参数
- 自动执行 ping 测试（延迟 + 丢包）
- 提供 `iperf3`、`mtr`、`ss` 等实用验证命令

建议在应用模板或生产级调优**前后各运行一次**选项 9，对比参数变化即可直观看到提升。

</details>

<details>
<summary><b>适合什么代理协议？</b></summary>

对所有 TCP/UDP 代理均有效，尤其在以下场景提升明显：

- VLESS / VMess / Trojan / Reality
- Hysteria2 / TUIC（UDP 缓冲优化）
- WireGuard（IP 转发 + 缓冲区）

</details>

---

## 🔗 友链

https://linux.do/  
https://www.nodeseek.com/

感谢社区用户的反馈与建议！

## 📄 License

[MIT](LICENSE)

本项目基于 [666shen/tcp-dashboard](https://github.com/666shen/tcp-dashboard) 改进。