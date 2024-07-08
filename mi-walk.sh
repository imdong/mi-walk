#!/bin/bash

# 获取基础变量
username=$1
password=$2
step=$3

# 随机一个 IP
fake_ip() {
    echo "223.$((RANDOM % 54 + 64)).$((RANDOM % 256)).$((RANDOM % 256))"
}
fake_ip_addr=$(fake_ip)

# 发出 curl 请求
curl_send() {
    curl -s \
        -H "Content-Type: application/x-www-form-urlencoded;charset=UTF-8" \
        -H "User-Agent: Mozilla/5.0 (iPhone; CPU iPhone OS 14_7_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.1.2" \
        -H "X-Forwarded-For: ${fake_ip_addr}" \
        $@
}

# 检测帐号是手机号还是邮箱
mi_get_username_type() {
    # 要检测的字符串
    input="$1"

    # 邮箱正则表达式
    email_regex="^[^@]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"

    # 全球手机号正则表达式 (国际格式)
    phone_regex="^\+[1-9][0-9]{1,14}$"

    # 中国手机号正则表达式 (不带前缀)
    phone_regex_cn="^1[3-9][0-9]{9}$"

    if [[ $input =~ $email_regex ]]; then
        echo "email"
        return 0
    elif [[ $input =~ $phone_regex ]]; then
        echo "huami_phone"
        return 0
    elif [[ $input =~ $phone_regex_cn ]]; then
        echo "huami_phone_cn"
        return 0
    else
        echo "未知的帐号类型"
        return 1
    fi
}

# 登录
mi_login() {
    local username=$1
    local password=$2

    local body=$(curl_send -o /dev/null -w "%{http_code}|%{redirect_url}" \
        "https://api-user.huami.com/registrations/${username}/tokens" \
        --data-raw "client_id=HuaMi&password=${password}&redirect_uri=https://s3-us-west-2.amazonaws.com/hm-registration/successsignin.html&token=access")
    local status_code=$(echo $body | awk -F'|' '{print $1}')

    # 判断登录状态码
    if [ "$status_code" -eq 303 ]; then
        echo $(echo $body | awk -F'|' '{print $2}' | grep -o '[?&]access=[^&$]\+' | awk -F= '{print $2}')
        return 0
    else
        return 1
    fi
}

# 获取用户 user_id
mi_user_id() {
    local access=$1
    local mode=$2

    body=$(curl_send "https://account.huami.com/v2/client/login" \
        --data-raw "app_name=com.xiaomi.hm.health&app_version=4.6.0&code=${access}&country_code=CN&device_id=2C8B4939-0CCD-4E94-8CBA-CB8EA6E613A1&device_model=phone&grant_type=access_token&third_name=${mode}")
    echo $body | jq -r '.token_info.user_id'
}

# 检查帐号类型
username_type=$(mi_get_username_type "${username}")
if [ "$?" -eq 1 ]; then
    echo "帐号 ${username} 不是可支持的类型"
    exit 2
fi

# 中国号码特别处理
if [ "${username_type}" == "huami_phone_cn" ]; then
    username="+86${username}"
    username_type="huami_phone"
fi

# 登录并获取 access token
access=$(mi_login "${username}" "${password}")
if [ "$?" -eq 1 ]; then
    echo "登录失败，请检查帐号密码"
    exit 1
fi

# 换取用户ID
user_id=$(mi_user_id "${access}" "${username_type}")
if [[ "${user_id}" == "" || "${user_id}" == "null" ]]; then
    echo "登录失败，未能获取用户 user_id"
    exit 3
fi
