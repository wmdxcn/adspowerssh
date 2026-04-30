#!/bin/bash

# 1. 检查权限
[[ $EUID -ne 0 ]] && echo "请使用 root 权限运行此脚本" && exit 1

# 2. 自动检测架构并下载最新版 realm
ARCH=$(uname -m)
case ${ARCH} in
    x86_64)  FILE="realm-x86_64-unknown-linux-musl.tar.gz" ;;
    aarch64) FILE="realm-aarch64-unknown-linux-musl.tar.gz" ;;
    *) echo "不支持的架构: ${ARCH}"; exit 1 ;;
esac

echo "正在下载适合 ${ARCH} 的 realm..."
URL=$(curl -s https://github.com | grep "browser_download_url" | grep "${FILE}" | cut -d '"' -f 4)
wget -qO realm.tar.gz "${URL}"
tar -xvf realm.tar.gz && chmod +x realm
mv realm /usr/bin/realm
rm -f realm.tar.gz

# 3. 创建配置目录和首次安装引导
mkdir -p /etc/realm
echo "--- 首次安装引导：配置第一条中转线路 ---"
read -p "请输入本地监听端口 (默认 29208): " LISTENER_PORT
LISTENER_PORT=${LISTENER_PORT:-29208}
read -p "请输入远程目标 IP: " REMOTE_IP
read -p "请输入远程目标端口: " REMOTE_PORT

cat << TOML > /etc/realm/config.toml
[[endpoints]]
listen = "0.0.0.0:${LISTENER_PORT}"
remote = "${REMOTE_IP}:${REMOTE_PORT}"
TOML

# 4. 创建 Systemd 服务
cat << SERVICE > /etc/systemd/system/realm.service
[Unit]
Description=Realm Port Forwarding Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/realm
ExecStart=/usr/bin/realm/realm -c /etc/realm/config.toml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

# 5. 启动服务
systemctl daemon-reload
systemctl enable realm
systemctl start realm

echo "-----------------------------------------------"
echo "安装成功并已启动！"
echo "配置文件路径: /etc/realm/config.toml"
echo "管理命令:"
echo "  查看状态: systemctl status realm"
echo "  重启服务: systemctl restart realm"
echo "  停止服务: systemctl stop realm"
echo "-----------------------------------------------"
