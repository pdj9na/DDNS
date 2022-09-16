# DDNS
DDNS shell script,support aliyun

用于OpenWrt 路由器，需安装 bash mount-utils

执行 install.sh 完成初始化


# ============= /etc/config/odhcpd-ddns ================

# 全局配置

config globals 'globals'
    option dnsapi 'ali'					# 域名服务提供商代号，目前仅支持 阿里
    option AccessKey '***'				# 访问键
    option AccessSecret '***'			# 访问密钥
    option DN_suffix 'example.com'		# 域名服务提供商申请的域名
    option TTL '600'					# 记录更新后生效的最大延迟
    option default_dhcpv6_interface 'lan'	# 默认 dhcpv6 接口；客户端未开机时，不能从 neigh 中获取 dev，所以需要在配置文件中指定
    option exec_async '1'				# 为 1 时异步执行
    option log_quient '1'				# 为 1 时不输出日志
    option log_retain_linecount '300'	# 日志文件保留行数
    option terminal_quient '1'			# 为 1 时不输出终端


# 路由器 LAN 口公网 IPv6

config lan
    option iface 'br-lan'				# 接口名称
    option records 'router'				# 解析记录，可设多个
	
# 路由器 WAN 口公网 IPv6

config wan
    option iface 'pppoe-wan'
    option records 'wan-router'
	
# 下位机 公网 IPv6

config host
    option dhcpv6_interface '***'		# dhcpv6 接口，若未设置，将采用全局配置中的 default_dhcpv6_interface
    option duid '***'					# dhcpv6 duid
    option mac '***'					# neigh mac ，如果 ip -6 neigh 也使用 duid 就不需要 mac 了；如果不设 mac，就不能设置 neigh
	option router '0'					# 主机类型是否为路由（非 OpenWrt系统路由不能确保 neigh 是否为 router，需先验证），默认为 0；
										#	客户端未开机时，neigh 中不存在该 mac 的记录，也就不能通过 neigh 确定客户端类型
    option records '***'
	
	

