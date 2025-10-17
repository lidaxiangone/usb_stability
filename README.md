# 下载脚本（如果可以通过网络）
wget -O /tmp/usb_stability_deploy.sh https://raw.githubusercontent.com/lidaxiangone/usb_stability/refs/heads/main/usb_stability_deploy.sh

# 或者直接创建文件并复制上述内容
vi /root/usb_stability_deploy.sh
# 复制上面脚本内容，保存退出

# 赋予执行权限
chmod +x /root/usb_stability_deploy.sh

# 执行部署脚本
/root/usb_stability_deploy.sh

#  一键执行命令（最简单方式）如果不想保存文件，可以直接执行：
curl -sL https://raw.githubusercontent.com/lidaxiangone/usb_stability/refs/heads/main/usb_stability_deploy.sh | sh
