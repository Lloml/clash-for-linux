#!/bin/bash

# 加载系统函数库(Only for RHEL Linux)
# [ -f /etc/init.d/functions ] && source /etc/init.d/functions

#################### 脚本初始化任务 ####################

# 获取脚本工作目录绝对路径
export Server_Dir=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)

# 加载.env变量文件
source $Server_Dir/.env

# 给二进制启动程序、脚本等添加可执行权限
chmod +x $Server_Dir/bin/*
chmod +x $Server_Dir/scripts/*
chmod +x $Server_Dir/tools/subconverter/subconverter



#################### 变量设置 ####################

Conf_Dir="$Server_Dir/conf"

#################### 任务执行 ####################

## 获取CPU架构信息
# Source the script to get CPU architecture
source $Server_Dir/scripts/get_cpu_arch.sh

# Check if we obtained CPU architecture
if [[ -z "$CpuArch" ]]; then
	echo "Failed to obtain CPU architecture"
	exit 1
fi

## 启动Clash服务
echo -e '\n正在启动Clash服务...'
if [[ $CpuArch =~ "x86_64" || $CpuArch =~ "amd64"  ]]; then
	$Server_Dir/bin/clash-linux-amd64 -d $Conf_Dir
elif [[ $CpuArch =~ "aarch64" ||  $CpuArch =~ "arm64" ]]; then
	$Server_Dir/bin/clash-linux-arm64 -d $Conf_Dir
elif [[ $CpuArch =~ "armv7" ]]; then
	$Server_Dir/bin/clash-linux-armv7 -d $Conf_Dir
else
	echo -e "\033[31m\n[ERROR] Unsupported CPU Architecture！\033[0m"
	exit 1
fi