#!/bin/bash
[ -z "$DIR" ] && { DIR=$(readlink -f $0);DIR=${DIR%/*}; }
[ -z "$LOGFILE_NAME" ] && LOGFILE_NAME=log.log
#引用基本参数
. $DIR/ddns.conf

enc() {
	$DIR/urlencode.sh $1
}

send_request() {
    local args="AccessKeyId=$AccessKey&Action=$1&Format=json&$2&Version=2015-01-09"
    local hash=$(echo -n "GET&%2F&$(enc "$args")" | openssl dgst -sha1 -hmac "$AccessSecret&" -binary | openssl base64)
#echo -n "GET&%2F&$(enc "$args")"
    curl -s "http://alidns.aliyuncs.com/?$args&Signature=$(enc "$hash")"
}

query_recordid() {
    send_request "DescribeSubDomainRecords"                            "SignatureMethod=HMAC-SHA1&SignatureNonce=$timestamp&SignatureVersion=1.0&SubDomain=$DN&Timestamp=$timestamp&Type=AAAA"
}

update_record() {
    send_request "UpdateDomainRecord"        "RR=$DN_prefix&RecordId=$1&SignatureMethod=HMAC-SHA1&SignatureNonce=$timestamp&SignatureVersion=1.0&TTL=$TTL&Timestamp=$timestamp&Type=AAAA&Value=$(enc $ip_local)"
}

add_record() {
    send_request "AddDomainRecord&DomainName=$DN_suffix" "RR=$DN_prefix&SignatureMethod=HMAC-SHA1&SignatureNonce=$timestamp&SignatureVersion=1.0&TTL=$TTL&Timestamp=$timestamp&Type=AAAA&Value=$(enc $ip_local)"
}

get_recordid() {
    grep -Eo '"RecordId":"[0-9]+"' | cut -d':' -f2 | tr -d '"'
}

#https://blog.zeruns.tech

run(){
ip_local=$1
DN_prefix=$2

timestamp=`date -u "+%Y-%m-%dT%H%%3A%M%%3A%SZ"`

DN=$DN_suffix
#不支持添加直接解析主域名@
#@需要url编码两次，获得%2540,@的url编码一次是%40，不符合阿里云要求的%2540，*的url编码是%2A
[ $DN_prefix = '@' ] && DN_prefix=$(enc $DN_prefix) || DN=$DN_prefix.$DN
# 经测试*也需要编码两次，且需要添加到 DN
[ $DN_prefix = '*' ] && DN_prefix=$(enc $DN_prefix)

# echo $DN'---'$DN_prefix
echo -e "\n主机记录:$DN"

# ip_FromDNS=`nslookup -query=AAAA $DN 2>&1 | grep 'Address: ' | tail -n1 | awk '{print $NF}'`
# 这里只针对OpenWrt， nslookup 命令有平台差异，不同平台输出格式不同；-query == -qt
# dnsmasq解析可能会有问题，还容易出现 Parse error，所以指定DNS解析，最好指定域名解析服务DNS
local ip_FromDNS count=0
echo "" >>$DIR/$LOGFILE_NAME
while [ -z "$ip_FromDNS" -a $count -le 10 ];do
	echo ">>>>>>nslookup<<<<<<<<<<" >>$DIR/$LOGFILE_NAME
	ip_FromDNS=`echo $(nslookup -qt=AAAA "$DN" "$DNSDN" 2>>$DIR/$LOGFILE_NAME) | awk -F'has\\\sAAAA\\\saddress\\\s' '{print $2}'`
	[ -z "$ip_FromDNS" ] && sleep $((++count))
done

printf "DNS记录IP地址>%-23s	本地IP地址>%-23s\n" $ip_FromDNS $ip_local

printf ">>域名：$DN<< 从 $DNSDN 解析：\n" >>$DIR/$LOGFILE_NAME
printf "DNS记录IP地址>%-23s	本地IP地址>%-23s\n" $ip_FromDNS $ip_local >>$DIR/$LOGFILE_NAME

#if [ "$ip_local" = "$ip_FromDNS" ];then
if false;then
	echo "skipping"
	echo skipping >>$DIR/$LOGFILE_NAME
else
	# 强制释放内存
	echo 3 > /proc/sys/vm/drop_caches
	sleep 1
	local RecordId count=0
	# 尝试几次 ，确定记录是否存在，所以如果是新增记录，要延迟几秒
	while [ -z "$RecordId" -a $((++count)) -le 1 ];do
		echo ">>>>>>query_recordid<<<<<<<<<<" >>$DIR/$LOGFILE_NAME
		RecordId=`query_recordid 2>>$DIR/$LOGFILE_NAME | get_recordid`
		[ -z "$RecordId" ] && sleep 1
	done
	
	if [ -z "$RecordId" ];then
		echo -e "不存在RecordId，准备添加... \c"
		echo '准备添加...' >>$DIR/$LOGFILE_NAME
		count=0
		while [ -z "$RecordId" -a $((++count)) -le 1 ];do
			echo ">>>>>>add_record<<<<<<<<<<" >>$DIR/$LOGFILE_NAME
			RecordId=`add_record 2>>$DIR/$LOGFILE_NAME | get_recordid`
			[ -z "$RecordId" ] && sleep $count || echo "added record $RecordId"
		done
	else
		echo -e "已获取RecordId，准备更新... \c"
		echo '准备更新...' >>$DIR/$LOGFILE_NAME
		count=0
		# 记录已存在：            "Message":"The DNS record already exists."
		# 已使用指定的签名nonce： "Message":"Specified signature nonce was used already."
		while [ $((++count)) -le 2 ];do
			echo ">>>>>>update_record<<<<<<<<<<" >>$DIR/$LOGFILE_NAME
			update_record $RecordId 2>>$DIR/$LOGFILE_NAME 1>/dev/null # | grep -Eo '"RequestId":"\S*?"' | cut -d, -f1 | tr -d '"'
			[ ! "$?" = 0 ] && sleep $count || { echo "updated record $RecordId";break; }
		done
	fi
	# 强制释放内存
	echo 3 > /proc/sys/vm/drop_caches
fi

}

run "$@"
