#!/bin/sh

# 安装依赖
! type bash >/dev/null 2>&1 && opkg install bash
! type mountpoint >/dev/null 2>&1 && opkg install mount-utils

! type openssl >/dev/null 2>&1 && opkg install openssl-util

DIR=$(readlink -f $0)
DIR=${DIR%/*}

MAINEXEC=$DIR/updateDNS_ARPv6.sh

SRVNAME=odhcpd-ddns
SRVFULLNAME_S=$DIR/$SRVNAME
SRVFULLNAME=/etc/init.d/$SRVNAME


if test -f $MAINEXEC;then
	chmod +x $MAINEXEC
fi

# 安装 init 服务，提供参数 u 可卸载
# 安装过程：创建符号连接、启用、启动
# 卸载过程：停止、禁用、删除符号链接
if test -f $SRVFULLNAME_S;then

	chmod +x $SRVFULLNAME_S

	if test x$1 = x;then
	
		if test "$(readlink -f $SRVFULLNAME)" != $SRVFULLNAME_S;then
			ln -sf $SRVFULLNAME_S $SRVFULLNAME
		fi
		
		if test -x $SRVFULLNAME;then
			! $SRVFULLNAME enabled && $SRVFULLNAME enable
			$SRVFULLNAME start
		fi
		
	elif test x$1 = xu;then
		if test -x $SRVFULLNAME;then
			test -x $SRVFULLNAME && $SRVFULLNAME stop
			$SRVFULLNAME enabled && $SRVFULLNAME disable
		fi
			
		if test "$(readlink -f $SRVFULLNAME)" = $SRVFULLNAME_S;then		
			rm -f $SRVFULLNAME
		fi
	fi
fi


DIR=/etc/config

# 初始配置
if test ! -f $DIR/odhcpd-ddns;then

	cat >$DIR/odhcpd-ddns<<-\EOF

config globals 'globals'
#	option dnsapi 'ali'
#	option AccessKey '***'
#	option AccessSecret '***'
#	option DN_suffix 'example.com'
#	option TTL '600'
#	option DNSDN '114.114.114.114'
#	option prefix_from_iface 'br-lan'
#	option exec_async '1'
#	option log_quient '1'
#	option log_retain_linecount '500'

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
