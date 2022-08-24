#!/bin/sh

# 安装依赖
! type bash >/dev/null 2>&1 && opkg install bash
! type mountpoint >/dev/null 2>&1 && opkg install mount-utils


DIR=$(readlink -f $0)
DIR=${DIR%/*}

if test -f $DIR/updateDNS_ARPv6.sh;then
	chmod +x $DIR/updateDNS_ARPv6.sh
fi

# 安装 init 服务
if test -f $DIR/ddns-odhcpd;then

	chmod +x $DIR/ddns-odhcpd
	if test "$(readlink -f /etc/init.d/ddns-odhcpd)" != $DIR/ddns-odhcpd;then
		ln -sf $DIR/ddns-odhcpd /etc/init.d/ddns-odhcpd
	fi

	! /etc/init.d/ddns-odhcpd enabled && /etc/init.d/ddns-odhcpd enable

	/etc/init.d/ddns-odhcpd start

	# 检查是否挂载：
	#mountpoint /usr/sbin/odhcpd-update
	#less /usr/sbin/odhcpd-update
fi


DIR=/etc/config

# 初始配置
if test ! -f $DIR/ddns-odhcpd;then

	cat >$DIR/ddns-odhcpd<<-\EOF

config globals 'globals'
	option dnsapi 'ali'
	option AccessKey '***'
	option AccessSecret '***'
	option DN_suffix 'example.com'
	option TTL '600'
	option DNSDN '114.114.114.114'
	option prefix_from_iface 'br-lan'
	option exec_async '1'
	option log_quient '1'
	option log_retain_linecount '500'

#config lan
#	option iface 'br-lan'
#	option records 'router'
#
#config wan
#	option iface 'pppoe-wan'
#	option records 'wan-router'
#
#config host
#	option mac '***'
#	option records '***'
#	option neigh_nud 'permanent'

EOF

fi
