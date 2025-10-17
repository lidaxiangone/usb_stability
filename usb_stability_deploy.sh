#!/bin/bash
# USB稳定性一键部署脚本
# 适用于OpenWrt系统的USB共享网络稳定性优化

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        exit 1
    fi
}

# 创建USB看门狗守护进程
create_usb_watchdog() {
    log_info "创建USB看门狗守护进程..."
    
    cat > /usr/sbin/usb_watchdog << 'EOF'
#!/bin/sh
# USB看门狗守护进程 - 增强版
# 监控USB设备连接状态，自动恢复断连

logger "USB看门狗守护进程启动"
COUNTER=0
MAX_RETRIES=3
SLEEP_INTERVAL=10

while true; do
    # 检查USB设备是否存在
    if [ ! -d /sys/bus/usb/devices/usb1/1-1 ] && [ $COUNTER -lt $MAX_RETRIES ]; then
        logger "USB设备断开连接！尝试恢复...($((COUNTER+1))/$MAX_RETRIES)"
        
        # 温和的重置策略
        echo 1 > /sys/bus/platform/devices/7000000.usb/reset 2>/dev/null
        sleep 2
        echo 0 > /sys/bus/platform/devices/7000000.usb/reset 2>/dev/null
        
        # 等待设备重新识别
        sleep 5
        COUNTER=$((COUNTER+1))
    elif [ -d /sys/bus/usb/devices/usb1/1-1 ]; then
        if [ $COUNTER -ne 0 ]; then
            logger "USB设备恢复成功"
            COUNTER=0
        fi
    else
        if [ $COUNTER -ge $MAX_RETRIES ]; then
            logger "USB设备恢复失败已达最大重试次数，等待下一周期"
            COUNTER=0
        fi
    fi
    sleep $SLEEP_INTERVAL
done
EOF

    chmod +x /usr/sbin/usb_watchdog
    log_info "USB看门狗脚本创建完成"
}

# 创建状态检查脚本
create_status_script() {
    log_info "创建状态检查脚本..."
    
    cat > /usr/sbin/usb_status << 'EOF'
#!/bin/sh
# USB稳定性状态检查脚本

echo "=== USB稳定性系统状态检查 ==="
echo "检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# 检查看门狗进程
WATCHDOG_COUNT=$(ps | grep -c '[u]sb_watchdog')
echo "看门狗进程: $WATCHDOG_COUNT 个实例运行中"

# 检查自动挂起设置
AUTOSUSPEND=$(cat /sys/module/usbcore/parameters/autosuspend 2>/dev/null || echo "未知")
echo "自动挂起设置: $AUTOSUSPEND"

# 检查电源控制状态
echo "设备电源状态:"
for control_file in /sys/bus/usb/devices/*/power/control; do
    if [ -f "$control_file" ]; then
        device_name=$(echo "$control_file" | awk -F'/' '{print $(NF-1)}')
        status=$(cat "$control_file")
        echo "  $device_name: $status"
    fi
done

# 检查USB设备连接
echo ""
echo "USB设备连接状态:"
if [ -d /sys/bus/usb/devices/usb1/1-1 ]; then
    echo "  USB共享设备: 已连接"
else
    echo "  USB共享设备: 未连接"
fi

# 检查网络接口
echo ""
echo "网络接口状态:"
ifconfig usb0 2>/dev/null && echo "  usb0接口: 存在" || echo "  usb0接口: 不存在"

echo "=== 状态检查完成 ==="
EOF

    chmod +x /usr/sbin/usb_status
    log_info "状态检查脚本创建完成"
}

# 创建启动脚本
create_startup_script() {
    log_info "创建启动脚本..."
    
    cat > /etc/init.d/usb_stability << 'EOF'
#!/bin/sh /etc/rc.common
# USB稳定性服务脚本
# 提供USB电源管理和看门狗守护功能

USE_PROCD=1
START=95
STOP=15

start_service() {
    procd_open_instance
    procd_set_param command /bin/sh -c "while true; do sleep 60; done"
    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
    
    # 初始化USB稳定性设置
    init_usb_stability
}

stop_service() {
    # 停止看门狗进程
    pkill -f "/usr/sbin/usb_watchdog" 2>/dev/null && echo "看门狗进程已停止"
}

init_usb_stability() {
    # 禁用USB自动挂起
    echo -1 > /sys/module/usbcore/parameters/autosuspend 2>/dev/null && \
        echo "USB自动挂起已禁用" || echo "禁用自动挂起失败"
    
    # 设置USB设备持续供电
    for control_file in /sys/bus/usb/devices/*/power/control; do
        if [ -f "$control_file" ]; then
            echo on > "$control_file" 2>/dev/null && \
                echo "设置 $(basename $(dirname $control_file)) 为持续供电" \
                || echo "设置 $(basename $(dirname $control_file)) 供电失败"
        fi
    done
    
    # 启动看门狗守护进程
    /usr/sbin/usb_watchdog &
    echo "USB看门狗守护进程已启动"
}

boot() {
    start
}

restart() {
    stop
    sleep 2
    start
}
EOF

    chmod +x /etc/init.d/usb_stability
    log_info "启动脚本创建完成"
}

# 配置开机自启动
enable_autostart() {
    log_info "配置开机自启动..."
    
    # 启用服务
    /etc/init.d/usb_stability enable 2>/dev/null && \
        log_info "服务自启动已启用" || \
        log_warn "服务自启动启用失败，将使用备用方案"
    
    # 备用启动方案
    cat > /etc/rc.local << 'EOF'
#!/bin/sh
# USB稳定性备用启动脚本

sleep 30

# 禁用USB自动挂起
echo -1 > /sys/module/usbcore/parameters/autosuspend 2>/dev/null

# 设置USB设备持续供电
for i in /sys/bus/usb/devices/*/power/control; do
    [ -e "$i" ] && echo on > "$i" 2>/dev/null
done

# 启动看门狗
/usr/sbin/usb_watchdog &

exit 0
EOF

    chmod +x /etc/rc.local
    log_info "备用启动方案配置完成"
}

# 启动服务
start_services() {
    log_info "启动USB稳定性服务..."
    
    # 停止可能存在的旧进程
    pkill -f "/usr/sbin/usb_watchdog" 2>/dev/null && \
        log_info "停止旧看门狗进程"
    
    # 立即应用设置
    echo -1 > /sys/module/usbcore/parameters/autosuspend 2>/dev/null
    for i in /sys/bus/usb/devices/*/power/control; do
        [ -e "$i" ] && echo on > "$i" 2>/dev/null
    done
    
    # 启动看门狗
    /usr/sbin/usb_watchdog &
    sleep 2
    
    # 尝试通过init.d启动
    /etc/init.d/usb_stability start 2>/dev/null && \
        log_info "服务启动成功" || \
        log_warn "服务启动失败，但看门狗已直接启动"
}

# 验证部署
verify_deployment() {
    log_info "验证部署结果..."
    
    echo ""
    echo "=== 部署验证 ==="
    
    # 检查看门狗进程
    if pgrep -f "/usr/sbin/usb_watchdog" > /dev/null; then
        echo -e "${GREEN}✓ USB看门狗进程运行中${NC}"
    else
        echo -e "${RED}✗ USB看门狗进程未运行${NC}"
    fi
    
    # 检查自动挂起设置
    AUTOSUSPEND=$(cat /sys/module/usbcore/parameters/autosuspend 2>/dev/null)
    if [ "$AUTOSUSPEND" = "-1" ]; then
        echo -e "${GREEN}✓ USB自动挂起已禁用${NC}"
    else
        echo -e "${YELLOW}⚠ USB自动挂起设置可能未生效${NC}"
    fi
    
    # 检查电源控制
    POWER_CONTROLS=$(grep -h . /sys/bus/usb/devices/*/power/control 2>/dev/null | uniq)
    if [ "$POWER_CONTROLS" = "on" ]; then
        echo -e "${GREEN}✓ USB设备持续供电已启用${NC}"
    else
        echo -e "${YELLOW}⚠ USB电源控制可能未完全生效${NC}"
    fi
    
    echo "=== 验证完成 ==="
    echo ""
}

# 显示使用说明
show_usage() {
    cat << 'EOF'

=== USB稳定性系统使用说明 ===

1. 手动控制命令：
   /etc/init.d/usb_stability start    # 启动服务
   /etc/init.d/usb_stability stop     # 停止服务  
   /etc/init.d/usb_stability restart  # 重启服务
   usb_status                         # 检查系统状态

2. 日志查看：
   logread | grep -i usb              # 查看USB相关日志
   ps | grep usb_watchdog            # 查看看门狗进程

3. 监控建议：
   - 定期运行 usb_status 检查系统健康度
   - 关注日志中的USB设备断开/恢复记录
   - 重启后验证配置是否持久化

4. 故障排查：
   - 如果USB仍然频繁断连，检查物理连接和电源
   - 查看系统负载和内存使用情况
   - 确认USB驱动正常工作

EOF
}

# 主执行函数
main() {
    log_info "开始部署USB稳定性系统..."
    
    check_root
    create_usb_watchdog
    create_status_script
    create_startup_script
    enable_autostart
    start_services
    verify_deployment
    
    log_info "USB稳定性系统部署完成！"
    show_usage
}

# 执行主函数
main
