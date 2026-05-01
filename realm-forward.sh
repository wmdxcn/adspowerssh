#!/bin/bash

# --- 配置区 ---
GITHUB_USER="wmdxcn"
REPO_NAME="adspowerssh"
BRANCH="main"
# --------------

# 1. 权限检查
[[ $EUID -ne 0 ]] && echo "请使用 root 权限运行此脚本" && exit 1

# 2. 自动检测架构
arch=$(uname -m)
case ${arch} in
    x86_64)  
        file="realm-x86_64-unknown-linux-gnu.tar.gz" 
        ;;
    aarch64) 
        file="realm-aarch64-unknown-linux-gnu.tar.gz" 
        ;;
    *) 
        echo "不支持的架构: ${arch}"
        exit 1 
        ;;
esac

# 3. 构造下载链接 (指向你项目中的 reaml 目录)
DOWNLOAD_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${REPO_NAME}/${BRANCH}/reaml/${file}"

echo "检测到架构: ${arch}"
echo "正在从项目下载: ${file}..."

# 4. 下载与环境清理
# 清理当前目录旧文件和系统残留，防止 mv 命令逻辑走偏
rm -f realm.tar.gz reaml realm
rm -rf /usr/bin/realm  # 彻底删除可能存在的旧目录或文件

wget -qO realm.tar.gz "${DOWNLOAD_URL}"
if [ $? -ne 0 ]; then


    echo "下载失败，请检查链接或项目权限: ${DOWNLOAD_URL}"
    exit 1
fi

# 5. 解压与路径规范化
tar -xvf realm.tar.gz

# 核心逻辑：无论解压出来是 reaml 还是 realm，统一强制重命名为 /usr/bin/realm (文件)
if [ -f "reaml" ]; then
    mv reaml /usr/bin/realm
elif [ -f "realm" ]; then
    mv realm /usr/bin/realm
else
    # 兜底方案：寻找解压出的可执行文件
    executable_file=$(find . -maxdepth 1 -type f -executable | head -n 1)
    if [ -n "$executable_file" ]; then
        mv "$executable_file" /usr/bin/realm
    else
        echo "错误：未在压缩包内找到可执行文件。"
        exit 1
    fi
fi

chmod +x /usr/bin/realm
rm -f realm.tar.gz

# 6. 配置目录与初始规则
CONFIG_PATH="/etc/realm/config.toml"
mkdir -p /etc/realm

if [ ! -f "$CONFIG_PATH" ]; then
    echo "--- 首次安装引导 ---"
    read -p "请输入本地监听端口 (默认 29208): " listener_port
    listener_port=${listener_port:-29208}
    read -p "请输入远程目标 IP: " remote_ip
    read -p "请输入远程目标端口: " remote_port

    cat << EOF > "$CONFIG_PATH"
[[endpoints]]
listen = "0.0.0.0:${listener_port}"
remote = "${remote_ip}:${remote_port}"
EOF
fi

# 7. 创建 Systemd 服务
cat << EOF > /etc/systemd/system/realm.service
[Unit]
Description=realm port forwarding service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/realm
ExecStart=/usr/bin/realm -c $CONFIG_PATH
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 8. 启动服务
systemctl daemon-reload
systemctl enable realm --now

# 9. 结果输出
echo "-----------------------------------------------"
echo "安装成功！"
echo "主程序路径: /usr/bin/realm (已自动重命名)"
echo "配置文件路径: ${CONFIG_PATH}"
echo "-----------------------------------------------"
echo "管理命令:"
echo "  查看状态: systemctl status realm"
echo "  修改配置: vi ${CONFIG_PATH}"
echo "  查看日志: journalctl -u realm -f"
echo "-----------------------------------------------"
