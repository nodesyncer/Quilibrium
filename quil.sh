#!/bin/bash

function install_node() {
	mem_size=$(free -g | grep "Mem:" | awk '{print $2}')
	swap_size=$(free -g | grep "Swap:" | awk '{print $2}')
	desired_swap_size=$((mem_size * 2))
	if ((desired_swap_size >= 32)); then
	    desired_swap_size=32
	fi
	if ((swap_size < desired_swap_size)) && ((swap_size < 32)); then
	    echo "当前swap大小不足。正在将swap大小设置为 $desired_swap_size GB..."
	    sudo swapoff -a
	    sudo fallocate -l ${desired_swap_size}G /swapfile
	    sudo chmod 600 /swapfile
	    sudo mkswap /swapfile
	    sudo swapon /swapfile
	    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
	
	    echo "Swap大小已设置为 $desired_swap_size GB。"
	else
	    echo "当前swap大小已经满足要求或大于等于32GB，无需改动。"
	fi
    sudo apt update
    sudo apt install -y git ufw bison screen binutils gcc make bsdmainutils jq coreutils
	echo -e "\n\n# set for Quil" | sudo tee -a /etc/sysctl.conf
	echo "net.core.rmem_max=600000000" | sudo tee -a /etc/sysctl.conf
	echo "net.core.wmem_max=600000000" | sudo tee -a /etc/sysctl.conf
	sudo sysctl -p
	bash < <(curl -s -S -L https://raw.githubusercontent.com/moovweb/gvm/master/binscripts/gvm-installer)
	source $HOME/.gvm/scripts/gvm
	gvm install go1.4 -B
	gvm use go1.4
	export GOROOT_BOOTSTRAP=$GOROOT
	gvm install go1.17.13
	gvm use go1.17.13
	export GOROOT_BOOTSTRAP=$GOROOT
	gvm install go1.20.2
	gvm use go1.20.2
	
	# Contabo 的机器如果这里报错可以换成 https://github.com/a3165458/ceremonyclient.git
	git clone https://source.quilibrium.com/quilibrium/ceremonyclient.git
	cd $HOME/ceremonyclient/
	git switch release
    sudo tee /lib/systemd/system/ceremonyclient.service > /dev/null <<EOF
[Unit]
Description=Ceremony Client Go App Service
[Service]
Type=simple
Restart=always
RestartSec=5s
WorkingDirectory=$HOME/ceremonyclient/node
Environment=GOEXPERIMENT=arenas
ExecStart=$HOME/ceremonyclient/node/node-1.4.18-linux-amd64
[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable ceremonyclient
    sudo systemctl start ceremonyclient
	rm $HOME/go/bin/qclient
	cd $HOME/ceremonyclient/client
	GOEXPERIMENT=arenas go build -o $HOME/go/bin/qclient main.go
	echo "部署完成"
}

function backup_key(){
    sudo chown -R $USER:$USER $HOME/ceremonyclient/node/.config/
	file_path_keys="$HOME/ceremonyclient/node/.config/keys.yml"
	file_path_config="$HOME/ceremonyclient/node/.config/config.yml"
	
	if [ -f "$file_path_keys" ]; then
	    echo "keys文件已生成，路径为: $file_path_keys，请尽快备份"
	else
	    echo "keys文件未生成，请等待..."
	fi
	if [ -f "$file_path_config" ]; then
	    echo "config文件已生成，路径为: $file_path_config，请尽快备份"
	else
	    echo "config文件未生成，请等待..."
	fi
}

function view_logs(){
	sudo journalctl -u ceremonyclient.service -f --no-hostname -o cat
}

function view_status(){
	sudo systemctl status ceremonyclient
}

function stop_node(){
	sudo systemctl stop ceremonyclient
	echo "quil 节点已停止"
}

function start_node(){
	sudo systemctl start ceremonyclient
	echo "quil 节点已启动"
}

function uninstall_node(){
    sudo systemctl stop ceremonyclient
    screen -ls | grep -Po '\t\d+\.quil\t' | grep -Po '\d+' | xargs -r kill
	rm -rf $HOME/ceremonyclient
	rm -rf $HOME/check_and_restart.sh
	echo "卸载完成。"
}

function check_node_info(){
	echo "当前版本："
	cat ~/ceremonyclient/node/config/version.go | grep -A 1 'func GetVersion() \[\]byte {' | grep -Eo '0x[0-9a-fA-F]+' | xargs printf '%d.%d.%d'
}

function download_snap(){
    if wget -P $HOME/ https://snapshots.nodesyncer.xyz/quilibrium/store_latest.zip ;
    then
		if ! command -v unzip &> /dev/null
		then
		    sudo apt-get update && sudo apt-get install -y unzip
		    if [ $? -eq 0 ]; then
		        echo "unzip has been successfully installed."
		    else
		        echo "Failed to install unzip. Please check your package manager settings."
		        exit 1
		    fi
		else
		    echo "unzip is already installed."
		fi
        mv $HOME/store_latest.zip $HOME/ceremonyclient/node/.config/
		cd $HOME/ceremonyclient/node/.config/
		stop_node && sudo unzip -o store_latest.zip && rm store_latest.zip &&. start_node
    else
        echo "下载失败。"
        exit 1
    fi
}

function update_repair(){
	echo "快照文件较大，下载需要较长时间，请保持电脑屏幕不要熄灭"
    stop_node
    cp $HOME/ceremonyclient/node/.config/REPAIR $HOME/REPAIR.bak
    if wget -O $HOME/ceremonyclient/node/.config/REPAIR 'https://2040319038-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FwYHoFaVat0JopE1zxmDI%2Fuploads%2FJL4Ytu5OIWHbisIbZs8v%2FREPAIR?alt=media&token=d080b681-ee26-470c-baae-4723bcf018a3' ;
    then
    	start_node
    	echo "REPAIR已更新..."
    else
        echo "下载失败。"
        exit 1
    fi
}

function check_balance(){
	source $HOME/.gvm/scripts/gvm
	gvm use go1.20.2
	cd "$HOME/ceremonyclient/client"
	FILE="$HOME/ceremonyclient/client/qclient"
	
	if [ ! -f "$FILE" ]; then
	    echo "文件不存在，正在尝试构建..."
	    GOEXPERIMENT=arenas go build -o qclient main.go
	    if [ $? -eq 0 ]; then
	        echo "余额："
	        ./qclient token balance
	    else
	        echo "构建失败。"
	        exit 1
	    fi
	else
		echo "余额："
	    ./qclient token balance
	fi
}

function install_grpc(){
	go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest
}

function check_heal(){
	sudo journalctl -u ceremonyclient.service --no-hostname --since "today" | awk '/"current_frame"/ {print $1, $2, $3, $7}'
	echo "提取了当天的日志，如果current_frame一直在增加，说明程序运行正常"
}

function update_quil(){
	cd ceremonyclient
	git remote remove origin
	git remote add origin https://source.quilibrium.com/quilibrium/ceremonyclient.git
	git pull
	git reset --hard v1.4.18-p2
	sudo systemctl restart ceremonyclient
}

function cpu_limited_rate(){
    read -p "输入每个CPU允许quil使用占比(如60%输入0.6，最大1):" cpu_rate
    comparison=$(echo "$cpu_rate >= 1" | bc)
    if [ "$comparison" -eq 1 ]; then
        cpu_rate=1
    fi
    cpu_core=$(lscpu | grep '^CPU(s):' | awk '{print $2}')
    limit_rate=$(echo "scale=2; $cpu_rate * $cpu_core * 100" | bc)
    echo "最终限制的CPU使用率为：$limit_rate%"
    echo "正在重启，请稍等..."
    stop_node
    sudo rm -f /lib/systemd/system/ceremonyclient.service
    sudo tee /lib/systemd/system/ceremonyclient.service > /dev/null <<EOF
[Unit]
Description=Ceremony Client Go App Service
[Service]
Type=simple
Restart=always
RestartSec=5s
WorkingDirectory=$HOME/ceremonyclient/node
Environment=GOEXPERIMENT=arenas
ExecStart=$HOME/ceremonyclient/node/node-1.4.18-linux-amd64
CPUQuota=$limit_rate%
[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable ceremonyclient
    sudo systemctl start ceremonyclient
    echo "quil 节点已启动"
}

function main_menu() {
	while true; do
	    clear
	    echo "===================Quilibrium 一键部署脚本==================="
	    echo "请选择要执行的操作:"
	    echo "1. 部署节点 install_node"
	    echo "2. 提取秘钥 backup_key"
	    echo "3. 查看状态 view_status"
	    echo "4. 查看日志 view_logs"
	    echo "5. 停止节点 stop_node"
	    echo "6. 启动节点 start_node"
	    echo "7. 节点信息 check_node_info"
	    echo "8. 卸载节点 uninstall_node"
	    echo "9. 查询余额 check_balance"
	    echo "10. 下载快照 download_snap"
	    echo "11. 运行状态 check_heal"
	    echo "12. 升级程序 update_quil"
	    echo "13. 限制CPU cpu_limited_rate"
	    echo "0. 退出脚本 exit"
	    read -p "请输入选项: " OPTION
	
	    case $OPTION in
	    1) install_node ;;
	    2) backup_key ;;
	    3) view_status ;;
	    4) view_logs ;;
	    5) stop_node ;;
	    6) start_node ;;
	    7) check_node_info ;;
	    8) uninstall_node ;;
	    9) check_balance ;;
	    10) download_snap ;;
	    11) check_heal ;;
	    12) update_quil ;;
	    13) cpu_limited_rate ;;
	    0) echo "退出脚本。"; exit 0 ;;
	    *) echo "无效选项，请重新输入。"; sleep 3 ;;
	    esac
	    echo "按任意键返回主菜单..."
        read -n 1
    done
}

main_menu
