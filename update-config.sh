#!/bin/bash
set -e

# 加载系统函数库(Only for RHEL Linux)
# [ -f /etc/init.d/functions ] && source /etc/init.d/functions

#################### 脚本初始化任务 ####################

# 获取脚本工作目录绝对路径
export Server_Dir=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)


# 检查.env文件是否存在
ENV_FILE=$Server_Dir/.env
if [ ! -f "$ENV_FILE" ]; then
  # 如果不存在，创建并写入内容
  echo "# Clash 订阅地址" > "$ENV_FILE"
  echo "export CLASH_URL=''" >> "$ENV_FILE"
  echo "export CLASH_SECRET=''" >> "$ENV_FILE"
  echo ".env 文件已创建并写入内容。"
fi



# 加载.env变量文件
source $Server_Dir/.env

# 给二进制启动程序、脚本等添加可执行权限
chmod +x $Server_Dir/bin/*
chmod +x $Server_Dir/scripts/*
chmod +x $Server_Dir/tools/subconverter/subconverter



#################### 变量设置 ####################

Conf_Dir="$Server_Dir/conf"
Templete_Dir="$Server_Dir/templete"
Temp_Dir="/tmp/clash-config"
Log_Dir="$Server_Dir/logs"

# 检查文件夹是否存在
if [ ! -d "$Temp_Dir" ]; then
  # 如果文件夹不存在，创建文件夹
  mkdir -p "$Temp_Dir"
  echo "文件夹 $Temp_Dir 已创建。"
fi

# 将 CLASH_URL 变量的值赋给 URL 变量，并检查 CLASH_URL 是否为空
URL=${CLASH_URL:?Error: CLASH_URL variable is not set or empty}



#################### 函数定义 ####################

# 自定义action函数，实现通用action功能
success() {
	echo -en "\\033[60G[\\033[1;32m  OK  \\033[0;39m]\r"
	return 0
}

failure() {
	local rc=$?
	echo -en "\\033[60G[\\033[1;31mFAILED\\033[0;39m]\r"
	[ -x /bin/plymouth ] && /bin/plymouth --details
	return $rc
}

action() {
	local STRING rc

	STRING=$1
	echo -n "$STRING "
	shift
	"$@" && success $"$STRING" || failure $"$STRING"
	rc=$?
	echo
	return $rc
}

# 判断命令是否正常执行 函数
if_success() {
	local ReturnStatus=$3
	if [ $ReturnStatus -eq 0 ]; then
		action "$1" /bin/true
	else
		action "$2" /bin/false
		exit 1
	fi
}



#################### 任务执行 ####################

## 临时取消环境变量
unset http_proxy
unset https_proxy
unset no_proxy
unset HTTP_PROXY
unset HTTPS_PROXY
unset NO_PROXY


## Clash 订阅地址检测及配置文件下载
# 检查url是否有效
echo -e '\n正在检测订阅地址...'
Text1="Clash订阅地址可访问！"
Text2="Clash订阅地址不可访问！"
#curl -o /dev/null -s -m 10 --connect-timeout 10 -w %{http_code} $URL | grep '[23][0-9][0-9]' &>/dev/null
curl -o /dev/null -L -k -sS --retry 5 -m 10 --connect-timeout 10 -w "%{http_code}" $URL | grep -E '^[23][0-9]{2}$' &>/dev/null
ReturnStatus=$?
if_success $Text1 $Text2 $ReturnStatus

# 拉取更新config.yml文件
echo -e '\n正在下载Clash配置文件...'
Text3="配置文件config.yaml下载成功！"
Text4="配置文件config.yaml下载失败，退出启动！"

# 尝试使用curl进行下载
curl -L -k -sS --retry 5 -m 10 -o $Temp_Dir/clash.yaml $URL
ReturnStatus=$?
if [ $ReturnStatus -ne 0 ]; then
	# 如果使用curl下载失败，尝试使用wget进行下载
	for i in {1..10}
	do
		wget -q --no-check-certificate -O $Temp_Dir/clash.yaml $URL
		ReturnStatus=$?
		if [ $ReturnStatus -eq 0 ]; then
			break
		else
			continue
		fi
	done
fi
if_success $Text3 $Text4 $ReturnStatus

# 重命名clash配置文件
\cp -a $Temp_Dir/clash.yaml $Temp_Dir/clash_config.yaml


## 判断订阅内容是否符合clash配置文件标准，尝试转换（当前不支持对 x86_64 以外的CPU架构服务器进行clash配置文件检测和转换，此功能将在后续添加）
if [[ $CpuArch =~ "x86_64" || $CpuArch =~ "amd64"  ]]; then
	echo -e '\n判断订阅内容是否符合clash配置文件标准:'
	bash $Server_Dir/scripts/clash_profile_conversion.sh
	sleep 3
fi


## Clash 配置文件重新格式化及配置
# 取出代理相关配置 
#sed -n '/^proxies:/,$p' $Temp_Dir/clash.yaml > $Temp_Dir/proxy.txt
sed -n '/^proxies:/,$p' $Temp_Dir/clash_config.yaml > $Temp_Dir/proxy.txt

# 合并形成新的config.yaml
cat $Templete_Dir/templete_config.yaml > $Temp_Dir/config.yaml
cat $Temp_Dir/proxy.txt >> $Temp_Dir/config.yaml
cp $Temp_Dir/config.yaml $Conf_Dir/

echo "$Temp_Dir/config.yaml $Conf_Dir/"

# Configure Clash Dashboard
Work_Dir=$(cd $(dirname $0); pwd)
Dashboard_Dir="${Work_Dir}/dashboard/public"
sed -ri "s@^# external-ui:.*@external-ui: ${Dashboard_Dir}@g" $Conf_Dir/config.yaml
if [ -z "$CLASH_SECRET" ]; then
    sed -r -i '/^secret: /s@.*@@' $Conf_Dir/config.yaml
else
    sed -r -i '/^secret: /s@(secret: ).*@\1'${CLASH_SECRET}'@g' $Conf_Dir/config.yaml
fi
systemctl restart clash.service
