#!/bin/bash

get_prefix(){
#读取路由公网IPv6前缀
 #重试计数 前缀
local count=-1
#重试小于等于?就继续循环
echo -e "\n获取路由公网 IPv6 前缀，重试时长120s" >$STDOUT
while [ -z "$prefix" -a $((++count)) -le 120 ];do
	#grep -v via：排除下级路由器dhcp客户端路由
	#grep "dev br-lan "：‘br-lan’的后面保留一个空格是为了完全匹配‘br-lan’，而不会匹配如‘br-lanxxxx...’这样的
	prefix=`ip -6 route | grep -E '^2\S*? dev '${prefix_from_iface:-br-lan}' ' | awk -F/ '{print $1}'`
	[ -z "$prefix" ] && sleep 1
done
[ -n "$prefix" ]
}

###更新路由器br-lan、pppoe-wan的动态域名IPv6
updateDomainNameFromRouter(){
echo -e "\n=============更新路由器================" >$STDOUT

local iface records record
local ifacetype ip_local index

for ifacetype in lan wan;do
	index=-1
	while uci -q get $configName.@$ifacetype[$((++index))] >/dev/null;do
		iface=$(uci -q get $configName.@$ifacetype[$index].iface)
		records=$(uci -q get $configName.@$ifacetype[$index].records)
		test -z "$iface" -o -z "$records" && continue
		
		#要更新的IPv6地址
		# 需要排除： scope global deprecated dynamic noprefixroute
		# OpenWrt 18.06+: scope global dynamic noprefixroute
		# OpenWrt 17: scope global noprefixroute dynamic
		
		if test "${OS_VERSION%%.*}" -le 17;then
			ip_local=`ip -6 addr show $iface 2>/dev/null | grep -E '\s*?inet6 2\S*? scope global noprefixroute dynamic ' | awk -F'\\\s+|/' '{print $3}'`
		else
			ip_local=`ip -6 addr show $iface 2>/dev/null | grep -E '\s*?inet6 2\S*? scope global dynamic noprefixroute ' | awk -F'\\\s+|/' '{print $3}'`
		fi
		#echo "===$iface===$ip_local======="
		if [ -n "$ip_local" ];then
			for record in $records;do
				if [ -n "$record" ];then
					if test "$exec_async" = 1;then
						run $ip_local $record &
					else
						run $ip_local $record
					fi
				fi
			done
		fi
		
	done
done


}

updateDomainNameFromRearHost(){

echo -e "=============更新下级主机===============" >$STDOUT

#获取2开头的网上邻居ipv6公网地址
#形式	2xxx:xxxx:xxxx:xxxx::xxxx dev br-lan lladdr xx:xx:xx:xx:xx:xx PERMANENT
local neigh_ipv6s=`ip -6 neigh show | grep -E '^2\S*? dev '${prefix_from_iface:-br-lan}' '`
#这一句获取数据中的MAC地址中包含的字母全部是小写


local mac duid records record
local index suffix neigh_ipv6 neigh_state

local index2=-1 ip_local ip_exists

# 邻居状态 neigh_nud 可能的值有： stale（过期，默认的）、reachable（可达）、permanent（永久），必须全小写
local neigh_nud=permanent

while uci -q get $configName.@host[$((++index2))] >/dev/null;do
	mac=$(uci -q get $configName.@host[$index2].mac)
	duid=$(uci -q get $configName.@host[$index2].duid)
	records=$(uci -q get $configName.@host[$index2].records)
	test -z "$duid" -o -z "$records" && continue

	printf "主机DUID>%-15s	主机记录集合>%s\n" $duid $records >$STDOUT

	#读取dhcp中的静态分配地址后缀
	index=-1 suffix=

	while uci -q get dhcp.@host[$((++index))] >/dev/null && ! uci -q get dhcp.@host[$index].duid | grep -qwi $duid;do :;done

	#dhcp配置文件中的静态地址分配节中的MAC地址，在LUCI中的下拉框中字母都为大写
	#网上邻居读取的是小写，配置网上邻居就也用小写
	uci -q get dhcp.@host[$index].duid | grep -qwi $duid &&	suffix=`uci -q get dhcp.@host[$index].hostid`
	

	if [ -n "$suffix" ];then

		#要更新的IPv6地址
		ip_local="$prefix$suffix"
		
		echo "合并的（新的）IPv6>>$ip_local" >$STDOUT

		#判断是否需要配置ARPv6
		if [ -n "$mac" ];then
			
			ip_exists=
			echo -e "\n-------更新ARPv6-------" >$STDOUT
			while read neigh_ipv6 neigh_state;do
				test -z "$neigh_ipv6" && continue
				
				echo -e "网上邻居 IPv6（$neigh_ipv6）\c" >$STDOUT
				
				if test "$neigh_ipv6" = "$ip_local";then
					echo -e "与新的一致，\c" >$STDOUT
					ip_exists=1
					if [ "$neigh_state" != "${neigh_nud^^}" ];then
						echo "状态由 ${neigh_state:-<null>} 更改为 ${neigh_nud^^}" >$STDOUT
						ip -6 neigh change $neigh_ipv6 lladdr $mac nud $neigh_nud dev ${prefix_from_iface:-br-lan}
					else
						echo "状态已经是 ${neigh_nud^^}" >$STDOUT
					fi
				
				else
					echo -e "与新的不同，\c" >$STDOUT
					# 只有状态为 permanent 时才需要更改
					if [ "$neigh_state" = "${neigh_nud^^}" ];then
						echo "状态由 ${neigh_nud^^} 更改为 REACHABLE" >$STDOUT
						ip -6 neigh change $neigh_ipv6 lladdr $mac nud reachable dev ${prefix_from_iface:-br-lan}
					else
						echo "状态已经不是 ${neigh_nud^^}" >$STDOUT
					fi
				fi
			
			
			done <<<"$(grep -iE "$mac|$ip_local" <<<"$neigh_ipv6s" | awk '{print $1,$6}')"
			
			if test -z "$ip_exists";then
				echo "添加新的 IPv6（$ip_local）网上邻居为 ${neigh_nud^^} 状态" >$STDOUT
				ip -6 neigh add $ip_local lladdr $mac nud $neigh_nud dev ${prefix_from_iface:-br-lan}
			fi
			
			ip -6 neigh show | grep -E '^2\S*? dev '${prefix_from_iface:-br-lan}' .*?'$mac  >$STDOUT
		else
			echo "这条更新记录未设置 MAC 地址" >$STDOUT
		fi
		
		#更新DNS----
		
		if [ -n "$records" ];then

			echo -e "\n------更新DNS-------" >$STDOUT
			
			for record in $records;do
				if [ -n "$record" ];then
					if test "$exec_async" = 1;then
						run $ip_local $record &
					else
						run $ip_local $record
					fi
				fi
			done
		fi
	else
		echo "未配置静态地址分配！" >$STDOUT
	fi

	echo "------------------------------------------" >$STDOUT

done

}



DIR=$(readlink -f $0)
DIR=${DIR%/*}

# 配置文件名称
configName=odhcpd-ddns


test ! -r /etc/config/$configName && {
	echo "不存在配置文件，请执行 install.sh，并编辑 /etc/config/$configName"
	exit 0
}


AccessKey=$(uci -q get $configName.globals.AccessKey)
AccessSecret=$(uci -q get $configName.globals.AccessSecret)
DN_suffix=$(uci -q get $configName.globals.DN_suffix)
TTL=$(uci -q get $configName.globals.TTL)
prefix_from_iface=$(uci -q get $configName.globals.prefix_from_iface)
exec_async=$(uci -q get $configName.globals.exec_async)
log_quient=$(uci -q get $configName.globals.log_quient)
log_retain_linecount=$(uci -q get $configName.globals.log_retain_linecount)

# 日志文件截断后保留的最大行数
if test -z "$log_retain_linecount";then
	log_retain_linecount=500
fi

# 日志文件保存位置
LOGFILE_PATH=/dev/null
STDOUT=/dev/null
if test "$log_quient" != 1;then
	LOGFILE_PATH=$DIR/log_ddns.log
	STDOUT=/proc/self/fd/1
	#test ! -L $STDOUT && ln -sf /proc/self/fd/1 $STDOUT
fi


# 系统版本信息：
OS_VERSION=$(grep '^VERSION=' /etc/os-release | awk -F'"|-' '{print $2}')

get_prefix

if test -n "$prefix";then
	echo -e '\n'====$(date "+%Y-%m-%d %H:%M:%S") >>$LOGFILE_PATH
	. $DIR/aliddns.sh
	
	
	updateDomainNameFromRouter
	updateDomainNameFromRearHost
	
	
	if test "$log_quient" != 1;then
		wait
		# 截断日志文件为不超过指定行数
		logFileLineCount=`[ -r $LOGFILE_PATH ] && wc -l $LOGFILE_PATH | awk '{print $1}' || echo 0`
		# echo $logFileLineCount
		logFileTruncateLineCount=$[logFileLineCount-log_retain_linecount]
		# echo $logFileTruncateLineCount
		[ "$logFileTruncateLineCount" -gt 0 ] && sed -i '1,'$logFileTruncateLineCount'd' $LOGFILE_PATH
	fi

fi

