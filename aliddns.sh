#!/bin/bash

_ali_urlencode() {
  local _str="$1"
  local _str_len=${#_str}
  local _u_i=0 _str_c
  while [ "$_u_i" -lt "$_str_len" ]; do
    _str_c=${_str:$_u_i:1}
    case $_str_c in [a-zA-Z0-9.~_-])
      printf "%s" "$_str_c"
      ;;
    *)
      printf "%%%02X" "'$_str_c"
      ;;
    esac
	((++_u_i))
  done
}

_digest() {
  local alg="$1"
  if [ -z "$alg" ]; then
    return 1
  fi

  local outputhex="$2"

  if [ "$alg" = "sha256" -o "$alg" = "sha1" -o "$alg" = "md5" ]; then
    if [ "$outputhex" ]; then
      ${ACME_OPENSSL_BIN:-openssl} dgst -"$alg" -hex | cut -d = -f 2 | tr -d ' '
    else
      ${ACME_OPENSSL_BIN:-openssl} dgst -"$alg" -binary | _base64
    fi
  else
    return 1
  fi

}

_ali_nonce() {
  # date +"%s%N"
  # _timestamp
  # 若时间精度不够，会提示：
  #  Specified signature nonce was used already.
  
  # 还是采用随机数：
  head -n 1 </dev/urandom | _digest "sha256" hex | cut -c 1-31
}

_timestamp() {
  date -u +"%Y-%m-%dT%H%%3A%M%%3A%SZ"
}

# ========================================================================================

send_request() {
	# 参数具有固定的顺序，不能改变，否则执行无效
    local args="AccessKeyId=$AccessKey&Action=$1&Format=json&$2&Version=2015-01-09"
    local hash=$(echo -n "GET&%2F&$(_ali_urlencode "$args")" | openssl dgst -sha1 -hmac "$AccessSecret&" -binary | openssl base64)
#echo -n "GET&%2F&$(_ali_urlencode "$args")"
    curl -s "http://alidns.aliyuncs.com/?$args&Signature=$(_ali_urlencode "$hash")"
}


query_recordid() {
	local DN_prefix=$1 #ip_local=$2
	#test -n "$ip_local" && ip_local='&ValueKeyWord='$ip_local
	# 经过测试 Value、ValueKeyWord 都不会作为查询条件！
	# &ValueKeyWord=$(_ali_urlencode $ip_local)
    send_request "DescribeDomainRecords&DomainName=$DN_suffix" "RRKeyWord=$DN_prefix&SignatureMethod=HMAC-SHA1&SignatureNonce=$(_ali_nonce)&SignatureVersion=1.0&Timestamp=$(_timestamp)&TypeKeyWord=AAAA"
}

add_record() {
	local DN_prefix=$1 ip_local=$2
    send_request "AddDomainRecord&DomainName=$DN_suffix" "RR=$DN_prefix&SignatureMethod=HMAC-SHA1&SignatureNonce=$(_ali_nonce)&SignatureVersion=1.0&TTL=$TTL&Timestamp=$(_timestamp)&Type=AAAA&Value=$(_ali_urlencode $ip_local)"
}

del_record() {
	# RecordId is mandatory for this action.
	# 必须要求 RecordId，否则不能删除
	local RecordId=$1
    send_request "DeleteDomainRecord" "RecordId=$RecordId&SignatureMethod=HMAC-SHA1&SignatureNonce=$(_ali_nonce)&SignatureVersion=1.0&Timestamp=$(_timestamp)&Type=AAAA"
}

get_recordid() {
    grep -Eo '"RecordId":"[0-9]+"' | cut -d':' -f2 | tr -d '"'
}


get_recordvalueid() {
    grep -o "\"Value\":\"[^\"]*\",\"RecordId\":\"[^\"]*\"" | awk -F\" '{print $4,$8}'
}

run(){
	local ip_local=$1 DN_prefix=$2
	local DN=$DN_suffix
	#不支持添加直接解析主域名@
	#@需要url编码两次，获得%2540,@的url编码一次是%40，不符合阿里云要求的%2540，*的url编码是%2A
	[ $DN_prefix = '@' ] && DN_prefix=$(_ali_urlencode $DN_prefix) || DN=$DN_prefix.$DN
	# 经测试*也需要编码两次，且需要添加到 DN
	[ $DN_prefix = '*' ] && DN_prefix=$(_ali_urlencode $DN_prefix)

	_echo "记录：$DN_prefix"
	_echo "要删除的记录 Value、ID 列表："
	
	local RecordValueIds=`query_recordid $DN_prefix 2>>$LOGFILE_PATH | get_recordvalueid`
	_echo "$RecordValueIds"
	
	_echo "其中排除要删除的记录 Value：$ip_local"
	
	local rvalue rid
	local excludeRecordId
	while read rvalue rid;do
		if test "$rvalue" = "$ip_local" -a -z "$excludeRecordId";then
			# 只排除一个 value 相同的记录，其他记录都删除
			# 经过测试，value 相同的记录没法添加到阿里云
			excludeRecordId=$rid
		else
			del_record $rid >/dev/null
		fi
	done <<<"$RecordValueIds"
	
	if test -z "$excludeRecordId";then
		_echo "已添加记录的 ID：\c"
		_echo `add_record $DN_prefix $ip_local 2>>$LOGFILE_PATH | get_recordid`
	else
		_echo "记录已存在，不需要添加"
	fi
	_echo ""
}


