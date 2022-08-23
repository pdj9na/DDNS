# DDNS
DDNS shell script,support aliyun

用于OpenWrt 路由器，需安装 bash mount-utils


# ============== /etc/init.d/ddns-odhcpd ==============

chmod +x /root/DDNS/ddns-odhcpd
ln -sf /root/DDNS/ddns-odhcpd /etc/init.d/ddns-odhcpd

/etc/init.d/ddns-odhcpd enable

# 检查是否挂载：
mountpoint /usr/sbin/odhcpd-update
less /usr/sbin/odhcpd-update

# ============= /etc/config/ddns-odhcpd ================

# 全局配置

config globals 'globals'
	option dnsapi 'ali'					# 域名服务提供商代号，目前仅支持 阿里
	option AccessKey '***'				# 访问键
	option AccessSecret '***'			# 访问密钥
	option DN_suffix 'example.com'		# 域名服务提供商申请的域名
	option TTL '600'					# 记录更新后生效的最大延迟
	option DNSDN '114.114.114.114'		# DNS 域名解析指定 DNS
	option prefix_from_iface 'br-lan'	# 获取 IPv6 前缀的 接口名称，目前只考虑一个 LAN 的情况
	option exec_async '1'				# 为 1 时异步执行
	option log_quient '1'				# 为 1 时不输出日志
	option log_retain_linecount '500'	# 日志文件保留行数

# >>DNSDN
# DNS 域名解析指定DNS，采用域名解析服务提供商的DNS最好，指定其他DNS如114，更新会有延迟
# 114DNS虽然更新有延迟，但是问题少，可能是 DNSDN 再经过一次域名解析的原因，或者是服务器停机了？


# 路由器 LAN 口公网 IPv6

config lan
	option iface 'br-lan'				# 接口名称
	option records 'router'				# 解析记录，可设多个
	
# 路由器 WAN 口公网 IPv6

config wan
	option iface 'pppoe-wan'
	option records 'wan-router'
	
# 下位机 公网 IPv6
# 需分配静态地址

config host
	option mac '***'					# mac 地址
	option records '***'
	option neigh_nud ''			# 可能的值有： STALE（过期，默认的）、REACHABLE（可达）、PERMANENT（永久）

	

