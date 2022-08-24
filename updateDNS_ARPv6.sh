#!/bin/bash

get_prefix(){
#读取路由公网IPv6前缀
 #重试计数 前缀
local count=-1
#重试小于等于?就继续循环
while [ -z "$prefix" -a $((++count)) -le 120 ];do
	#grep -v via：排除下级路由器dhcp客户端路由
	#grep "dev br-lan "：‘br-lan’的后面保留一个空格是为了完全匹配‘br-lan’，而不会匹配如‘br-lanxxxx...’这样的
	prefix=`ip -6 route | grep -E '^2\S*? dev '${prifix_from_iface:-br-lan}' ' | awk -F/ '{print $1}'`
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
	while uci -q get ddns-odhcpd.@$ifacetype[$((++index))] >/dev/null;do
		iface=$(uci -q get ddns-odhcpd.@$ifacetype[$index].iface)
		records=$(uci -q get ddns-odhcpd.@$ifacetype[$index].records)
		test -z "$iface" -o -z "$records" && continue
		
		#要更新的IPv6地址
		# 需要排除： scope global deprecated dynamic noprefixroute
		ip_local=`ip -6 addr show $iface 2>/dev/null | grep -E '\s*?inet6 2\S*? scope global dynamic ' | awk -F'\\\s+|/' '{print $3}'`
		
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

echo -e "\n=============更新下级主机===============" >$STDOUT

#获取2开头的网上邻居ipv6公网地址
#形式	2xxx:xxxx:xxxx:xxxx::xxxx dev br-lan lladdr xx:xx:xx:xx:xx:xx PERMANENT
local neigh_ipv6s=`ip -6 neigh show | grep -E '^2\S*? dev '${prefix_from_iface:-br-lan}' '`
#这一句获取数据中的MAC地址中包含的字母全部是小写


local mac records record
local index suffix neigh_ipv6 neigh_state

local index2=-1 neigh_nud ip_local
while uci -q get ddns-odhcpd.@host[$((++index2))] >/dev/null;do
	mac=$(uci -q get ddns-odhcpd.@host[$index2].mac)
	records=$(uci -q get ddns-odhcpd.@host[$index2].records)
	neigh_nud=$(uci -q get ddns-odhcpd.@host[$index2].neigh_nud)
	test -z "$mac" && continue
	test -z "$neigh_nud" -a -z "$records" && continue

	echo -e "\n------------------------------------------" >$STDOUT

	printf "\n主机MAC地址>%-15s	neigh_nud>%-2s	主机记录集合>%s\n" $mac ${neigh_nud:-<null>} ${records:-<null>} >$STDOUT


	#读取dhcp中的静态分配地址后缀
	index=-1 suffix=

	while uci -q get dhcp.@host[$((++index))] >/dev/null && test "$(uci -q get dhcp.@host[$index].mac)" != "${mac^^}";do :;done

	#dhcp配置文件中的静态地址分配节中的MAC地址，在LUCI中的下拉框中字母都为大写
	#网上邻居读取的是小写，配置网上邻居就也用小写
	test "$(uci -q get dhcp.@host[$index].mac)" = "${mac^^}" &&	suffix=`uci -q get dhcp.@host[$index].hostid`
	

	if [ -n "$suffix" ];then

		#要更新的IPv6地址
		ip_local="$prefix$suffix"
		
		echo "合并的IPv6>>$ip_local" >$STDOUT

		#判断是否需要配置ARPv6
		if [ -n "$neigh_nud" ];then
			
			#更新ARPv6------
			#筛选并截取地址
			eval `grep -i "$mac" <<<"$neigh_ipv6s" | awk '{printf("neigh_ipv6=%s;neigh_state=%s",$1,$6)}'`
			echo -e "\n----更新ARPv6-------\n原邻居IPv6>$neigh_ipv6 原邻居状态> $neigh_state" >$STDOUT
			
			if [ -z "$neigh_ipv6" ];then
				# 可能存在无 mac 地址的记录，但该记录的 IP 地址却与 $ip_local 相同
				eval `grep "$ip_local" <<<"$neigh_ipv6s" | awk '{printf("neigh_ipv6=%s;neigh_state=",$1)}'`
			fi
			
			if [ -n "$neigh_ipv6" -a "$neigh_ipv6" != "$ip_local" ];then
				echo "0-删除旧的IPv6与新IPv6不匹配的网上邻居" >$STDOUT
				ip -6 neigh del $neigh_ipv6 dev ${prefix_from_iface:-br-lan}
				neigh_ipv6=
			fi
			
			if [ -z "$neigh_ipv6" ];then
				echo "1-添加IPv6网上邻居为 ${neigh_nud^^} 状态" >$STDOUT
				ip -6 neigh add $ip_local lladdr $mac nud $neigh_nud dev ${prefix_from_iface:-br-lan}
			else
				echo "2-网上邻居旧的IPv6地址与新的IPv6地址一致" >$STDOUT
				if [ "$neigh_state" != "${neigh_nud^^}" ];then
					echo "3-网上邻居旧的IPv6更改为 ${neigh_nud^^} 状态" >$STDOUT
					ip -6 neigh change $ip_local lladdr $mac nud $neigh_nud dev ${prefix_from_iface:-br-lan}
				fi
			fi
			ip -6 neigh show | grep -E '^2\S*? dev '${prefix_from_iface:-br-lan}' .*?'$mac  >$STDOUT
			#ip -6 neigh show | grep " br-lan " | grep "^2" | grep "$mac"
		else
			echo "这条更新记录未设置 neigh_nud" >$STDOUT
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

	echo -e "\n------------------------------------------" >$STDOUT

done

}


DIR=$(readlink -f $0)
DIR=${DIR%/*}


test ! -r /etc/config/ddns-odhcpd && {
	echo "不存在配置文件，请执行 install.sh，并编辑 /etc/config/ddns-odhcpd"
	exit 0
}


AccessKey=$(uci -q get ddns-odhcpd.globals.AccessKey)
AccessSecret=$(uci -q get ddns-odhcpd.globals.AccessSecret)
DN_suffix=$(uci -q get ddns-odhcpd.globals.DN_suffix)
TTL=$(uci -q get ddns-odhcpd.globals.TTL)
DNSDN=$(uci -q get ddns-odhcpd.globals.DNSDN)
prefix_from_iface=$(uci -q get ddns-odhcpd.globals.prefix_from_iface)
exec_async=$(uci -q get ddns-odhcpd.globals.exec_async)
log_quient=$(uci -q get ddns-odhcpd.globals.log_quient)
log_retain_linecount=$(uci -q get ddns-odhcpd.globals.log_retain_linecount)

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

