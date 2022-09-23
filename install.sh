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


# 初始配置

DIRC=/root/.config

mkdir -p $DIRC

if test ! -f $DIRC/odhcpd-ddns;then
	cp -a $DIR/defaultconfig_odhcpd-ddns $DIRC/odhcpd-ddns
fi

DIRC2=/etc/config

if test "$(readlink -f $DIRC2/odhcpd-ddns)" != $DIRC/odhcpd-ddns;then
	ln -sfT $DIRC/odhcpd-ddns $DIRC2/odhcpd-ddns
fi
