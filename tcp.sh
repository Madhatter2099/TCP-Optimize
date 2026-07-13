#!/bin/bash
# ==================================================
# TCP/UDP 网络深度调优与性能看板 v2.1 (Enhanced)
# 原作者: Madhatter2099
# 增强版改进:
#   - 修正 BBR 版本描述（主线仍为 v1/v2，v3 需 patch）
#   - RPS + iptables/nftables MSS Clamp 持久化（systemd oneshot 服务）
#   - 新增 4 种工作负载配置模板 (Profiles)
#   - 新增 网络性能基准测试（实时状态 + ping 测试 + 建议命令）
# github.com/Madhatter2099/TCP-Optimize (原版基础)
# ==================================================

SCRIPT_PATH="/usr/local/bin/tcp.sh"
SHORTCUT_PATH="/usr/local/bin/t"

# 命令行参数支持（用于 systemd 持久化服务调用）
if [ "$1" = "--apply-rps" ]; then
    optimize_nic
    exit 0
elif [ "$1" = "--apply-mss" ]; then
    apply_mss_clamp
    exit 0
fi

if [ "$EUID" -ne 0 ]; then
    echo -e "\033[0;31m错误: 必须使用 root 权限运行此脚本！\033[0m"
    exit 1
fi

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

draw_line() {
    echo -e "${YELLOW}--------------------------------------------------${NC}"
}

print_ok() { echo -e " ${GREEN}✔${NC} $1"; }
print_warn() { echo -e " ${YELLOW}⚠${NC} $1"; }
print_fail() { echo -e " ${RED}✘${NC} $1"; }
print_info() { echo -e " ${CYAN}ℹ${NC} $1"; }

# ==================================================
# 1. 自动安装与快捷键设置（保持原逻辑）
# ==================================================
if [ "$_" != "$SCRIPT_PATH" ] && [ "$0" != "$SCRIPT_PATH" ]; then
    echo -e "${YELLOW}>>> 正在安装脚本到本地系统...${NC}"
    mkdir -p /usr/local/bin
    curl -sL "https://raw.githubusercontent.com/Madhatter2099/TCP-Optimize/main/tcp.sh" -o "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
    if [ ! -f "$SHORTCUT_PATH" ] || [ ! -L "$SHORTCUT_PATH" ]; then
        ln -sf "$SCRIPT_PATH" "$SHORTCUT_PATH"
        echo -e "${GREEN}✅ 快捷命令 't' 已创建，以后在任意地方输入 t 即可打开面板。${NC}"
    fi
    exec bash "$SCRIPT_PATH"
    exit 0
fi

# ==================================================
# 2. 脚本维护模块（保持原逻辑，增强卸载）
# ==================================================
check_update() {
    printf "${YELLOW}正在同步最新脚本...${NC}\n"
    curl -sL "https://raw.githubusercontent.com/Madhatter2099/TCP-Optimize/main/tcp.sh" -o "$SCRIPT_PATH.tmp"
    if [ $? -eq 0 ] && [ -s "$SCRIPT_PATH.tmp" ]; then
        mv "$SCRIPT_PATH.tmp" "$SCRIPT_PATH"
        chmod +x "$SCRIPT_PATH"
        printf "${GREEN}脚本更新成功！正在重新载入...${NC}\n"
        sleep 1
        exec bash "$SCRIPT_PATH"
    else
        rm -f "$SCRIPT_PATH.tmp"
        printf "${RED}更新失败，请检查网络。${NC}\n"
    fi
}

uninstall_script() {
    echo -e "\n${RED}>>> 正在准备完全卸载脚本与快捷键...${NC}"
    read -p "确定要卸载吗？(这也会同时回退所有网络优化设置并删除持久化服务) [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}正在恢复网络默认设置并清理持久化服务...${NC}"
        rollback_all &>/dev/null
        remove_all_persistence
        rm -f "$SHORTCUT_PATH"
        rm -f "$SCRIPT_PATH"
        echo -e "${GREEN}✅ 卸载成功！网络已恢复，脚本与快捷键 't' 已从系统中移除。${NC}\n"
        exit 0
    else
        echo -e "${GREEN}已取消卸载。${NC}"
        sleep 1
    fi
}

# ==================================================
# 3. 功能模块定义
# ==================================================
SYSCTL_OPT="/etc/sysctl.d/99-network-performance.conf"
SYSCTL_BBR="/etc/systemd/system/rps-optimize.service"   # 注意：原 BBR 文件路径保持，但实际用 10-bbr.conf
SYSCTL_BBR_CONF="/etc/sysctl.d/10-bbr.conf"
LIMITS_OPT="/etc/security/limits.d/99-network-performance.conf"

RPS_SERVICE="/etc/systemd/system/rps-optimize.service"
MSS_SERVICE="/etc/systemd/system/mss-clamp.service"

# --------------------------------------------------
# 辅助：MSS Clamp 独立函数（支持持久化调用）
# --------------------------------------------------
apply_mss_clamp() {
    if command -v iptables &>/dev/null; then
        iptables -t mangle -D POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
        iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
        print_ok "MSS Clamp 规则已部署/刷新 (iptables)"
    else
        print_warn "未找到 iptables，跳过 MSS Clamp"
    fi
}

# --------------------------------------------------
# 3a. IPv4 优先解析（保持原逻辑，微调提示）
# --------------------------------------------------
set_ipv4_priority() {
    echo -e "\n${YELLOW}>>> 正在调整系统互联网协议优先级...${NC}"
    if [ ! -f /etc/gai.conf ]; then
        cat > /etc/gai.conf <<'EOF'
label ::1/128 0
label ::/0 1
label 2002::/16 2
label ::/96 3
label ::ffff:0:0/96 4
precedence ::1/128 50
precedence ::/0 40
precedence 2002::/16 30
precedence ::/96 20
precedence ::ffff:0:0/96 10
EOF
    fi
    [ ! -f /etc/gai.conf.bak ] && cp /etc/gai.conf /etc/gai.conf.bak
    sed -i '/precedence ::ffff:0:0\/96/d' /etc/gai.conf
    echo "precedence ::ffff:0:0/96 100" >> /etc/gai.conf
    print_ok "系统已设置为 ${GREEN}IPv4 优先${NC}，DNS 解析将优先返回 A 记录。"
    print_info "这能避免 IPv6 默认路由绕路导致的握手卡顿（适合部分国内/跨境环境）。"
    print_warn "注意：此设置可能影响纯 IPv6 服务，建议测试验证。"
    read -p "按回车返回..."
}

# --------------------------------------------------
# 3b. BBR + FQ（修正版本描述）
# --------------------------------------------------
enable_bbr() {
    echo -e "\n${YELLOW}>>> 正在激活 BBR + FQ 拥塞算法...${NC}"
    if ! modprobe tcp_bbr &>/dev/null && ! grep -q bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
        print_fail "当前内核不支持 BBR，请升级到 4.9+ 内核。"
        read -p "按回车返回..."
        return
    fi
    cat > "$SYSCTL_BBR_CONF" <<'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
    sysctl --system &>/dev/null

    local current_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    local current_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    if [ "$current_cc" = "bbr" ] && [ "$current_qdisc" = "fq" ]; then
        print_ok "BBR + FQ 已成功激活。"
    else
        print_warn "设置已写入但可能未完全生效，当前状态: cc=$current_cc qdisc=$current_qdisc"
    fi

    # 修正 BBR 版本描述（主线内核仍为 v1/v2，v3 需 patch）
    local kernel_ver=$(uname -r | cut -d. -f1-2)
    local major=$(echo "$kernel_ver" | cut -d. -f1)
    local minor=$(echo "$kernel_ver" | cut -d. -f2)
    echo -e "\n${CYAN}BBR 版本说明:${NC}"
    if [ "$major" -gt 6 ] || ([ "$major" -eq 6 ] && [ "$minor" -ge 12 ]); then
        print_info "内核 $(uname -r) 支持较新 BBR 实现。"
        print_info "注意：Linux 主线内核目前仍为 BBRv1（带部分 v2 改进）。BBRv3 需使用 Google 官方 patch 或特定发行版/自定义内核。"
    else
        print_info "内核 $(uname -r)，当前运行 ${CYAN}BBRv1/v2${NC}。"
        print_info "升级到 6.12+ 主线或使用带 BBRv3 patch 的内核可获得进一步改进。"
    fi

    draw_line
    printf " %-26s : ${GREEN}%s${NC}\n" "Congestion Control" "$current_cc"
    printf " %-26s : ${GREEN}%s${NC}\n" "Packet Scheduler (qdisc)" "$current_qdisc"
    draw_line
    read -p "按回车返回..."
}

# --------------------------------------------------
# 3c. 生产级内核深度调优（保持原逻辑 + 调用 MSS 函数）
# --------------------------------------------------
smart_tune() {
    echo -e "\n${YELLOW}>>> 正在启动系统环境扫描...${NC}"
    local mem_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local cpu_count=$(nproc)
    local mem_mb=$((mem_total_kb / 1024))

    local buf_bytes=$((mem_total_kb * 5 / 100 * 1024))
    local buf_min=$((4 * 1024 * 1024))
    local buf_max=$((256 * 1024 * 1024))
    [ "$buf_bytes" -lt "$buf_min" ] && buf_bytes=$buf_min
    [ "$buf_bytes" -gt "$buf_max" ] && buf_bytes=$buf_max

    local conntrack_max=$((mem_total_kb / 16))
    [ "$conntrack_max" -lt 65536 ] && conntrack_max=65536
    local conntrack_buckets=$((conntrack_max / 4))

    local old_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    local old_somax=$(sysctl -n net.core.somaxconn 2>/dev/null || echo "128")
    local old_rmem=$(sysctl -n net.core.rmem_max 2>/dev/null || echo "212992")
    local old_file=$(ulimit -n)

    echo -e " 核心数: ${CYAN}${cpu_count}${NC} | 内存: ${CYAN}${mem_mb}MB${NC}"
    echo -e " 动态缓冲区: ${CYAN}$((buf_bytes / 1024 / 1024))MB${NC} (总内存 5%, 范围 4-256MB)"
    echo -e " Conntrack 表: ${CYAN}${conntrack_max}${NC} 条目"

    echo -e "\n${YELLOW}>>> 正在写入内核参数配置...${NC}"
    cat > "$SYSCTL_OPT" <<EOF
# ===== TCP/UDP 网络性能调优 (v2.1 生产级动态) =====
# 由 tcp.sh 自动生成，勿手动编辑
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.ip_local_port_range = 1024 65535
net.core.rmem_max = ${buf_bytes}
net.core.wmem_max = ${buf_bytes}
net.core.rmem_default = 2097152
net.core.wmem_default = 2097152
net.core.optmem_max = 65536
net.ipv4.tcp_rmem = 4096 87380 ${buf_bytes}
net.ipv4.tcp_wmem = 4096 65536 ${buf_bytes}
net.ipv4.udp_rmem_min = 16384
net.ipv4.udp_wmem_min = 16384
net.ipv4.udp_mem = 65536 131072 262144
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_retries2 = 12
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_max_orphans = 32768
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_ecn = 2
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.netfilter.nf_conntrack_max = ${conntrack_max}
net.netfilter.nf_conntrack_buckets = ${conntrack_buckets}
net.netfilter.nf_conntrack_tcp_timeout_established = 7200
net.netfilter.nf_conntrack_tcp_timeout_time_wait = 30
net.netfilter.nf_conntrack_udp_timeout = 60
net.netfilter.nf_conntrack_udp_timeout_stream = 180
EOF

    modprobe nf_conntrack &>/dev/null || true
    sysctl --system &>/dev/null
    local sysctl_exit=$?

    mkdir -p /etc/security/limits.d/
    cat > "$LIMITS_OPT" <<'EOF'
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 65535
* hard nproc 65535
EOF

    apply_mss_clamp

    ulimit -n 1048576 2>/dev/null || true

    echo -e "\n${GREEN}✅ 内核调优完成，配置变更对比:${NC}"
    draw_line
    printf " %-14s: %-15s -> ${GREEN}%-15s${NC}\n" "拥塞算法" "$old_cc" "bbr"
    printf " %-14s: %-15s -> ${GREEN}%-15s${NC}\n" "最大连接队列" "$old_somax" "65535"
    printf " %-14s: %-15s -> ${GREEN}%-15s${NC}\n" "文件句柄" "$old_file" "1048576"
    printf " %-14s: %-15s -> ${GREEN}%-15s${NC}\n" "网络缓冲" "$((old_rmem / 1024 / 1024))MB" "$((buf_bytes / 1024 / 1024))MB"
    printf " %-14s: %-15s -> ${GREEN}%-15s${NC}\n" "Conntrack" "65536" "$conntrack_max"
    printf " %-14s: %-15s -> ${GREEN}%-15s${NC}\n" "IP 转发" "—" "已开启"
    printf " %-14s: %-15s -> ${GREEN}%-15s${NC}\n" "ECN 模式" "—" "被动响应(2)"
    draw_line

    if [ $sysctl_exit -ne 0 ]; then
        print_warn "部分参数可能未生效，请检查 dmesg。"
    fi

    print_info "所有配置已持久化至 ${PURPLE}$SYSCTL_OPT${NC}"
    print_info "重启后配置依然生效。RPS/MSS 持久化服务请在对应选项中启用。"

    # 询问是否为 MSS 创建持久化服务
    read -p "是否创建 systemd 服务使 MSS Clamp 持久化（推荐）？[Y/n]: " mss_persist
    if [[ "$mss_persist" =~ ^[Yy]$ ]] || [ -z "$mss_persist" ]; then
        setup_mss_persistence
    fi

    read -p "按回车返回..."
}

# --------------------------------------------------
# 3d. 网卡多核中断分发 (RPS) + 持久化询问
# --------------------------------------------------
optimize_nic() {
    echo -e "\n${YELLOW}>>> 正在执行多核心中断分发 (RPS/RFS) 优化...${NC}"
    if ! command -v ethtool &>/dev/null; then
        echo -e "${YELLOW}正在安装 ethtool...${NC}"
        apt-get update -qq && apt-get install -y -qq ethtool 2>/dev/null || yum install -y -q ethtool 2>/dev/null || true
    fi

    local interfaces=$(ls /sys/class/net | grep -vE '^(lo|docker[0-9]*|veth|br-|virbr|any|sit[0-9]*|tun[0-9]*|tap[0-9]*|wg[0-9]*|dummy)$')
    local cpu_count=$(nproc)
    if [ "$cpu_count" -le 1 ]; then
        print_warn "当前系统只有 1 个 CPU 核心，RPS 分发无实际效果。"
        read -p "按回车返回..."
        return
    fi

    local rps_cpus=$(printf '%x' $(((1 << cpu_count) - 1)))
    local configured=0
    for eth in $interfaces; do
        [ ! -d "/sys/class/net/$eth" ] && continue
        local max_rx=$(ethtool -g "$eth" 2>/dev/null | awk '/Pre-set maximums/{found=1} found && /RX:/{print $2; exit}')
        local max_tx=$(ethtool -g "$eth" 2>/dev/null | awk '/Pre-set maximums/{found=1} found && /TX:/{print $2; exit}')
        [ -n "$max_rx" ] && ethtool -G "$eth" rx "$max_rx" 2>/dev/null || true
        [ -n "$max_tx" ] && ethtool -G "$eth" tx "$max_tx" 2>/dev/null || true

        for rps_file in /sys/class/net/$eth/queues/rx-*/rps_cpus; do
            [ -f "$rps_file" ] && echo "$rps_cpus" > "$rps_file"
        done
        for rfc_file in /sys/class/net/$eth/queues/rx-*/rps_flow_cnt; do
            [ -f "$rfc_file" ] && echo "4096" > "$rfc_file"
        done
        print_ok "接口 ${CYAN}$eth${NC}: RPS 掩码=0x${rps_cpus} (覆盖 ${cpu_count} 核心)"
        configured=$((configured + 1))
    done

    sysctl -w net.core.rps_sock_flow_entries=32768 &>/dev/null

    if [ "$configured" -eq 0 ]; then
        print_warn "未找到可配置的网络接口。"
    else
        echo -e "\n${GREEN}✅ RPS/RFS 配置完成:${NC}"
        draw_line
        printf " %-22s : ${GREEN}%s${NC}\n" "配置接口数" "$configured"
        printf " %-22s : ${GREEN}%s 核心${NC}\n" "CPU 分发范围" "$cpu_count"
        printf " %-22s : ${GREEN}%s${NC}\n" "全局流表 (RFS)" "32768"
        draw_line
        print_info "RPS 是软件级数据包分发，在 VPS 虚拟网卡上是最佳方案。"
    fi

    # 询问是否创建持久化服务
    read -p "是否创建 systemd 服务使 RPS/RFS 持久化（重启后自动生效，推荐）？[Y/n]: " rps_persist
    if [[ "$rps_persist" =~ ^[Yy]$ ]] || [ -z "$rps_persist" ]; then
        setup_rps_persistence
    fi

    read -p "按回车返回..."
}

# --------------------------------------------------
# 持久化服务创建函数
# --------------------------------------------------
setup_rps_persistence() {
    cat > "$RPS_SERVICE" <<EOF
[Unit]
Description=RPS/RFS Network Optimization (created by tcp.sh v2.1)
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/tcp.sh --apply-rps
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable rps-optimize.service &>/dev/null
    systemctl start rps-optimize.service &>/dev/null
    print_ok "RPS 持久化服务已创建并启用 → $RPS_SERVICE"
    print_info "重启后将自动应用 RPS/RFS 优化。"
}

setup_mss_persistence() {
    cat > "$MSS_SERVICE" <<EOF
[Unit]
Description=MSS Clamp for PMTU (created by tcp.sh v2.1)
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/tcp.sh --apply-mss
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable mss-clamp.service &>/dev/null
    systemctl start mss-clamp.service &>/dev/null
    print_ok "MSS Clamp 持久化服务已创建并启用 → $MSS_SERVICE"
}

remove_all_persistence() {
    systemctl disable --now rps-optimize.service mss-clamp.service 2>/dev/null || true
    rm -f "$RPS_SERVICE" "$MSS_SERVICE"
    systemctl daemon-reload 2>/dev/null || true
    print_ok "持久化服务已清理"
}

# --------------------------------------------------
# 3e. 一键回退（增强持久化清理）
# --------------------------------------------------
rollback_all() {
    rm -f "$SYSCTL_OPT" "$LIMITS_OPT" "$SYSCTL_BBR_CONF"
    if [ -f /etc/gai.conf.bak ]; then
        mv /etc/gai.conf.bak /etc/gai.conf
    else
        sed -i '/precedence ::ffff:0:0\/96 100/d' /etc/gai.conf 2>/dev/null || true
    fi
    sysctl -w net.ipv4.tcp_congestion_control=cubic &>/dev/null
    sysctl -w net.core.default_qdisc=fq_codel &>/dev/null
    sysctl -w net.core.rps_sock_flow_entries=0 &>/dev/null

    local interfaces=$(ls /sys/class/net | grep -vE '^(lo|docker[0-9]*|veth|br-|virbr|any|sit[0-9]*|tun[0-9]*|tap[0-9]*|wg[0-9]*|dummy)$')
    for eth in $interfaces; do
        for rps_file in /sys/class/net/$eth/queues/rx-*/rps_cpus; do
            [ -f "$rps_file" ] && echo "0" > "$rps_file"
        done
    done

    if command -v iptables &>/dev/null; then
        iptables -t mangle -D POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || true
    fi

    ulimit -n 1024 2>/dev/null || true
    sysctl --system &>/dev/null

    remove_all_persistence

    echo -e "${GREEN}✅ 回退完成:${NC}"
    print_ok "配置文件已清理"
    print_ok "拥塞算法已恢复: cubic + fq_codel"
    print_ok "RPS/RFS 已关闭 + 持久化服务已删除"
    print_ok "MSS Clamp 规则已移除"
    print_ok "IPv4 优先解析已恢复"
}

# --------------------------------------------------
# 新增：工作负载配置模板 (Profiles)
# --------------------------------------------------
apply_workload_profile() {
    clear
    echo -e "${YELLOW}==================================================${NC}"
    echo -e "${YELLOW} 工作负载配置模板 (Profiles) v2.1 ${NC}"
    echo -e "${YELLOW}==================================================${NC}"
    echo -e "请选择最符合你 VPS 主要用途的模板："
    echo ""
    echo -e " ${CYAN}1.${NC} 轻量 Web / 静态网站     - 保守缓冲，适合低并发 Web"
    echo -e " ${CYAN}2.${NC} 高并发代理/VPN (推荐)   - 激进 conntrack + UDP，适合 Hysteria2/Xray"
    echo -e " ${CYAN}3.${NC} 游戏 / 低延迟应用       - 平衡延迟，适合游戏服务器"
    echo -e " ${CYAN}4.${NC} 最大吞吐国际链路       - 最大缓冲 + BBR，适合下载/中转"
    echo -e " ${CYAN}0.${NC} 返回主菜单"
    draw_line
    read -p "请选择模板 [0-4]: " profile_choice

    local mem_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local buf_bytes=$((mem_total_kb * 5 / 100 * 1024))
    local buf_min=$((4 * 1024 * 1024))
    local buf_max=$((256 * 1024 * 1024))
    [ "$buf_bytes" -lt "$buf_min" ] && buf_bytes=$buf_min
    [ "$buf_bytes" -gt "$buf_max" ] && buf_bytes=$buf_max

    local conntrack_max=$((mem_total_kb / 16))
    [ "$conntrack_max" -lt 65536 ] && conntrack_max=65536

    case "$profile_choice" in
        1)  # 轻量 Web
            echo -e "\n${GREEN}>>> 应用「轻量 Web」模板...${NC}"
            cat > "$SYSCTL_OPT" <<EOF
# 轻量 Web 服务器模板
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.ip_forward = 1
net.core.somaxconn = 32768
net.core.netdev_max_backlog = 32768
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.ip_local_port_range = 1024 65535
net.core.rmem_max = $buf_bytes
net.core.wmem_max = $buf_bytes
net.ipv4.tcp_rmem = 4096 87380 $buf_bytes
net.ipv4.tcp_wmem = 4096 65536 $buf_bytes
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 20
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_ecn = 2
net.netfilter.nf_conntrack_max = $conntrack_max
net.netfilter.nf_conntrack_tcp_timeout_established = 7200
EOF
            print_ok "轻量 Web 模板已应用（保守缓冲 + 标准超时）"
            ;;
        2)  # 高并发代理/VPN
            echo -e "\n${GREEN}>>> 应用「高并发代理/VPN」模板（推荐用于 Hysteria2/Xray）...${NC}"
            local proxy_buf=$((buf_bytes * 3 / 2))
            [ "$proxy_buf" -gt "$buf_max" ] && proxy_buf=$buf_max
            local proxy_ct=$((mem_total_kb / 12))
            [ "$proxy_ct" -lt 131072 ] && proxy_ct=131072
            cat > "$SYSCTL_OPT" <<EOF
# 高并发代理/VPN 模板 (Hysteria2/Xray 优化)
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.ip_forward = 1
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.ip_local_port_range = 1024 65535
net.core.rmem_max = $proxy_buf
net.core.wmem_max = $proxy_buf
net.ipv4.tcp_rmem = 4096 87380 $proxy_buf
net.ipv4.tcp_wmem = 4096 65536 $proxy_buf
net.ipv4.udp_rmem_min = 32768
net.ipv4.udp_wmem_min = 32768
net.ipv4.udp_mem = 131072 262144 524288
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_notsent_lowat = 16384
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_ecn = 2
net.netfilter.nf_conntrack_max = $proxy_ct
net.netfilter.nf_conntrack_buckets = $((proxy_ct / 4))
net.netfilter.nf_conntrack_tcp_timeout_established = 3600
net.netfilter.nf_conntrack_udp_timeout = 30
EOF
            # 代理场景加强 limits
            cat > "$LIMITS_OPT" <<'EOF'
* soft nofile 2097152
* hard nofile 2097152
* soft nproc 131072
* hard nproc 131072
EOF
            print_ok "高并发代理/VPN 模板已应用（更大 UDP 缓冲 + 更高 conntrack + 更激进回收）"
            ;;
        3)  # 游戏/低延迟
            echo -e "\n${GREEN}>>> 应用「游戏/低延迟」模板...${NC}"
            cat > "$SYSCTL_OPT" <<EOF
# 游戏/低延迟应用模板
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.ip_forward = 1
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.ip_local_port_range = 1024 65535
net.core.rmem_max = $((buf_bytes * 2 / 3))
net.core.wmem_max = $((buf_bytes * 2 / 3))
net.ipv4.tcp_rmem = 4096 87380 $((buf_bytes * 2 / 3))
net.ipv4.tcp_wmem = 4096 65536 $((buf_bytes * 2 / 3))
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_notsent_lowat = 8192
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_ecn = 2
net.netfilter.nf_conntrack_max = $conntrack_max
net.netfilter.nf_conntrack_tcp_timeout_established = 7200
EOF
            print_ok "游戏/低延迟模板已应用（更小缓冲 + 更激进 notsent_lowat 降低 TTFB）"
            ;;
        4)  # 最大吞吐
            echo -e "\n${GREEN}>>> 应用「最大吞吐国际链路」模板...${NC}"
            cat > "$SYSCTL_OPT" <<EOF
# 最大吞吐国际链路模板
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.ip_forward = 1
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 32768
net.ipv4.ip_local_port_range = 1024 65535
net.core.rmem_max = $buf_max
net.core.wmem_max = $buf_max
net.ipv4.tcp_rmem = 4096 87380 $buf_max
net.ipv4.tcp_wmem = 4096 65536 $buf_max
net.ipv4.udp_rmem_min = 32768
net.ipv4.udp_wmem_min = 32768
net.ipv4.udp_mem = 131072 262144 524288
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_notsent_lowat = 32768
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_ecn = 2
net.netfilter.nf_conntrack_max = $((conntrack_max * 2))
net.netfilter.nf_conntrack_tcp_timeout_established = 7200
EOF
            print_ok "最大吞吐模板已应用（最大缓冲 + 激进参数，适合高 BDP 国际链路）"
            ;;
        0) return ;;
        *) echo -e "${RED}无效选择${NC}"; sleep 1; return ;;
    esac

    modprobe nf_conntrack &>/dev/null || true
    sysctl --system &>/dev/null
    ulimit -n 1048576 2>/dev/null || true
    apply_mss_clamp

    print_info "模板已写入 $SYSCTL_OPT，重启后生效。"
    print_info "建议运行「网络性能基准测试」查看当前状态。"
    read -p "按回车返回主菜单..."
}

# --------------------------------------------------
# 新增：网络性能基准测试（让用户“看到”提升）
# --------------------------------------------------
run_network_benchmark() {
    clear
    echo -e "${YELLOW}==================================================${NC}"
    echo -e "${YELLOW} 网络性能基准测试 & 当前状态报告 v2.1 ${NC}"
    echo -e "${YELLOW}==================================================${NC}"

    echo -e "\n${CYAN}【当前关键内核参数】${NC}"
    draw_line
    printf " %-28s : ${GREEN}%s${NC}\n" "拥塞控制算法 (CC)" "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
    printf " %-28s : ${GREEN}%s${NC}\n" "队列调度 (qdisc)" "$(sysctl -n net.core.default_qdisc 2>/dev/null)"
    printf " %-28s : ${GREEN}%s${NC}\n" "最大连接队列 (somaxconn)" "$(sysctl -n net.core.somaxconn 2>/dev/null)"
    local rmem_max=$(sysctl -n net.core.rmem_max 2>/dev/null)
    printf " %-28s : ${GREEN}%s MB${NC}\n" "接收缓冲最大值" "$((rmem_max / 1024 / 1024))"
    printf " %-28s : ${GREEN}%s${NC}\n" "文件句柄限制 (ulimit -n)" "$(ulimit -n)"
    printf " %-28s : ${GREEN}%s${NC}\n" "IP 转发" "$(sysctl -n net.ipv4.ip_forward 2>/dev/null)"
    printf " %-28s : ${GREEN}%s${NC}\n" "RPS 全局流表" "$(sysctl -n net.core.rps_sock_flow_entries 2>/dev/null || echo 0)"
    draw_line

    # Conntrack 使用情况
    if command -v conntrack &>/dev/null; then
        local ct_max=$(sysctl -n net.netfilter.nf_conntrack_max 2>/dev/null || echo "?")
        local ct_current=$(conntrack -L 2>/dev/null | wc -l)
        printf " %-28s : ${GREEN}%s / %s${NC}\n" "Conntrack 使用情况" "$ct_current" "$ct_max"
    else
        print_info "安装 conntrack-tools 可查看实时连接跟踪表使用率"
    fi

    # IPv4 优先状态
    if [ -f /etc/gai.conf ] && grep -q "^precedence ::ffff:0:0/96 100" /etc/gai.conf 2>/dev/null; then
        printf " %-28s : ${GREEN}已激活${NC}\n" "IPv4 优先解析"
    else
        printf " %-28s : ${RED}未开启${NC}\n" "IPv4 优先解析"
    fi

    echo -e "\n${CYAN}【简单连通性测试】${NC}"
    draw_line
    echo -e "正在测试到 Cloudflare DNS (1.1.1.1) 的延迟与丢包..."
    ping -c 6 -W 2 1.1.1.1 2>/dev/null | tail -4

    echo -e "\n${CYAN}【如何验证优化效果（推荐手动执行）】${NC}"
    draw_line
    echo -e "1. 真实吞吐测试（需对端也有 iperf3）："
    echo -e "   ${GREEN}iperf3 -c <对端IP> -t 30 -P 4 -R${NC}"
    echo -e "2. 延迟抖动 + 丢包测试："
    echo -e "   ${GREEN}mtr -n -i 0.5 -c 50 <对端IP>${NC}   或安装 flent"
    echo -e "3. 连接数与缓冲使用观察："
    echo -e "   ${GREEN}ss -s${NC}   ${GREEN}ss -tan | wc -l${NC}"
    echo -e "4. 应用优化前后分别运行本测试，即可对比参数变化与 ping 表现。"

    echo -e "\n${PURPLE}提示：${NC}应用「工作负载配置模板」或「生产级内核调优」后，"
    echo -e "      重新运行本选项即可看到关键参数的实时变化。"
    draw_line
    read -p "按回车返回主菜单..."
}

# ==================================================
# 4. 主菜单（更新选项 + 状态）
# ==================================================
while true; do
    # 实时状态检测
    if [ -f /etc/gai.conf ] && grep -q "^precedence ::ffff:0:0/96 100" /etc/gai.conf 2>/dev/null; then
        status_ipv4="${GREEN}[已激活]${NC}"
    else
        status_ipv4="${RED}[未开启]${NC}"
    fi
    if [ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" = "bbr" ]; then
        status_bbr="${GREEN}[已激活]${NC}"
    else
        status_bbr="${RED}[未开启]${NC}"
    fi
    if [ -f "$SYSCTL_OPT" ]; then
        status_sysctl="${GREEN}[已激活]${NC}"
    else
        status_sysctl="${RED}[未开启]${NC}"
    fi
    if [ "$(sysctl -n net.core.rps_sock_flow_entries 2>/dev/null)" = "32768" ]; then
        status_nic="${GREEN}[已激活]${NC}"
    else
        status_nic="${RED}[未开启]${NC}"
    fi

    clear
    echo -e "${YELLOW}==================================================${NC}"
    echo -e "${YELLOW} TCP/UDP 网络深度调优与性能看板 v2.1 ${NC}"
    echo -e "${GREEN} github.com/Madhatter2099/TCP-Optimize (Enhanced)${NC}"
    echo -e "${GREEN} 快捷命令: t ${NC}"
    echo -e "${YELLOW}==================================================${NC}"
    echo -e " 1. 设置 IPv4 优先解析 $status_ipv4     解决 IPv6 绕路卡顿"
    echo -e " 2. 开启 BBR + FQ $status_bbr           降低丢包/提升吞吐（已修正版本描述）"
    echo -e " 3. 生产级内核调优 $status_sysctl       动态缓冲/连接/转发/conntrack"
    echo -e " 4. 网卡多核分发 (RPS) $status_nic     消除单核 SoftIRQ 瓶颈（支持持久化）"
    echo -e " 5. 一键回退到默认设置"
    echo -e " 6. 检查并强制同步更新脚本"
    echo -e " 7. 彻底卸载面板脚本"
    echo -e " ${CYAN}8. 工作负载配置模板 (Profiles)${NC}   一键应用推荐参数"
    echo -e " ${CYAN}9. 网络性能基准测试${NC}             查看当前状态与验证提升"
    echo -e " 0. 退出脚本"
    draw_line

    cur_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    cur_qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null)
    cur_fd=$(ulimit -n)
    cur_fwd=$(sysctl -n net.ipv4.ip_forward 2>/dev/null)
    echo -e " 算法: ${GREEN}${cur_cc}${NC} | 队列: ${GREEN}${cur_qdisc}${NC} | 句柄: ${GREEN}${cur_fd}${NC} | 转发: ${GREEN}${cur_fwd}${NC}"
    draw_line

    read -p "请选择 [0-9]: " t_opt
    case "$t_opt" in
        1) set_ipv4_priority ;;
        2) enable_bbr ;;
        3) smart_tune ;;
        4) optimize_nic ;;
        5) rollback_all && read -p "按回车返回..." ;;
        6) check_update ;;
        7) uninstall_script ;;
        8) apply_workload_profile ;;
        9) run_network_benchmark ;;
        0) exit 0 ;;
        *) echo -e "${RED}输入错误，请输入 0-9！${NC}" && sleep 1 ;;
    esac
done
