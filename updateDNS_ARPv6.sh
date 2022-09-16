#!/bin/bash

###更新路由器br-lan、pppoe-wan的动态域名IPv6
updateDomainNameFromRouter(){
_echo "=============更新路由器================"

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

_echo(){
	echo -e "$@" >$STDOUT
	echo -e "$@" >>$LOGFILE_PATH
}

_printf(){
	printf "$@" >$STDOUT
	printf "$@" >>$LOGFILE_PATH
}

updateDomainNameFromRearHost(){
_echo "=============更新下级主机==============="

#网上邻居ipv6公网地址
local neigh_ipv6s

# 配置参数
local mac router duid records dhcpv6_interface dhcpv6_device
local index suffix
local neigh_ipv6 neigh_router neigh_state

local index2=-1 ip_local ip_exists _reg_dhcpv6_device record _out_

# 邻居状态 neigh_nud 可能的值有： stale（过期，默认的）、reachable（可达）、permanent（永久），必须全小写
local neigh_nud=permanent

#重试计数 前缀
local count

while uci -q get $configName.@host[$((++index2))] >/dev/null;do
	duid=$(uci -q get $configName.@host[$index2].duid)
	records=$(uci -q get $configName.@host[$index2].records)
	
	test -z "$duid" -o -z "$records" && continue
	
	dhcpv6_interface=$(uci -q get $configName.@host[$index2].dhcpv6_interface)
	
	test -z "$dhcpv6_interface" && dhcpv6_interface=$default_dhcpv6_interface

	dhcpv6_device=$(uci -q get network.$dhcpv6_interface.device)
	test -z "$dhcpv6_device" && continue
	_reg_dhcpv6_device=$(sed 's|\.|\\&|g' <<<"$dhcpv6_device")
	
	if test -z "${device_ipv6prefix[$dhcpv6_device]}";then
	
		#读取路由公网IPv6前缀
		#重试小于等于?就继续循环
		_echo "获取路由 $dhcpv6_device device 公网 IPv6 前缀，重试时长120s\c "
		count=-1
		while [ -z "${device_ipv6prefix[$dhcpv6_device]}" -a $((++count)) -le 120 ];do
			#grep -v via：排除下级路由器dhcp客户端路由
			#grep "dev br-lan "：‘br-lan’的后面保留一个空格是为了完全匹配‘br-lan’，而不会匹配如‘br-lanxxxx...’这样的
			device_ipv6prefix[$dhcpv6_device]=`ip -6 route | grep -E '^2\S*? dev '$_reg_dhcpv6_device' ' | awk -F/ '{print $1}'`
			[ -z "${device_ipv6prefix[$dhcpv6_device]}" ] && sleep 1
		done
		[ -z "${device_ipv6prefix[$dhcpv6_device]}" ] && {
			_echo "；获取失败，继续下个客户端"
			continue
		} || {
			_echo "；获取成功，前缀为 ${device_ipv6prefix[$dhcpv6_device]}"
		}
	else
		_echo "路由 $dhcpv6_device device 已获取公网 IPv6 前缀 ${device_ipv6prefix[$dhcpv6_device]}"
	fi

	mac=$(uci -q get $configName.@host[$index2].mac)
	_printf "主机DUID>%-15s	主机MAC>%-15s	主机记录集合>%s\n" $duid ${mac:-<null>} $records
	router=$(uci -q get $configName.@host[$index2].router)
	test "$router" = 1 && router=router || router=

	#读取dhcp中的静态分配地址后缀
	index=-1 suffix=

	while uci -q get dhcp.@host[$((++index))] >/dev/null && ! uci -q get dhcp.@host[$index].duid | grep -qwi $duid;do :;done

	#dhcp配置文件中的静态地址分配节中的MAC地址，在LUCI中的下拉框中字母都为大写
	#网上邻居读取的是小写，配置网上邻居就也用小写
	uci -q get dhcp.@host[$index].duid | grep -qwi $duid &&	suffix=`uci -q get dhcp.@host[$index].hostid`
	

	if [ -n "$suffix" ];then

		#要更新的IPv6地址
		ip_local="${device_ipv6prefix[$dhcpv6_device]}$suffix"
		
		_echo "合并的（新的）IPv6>>$ip_local"

		#判断是否需要配置ARPv6
		if [ -n "$mac" ];then
		
			#获取2开头的网上邻居ipv6公网地址
			#形式	2xxx:xxxx:xxxx:xxxx::xxxx dev br-lan lladdr xx:xx:xx:xx:xx:xx PERMANENT
			#这一句获取数据中的MAC地址中包含的字母全部是小写
			neigh_ipv6s=`ip -6 neigh show | grep -E '^2\S*? dev '$_reg_dhcpv6_device' '`
			ip_exists=
			_echo "\n-------更新ARPv6-------"
			while read neigh_ipv6 neigh_router neigh_state;do
				#test -z "$neigh_ipv6" && continue
				# 排除非公网 IPv6 地址
				# 	OpenWrt 客户端及其客户端的 MAC 地址会有非公网 IPv6 邻居记录，类似下面，需要排除
				# 	fd7f::6 dev br-lan.1 lladdr c8:5b:a0:ea:1f:21 router STALE
				# 	fe80::ca5b:a0ff:feea:1f21 dev br-lan.1 lladdr c8:5b:a0:ea:1f:21 router STALE
				! grep -iEq "^2\S*" <<<"$neigh_ipv6" && continue
				
				test "$neigh_router" != router && neigh_router=
				
				_echo "网上邻居 IPv6（$neigh_ipv6）\c"
				
				if test "$neigh_ipv6" = "$ip_local";then
					_echo "与新的一致，\c"
					ip_exists=1
					if [ "$neigh_state" != "${neigh_nud^^}" -o "$neigh_router" != "$router" ];then
						_echo "状态由 $neigh_router ${neigh_state:-<null>} 更改为 $router ${neigh_nud^^}"
						ip -6 neigh change $neigh_ipv6 lladdr $mac $router nud $neigh_nud dev $dhcpv6_device
					else
						_echo "状态已经是 $neigh_router ${neigh_nud^^}"
					fi
				
				else
					_echo "与新的不同，\c"
					# 只有状态为 permanent 时才需要更改
					if [ "$neigh_state" = "${neigh_nud^^}" ];then
						_echo "状态由 $neigh_router ${neigh_nud^^} 更改为 $router REACHABLE"
						ip -6 neigh change $neigh_ipv6 lladdr $mac $router nud reachable dev $dhcpv6_device
					else
						_echo "状态已经不是 $neigh_router ${neigh_nud^^}"
					fi
				fi
			done <<<"$(grep -iE "(\s+$mac|$ip_local)\s+" <<<"$neigh_ipv6s" | awk '{print $1,$((NF-1)),$NF}')"
			
			if test -z "$ip_exists";then
				_echo "添加新的 IPv6（$ip_local）网上邻居为 $router ${neigh_nud^^} 状态"
				ip -6 neigh add $ip_local lladdr $mac $router nud $neigh_nud dev $dhcpv6_device
			fi
			
			_out_="$(ip -6 neigh show | grep -iE '^2\S*? dev '$_reg_dhcpv6_device' .*?'$mac)"
			echo "$_out_" >$STDOUT
			echo "$_out_" >>$LOGFILE_PATH
		else
			_echo "这条更新记录未设置 MAC 地址"
		fi
		
		#更新DNS----
		
		if [ -n "$records" ];then

			_echo -e "\n------更新DNS-------"
			
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
		_echo "未配置静态地址分配！"
	fi

	_echo "------------------------------------------"

done

}



DIR=$(readlink -f $0)
DIR=${DIR%/*}

# 配置文件名称
configName=odhcpd-ddns


test ! -r /etc/config/$configName && {
	_echo "不存在配置文件，请执行 install.sh，并编辑 /etc/config/$configName"
	exit 0
}


AccessKey=$(uci -q get $configName.globals.AccessKey)
AccessSecret=$(uci -q get $configName.globals.AccessSecret)
DN_suffix=$(uci -q get $configName.globals.DN_suffix)
TTL=$(uci -q get $configName.globals.TTL)
default_dhcpv6_interface=$(uci -q get $configName.globals.default_dhcpv6_interface)
exec_async=$(uci -q get $configName.globals.exec_async)
log_quient=$(uci -q get $configName.globals.log_quient)
log_retain_linecount=$(uci -q get $configName.globals.log_retain_linecount)
terminal_quient=$(uci -q get $configName.globals.terminal_quient)

if test -z "$default_dhcpv6_interface";then
	default_dhcpv6_interface=lan
fi


# 日志文件截断后保留的最大行数
if test -z "$log_retain_linecount";then
	log_retain_linecount=300
fi

# 日志文件保存位置
LOGFILE_PATH=/dev/null
if test "$log_quient" != 1;then
	LOGFILE_PATH=$DIR/log_ddns.log
fi

# 终端输出位置
STDOUT=/dev/null
if test "$terminal_quient" != 1;then
	STDOUT=/proc/self/fd/1
	#test ! -L $STDOUT && ln -sf /proc/self/fd/1 $STDOUT
fi

# 系统版本信息：
OS_VERSION=$(grep '^VERSION=' /etc/os-release | awk -F'"|-' '{print $2}')

# 关联数组，设备-ipv6前缀
declare -A device_ipv6prefix

echo -e "\n;=================$(date "+%Y-%m-%d %H:%M:%S")====================" >>$LOGFILE_PATH
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


