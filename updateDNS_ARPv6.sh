#!/bin/bash

# [ -z "$DIR" ] && DIR=$(dirname $(readlink -f $0)) && [ "${DIR:0-1}" != '/' ] && DIR=$DIR/
[ -z "$DIR" ] && { DIR=$(readlink -f $0);DIR=${DIR%/*}; }

# 日志文件截断后保留的最大行数
LOGFILE_TRUNCATE_LATER_RETAIN_LINE_COUNT=500

export LOGFILE_NAME=log_ddns.log

get_prefix(){

#读取路由公网IPv6前缀
 #重试计数 前缀
local count=0
#重试小于等于?就继续循环
while [ -z "$prefix" -a $count -le 120 ];do
	#grep -v via：排除下级路由器dhcp客户端路由
	#grep "dev br-lan "：‘br-lan’的后面保留一个空格是为了完全匹配‘br-lan’，而不会匹配如‘br-lanxxxx...’这样的
	prefix=`ip -6 route | grep -E '^2\S*? dev '${1:-br-lan}' ' | awk -F/ '{print $1}'`
	# count=`expr $count + 1`
	[ -z "$prefix" ] && sleep 1 && ((++count))
done
[ -z "$prefix" ] && return 1 || return 0
}


###更新路由器br-lan、pppoe-wan的动态域名IPv6
updateDomainNameFromRouter(){
# echo "$@"
# echo "$*"
echo -e "\n=============更新路由器================"
local item iface
# $@ 使用时加引号，并在引号中返回每个参数
for item in "$@";do
	unset iface DN_prefix
	eval `echo $item | awk '{printf("iface=%s;DN_prefix=%s",$1,$2)}'`
	# echo "$item | $iface | $DN_prefix"
	#要更新的IPv6地址
	[ -n "$iface" ] && ip_local=`ip -6 addr show $iface | grep -E '\s*?inet6 2\S*? scope global ' | awk -F' +|/' '{print $3}'`
	#更新DNS异步执行容易导致下一条执行失败，同步执行要好一些，最好延迟一点时间，aliddns_core.sh中执行更新操作前sleep 1
	[ -n "$ip_local" -a -n "$DN_prefix" ] && $DIR/aliddns.sh $ip_local $DN_prefix
done

}

updateDomainNameFromRearHost(){

echo -e "\n=============更新下级主机==============="

#获取2开头的网上邻居ipv6公网地址
#形式	2xxx:xxxx:xxxx:xxxx::xxxx dev br-lan lladdr xx:xx:xx:xx:xx:xx PERMANENT
local neigh_ipv6s=`ip -6 neigh show | grep -E '^2\S*? dev '${1:-br-lan}' '`
#这一句获取数据中的MAC地址中包含的字母全部是小写


local line mac records isConfigARPv6
local index suffix neigh_ipv6 neigh_state
while read -r line;do
	[ -z "$line" ] && continue

	eval `echo $line | awk '{printf("mac=%s;records=%s;isConfigARPv6=%s",$1,$2,$3)}'`

	echo -e "\n------------------------------------------"

	printf "\n主机MAC地址>%-15s	是否设置ARPv6>%-2s	主机记录集合>%s\n" $mac $isConfigARPv6 $records


	#读取dhcp中的静态分配地址后缀
	index=0 suffix=

	#="host"代表数组未越界
	while [[ `uci get dhcp.@host[$index]` = 'host' ]];do
		
		#dhcp配置文件中的静态地址分配节中的MAC地址，在LUCI中的下拉框中字母都为大写
		#网上邻居读取的是小写，配置网上邻居就也用小写
		if [ `uci get dhcp.@host[$index].mac` = "${mac^^}" ]
		then
			suffix=`uci get dhcp.@host[$index].hostid`
			break
		fi
		# index=`expr $index + 1`
		((++index))
	done

	if [ -n "$suffix" ];then

		#要更新的IPv6地址
		ip_local="$prefix$suffix"
		
		echo "合并的IPv6>>$ip_local"

		#判断是否需要配置ARPv6
		if [ "$isConfigARPv6" = '1' ];then
			
			#更新ARPv6------
			#筛选并截取地址
			eval `echo "$neigh_ipv6s" | grep -i "$mac" | awk '{printf("neigh_ipv6=%s;neigh_state=%s",$1,$6)}'`
			echo -e "\n----更新ARPv6-------\n原邻居IPv6>$neigh_ipv6 原邻居状态> $neigh_state"

			if [ -n "$neigh_ipv6" -a "$neigh_ipv6" != "$ip_local" ];then
				echo "0-删除旧的IPv6与新IPv6不匹配的网上邻居"
				ip -6 neigh del $neigh_ipv6 dev ${1:-br-lan}
			fi

			if [ -z "$neigh_ipv6" -o "$neigh_ipv6" != "$ip_local" ];then
				echo "1-添加IPv6网上邻居为PERMANENT状态"
				ip neigh add $ip_local lladdr $mac nud permanent dev ${1:-br-lan}
			elif [ "$neigh_ipv6" = "$ip_local" ];then
				echo "2-网上邻居旧的IPv6地址与新的IPv6地址一致"
				if [ "$neigh_state" != "PERMANENT" ];then
					echo "3-网上邻居旧的IPv6更改为PERMANENT状态"
					ip neigh change $ip_local lladdr $mac nud permanent dev ${1:-br-lan}
				fi
			fi
			ip -6 neigh show | grep -E '^2\S*? dev '${1:-br-lan}' .*?'$mac
			#ip -6 neigh show | grep " br-lan " | grep "^2" | grep "$mac"
		else
			echo "这条更新记录未设置为配置ARPv6"
		fi
		
		#更新DNS----
		if [ -n "$records" ];then

			echo -e "\n------更新DNS-------"
			#这里的$IFS等同于$'\n'
			for DN_prefix in ${records//,/$IFS};do
				[ -n "$DN_prefix" ] && $DIR/aliddns.sh $ip_local $DN_prefix
			done
		fi
	else
		echo "未配置静态地址分配！"
	fi

	echo -e "\n------------------------------------------"

#需要更新DNS和ARPv6的主机MAC、主机记录集合
#对应位置：MAC地址（字母采用小写） DNS主机记录集合（多个要采用,分割） 是否配置ARPv6(0等同于空,1)

#路由器IPv6的 DHCPv6模式只能选有状态，对于无状态，暂未做适配，需要处理网上邻居(neigh)ARPv6,且不需要静态地址分配
#对于无状态，由于可管理性和简洁性不如有状态，就优先采用有状态了
#对于安卓原生不支持有状态的情况，可以通过安装应用（如DHCPv6 Client）来解决，不过需要root权限

done < $DIR/ddns_record.txt

}


get_prefix && {
	echo -e '\n'====$(date "+%Y-%m-%d %H:%M:%S") >>$DIR/$LOGFILE_NAME
	updateDomainNameFromRouter 'br-lan router' 'pppoe-wan pppoe-wan.router' # 'br-lan @' 'br-lan *'
	updateDomainNameFromRearHost

	# 截断日志文件为不超过指定行数
	logFileLineCount=`[ -f $DIR/$LOGFILE_NAME ] && wc -l $DIR/$LOGFILE_NAME | awk '{print $1}' || echo 0`
	# echo $logFileLineCount
	logFileTruncateLineCount=$[logFileLineCount-LOGFILE_TRUNCATE_LATER_RETAIN_LINE_COUNT]
	# echo $logFileTruncateLineCount
	[ "$logFileTruncateLineCount" -gt 0 ] && sed -i '1,'$logFileTruncateLineCount'd' $DIR/$LOGFILE_NAME
}
