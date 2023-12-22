#!/bin/bash

configure() {
    config_file=/var/lib/pagermaid/data/config.yml
    echo "生成配置文件中 . . ."
    cp /var/lib/pagermaid/config.gen.yml $config_file
    printf "请输入应用程序 api_id："
    read -r api_id <&1
    sed -i "s/ID_HERE/$api_id/" $config_file
    printf "请输入应用程序 api_hash："
    read -r api_hash <&1
    sed -i "s/HASH_HERE/$api_hash/" $config_file
}

login_screen() {
    python3 -m pagermaid
    systemctl_reload
}

systemctl_reload() {
    echo "正在写入系统进程守护 . . ."
    sudo cat <<'TEXT' > /etc/systemd/system/pagermaid.service
    [Unit]
    Description=PagerMaid-Pyro Telegram Utility Daemon
    After=network.target

    [Install]
    WantedBy=multi-user.target

    [Service]
    Type=simple
    WorkingDirectory=/var/lib/pagermaid
    ExecStart=$PYV -m pagermaid
    Restart=always
TEXT
    systemctl daemon-reload >>/dev/null 2>&1
    systemctl start pagermaid >>/dev/null 2>&1
    systemctl enable pagermaid >>/dev/null 2>&1
}

start_installation() {
    check_sys
    check_root
    check_ip

    echo "系统检测通过。"
    install_python
    git clone https://github.com/TeamPGM/PagerMaid-Pyro.git
    
    cd /var/lib/pagermaid
    pip3 install -r requirements.txt
    mkdir -p /var/lib/pagermaid/data
    configure
    login_screen
    echo "PagerMaid 已经安装完毕 在telegram对话框中输入 ,help 并发送查看帮助列表"
}

cleanup() {
    if [ ! -x "/var/lib/pagermaid" ]; then
        echo "目录不存在不需要卸载。"
    else
        echo "正在关闭 PagerMaid . . ."
        systemctl disable pagermaid >>/dev/null 2>&1
        systemctl stop pagermaid >>/dev/null 2>&1
        echo "正在删除 PagerMaid 文件 . . ."
        rm -rf /etc/systemd/system/pagermaid.service >>/dev/null 2>&1
        rm -rf /var/lib/pagermaid >>/dev/null 2>&1
        echo "卸载完成 . . ."
    fi
}

shon_online() {
    echo "一键脚本出现任何问题请转手动搭建！ https://xtaolabs.com/"
    echo ""
    echo ""
    echo "请选择您需要进行的操作:"
    echo "  1) 安装 PagerMaid"
    echo "  2) 卸载 PagerMaid"
    echo "  3) 退出脚本"
    echo ""
    echo "     Version：2.0"
    echo ""
    echo -n "请输入编号: "
    read N
    case $N in
    1) start_installation ;;
    2) cleanup ;;
    3) exit ;;
    *) echo "Wrong input!" ;;
    esac
}

check_sys
shon_online