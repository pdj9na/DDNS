# DDNS
DDNS shell script,support aliyun

用于OpenWrt 路由器，需安装bash

========

配置路由器 DHCP/DNS，添加静态地址分配

========

编辑文件 /usr/sbin/odhcpd-update，在最后添加：

{

echo 'odhcpd-update exec attach action'

: '附加更新脚本,执行对DNS和ARPv6的更新（脚本文件在/root/.AliDDNS目录下）'

/root/.AliDDNS/updateDNS_ARPv6.sh >/dev/null

: '其他可异步执行的脚本...'

} &
