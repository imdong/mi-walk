#!/bin/bash

# 获取基础变量
username=$1
password=$2
step=$3

# 随机一个 IP
fake_ip() {
    echo "223.$((RANDOM % 54 + 64)).$((RANDOM % 256)).$((RANDOM % 256))"
}

urlencode() {
    local encode_str=$1
    curl -Gs -w %{url_effective} --data-urlencode "dummy=$(echo $encode_str)" 127.0.0.1 | cut -c 25-
}

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

# 获取用于提交的 data 数据
mi_get_step_data() {
    local step=$1
    local now=$(date +%Y-%m-%d)

    # echo '[{"data_hr":"","date":"","data":[],"summary":{"stp":{"ttl":0}}}]' |
    #     jq ".[0].date=\"${now}\"" |
    #     jq ".[0].summary.stp.ttl=${step}" |
    #     jq -c '.[] | .summary = (.summary | tostring)'

    cat ./mi-step.txt | sed -E "s/%22date%22%3A%22[0-9-]+%22/%22date%22%3A%22${now}%22/" | sed -E "s/%22ttl%5C%22%3A[0-9]+%2C/%22ttl%5C%22%3A${step}%2C/"
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

# 获取用户信息
mi_userinfo() {
    local access=$1
    local mode=$2

    curl_send "https://account.huami.com/v2/client/login" \
        --data-raw "app_name=com.xiaomi.hm.health&app_version=4.6.0&code=${access}&country_code=CN&device_id=2C8B4939-0CCD-4E94-8CBA-CB8EA6E613A1&device_model=phone&grant_type=access_token&third_name=${mode}"
}

# 获取apptoken
mi_get_apptoken() {
    local login_token=$1

    local body=$(curl_send "https://account-cn.huami.com/v1/client/app_tokens?app_name=com.xiaomi.hm.health&dn=api-user.huami.com%2Capi-mifit.huami.com%2Capp-analytics.huami.com&login_token=${login_token}")

    echo $body | jq -r '.token_info.app_token'
}

# 提交步数
mi_step_submit() {
    local user_id=$1
    local app_token=$2
    local step=$3

    local data_json=$(mi_get_step_data $step)
    local now_time=$(date +%s)

    body=$(curl_send "https://api-mifit-cn.huami.com/v1/data/band_data.json?t=${now_time}" \
        -H "apptoken:${app_token}" \
        --data-raw "userid=${user_id}&last_sync_data_time=1597306380&device_type=0&last_deviceid=DA932FFFFE8816E7&data_json=${data_json}")

    echo $body
}

# 伪造一个 IP
fake_ip_addr=$(fake_ip)

# # 检查帐号类型
# username_type=$(mi_get_username_type "${username}")
# if [ "$?" -eq 1 ]; then
#     echo "帐号 ${username} 不是可支持的类型"
#     exit 2
# fi

# # 中国号码特别处理
# if [ "${username_type}" == "huami_phone_cn" ]; then
#     username="+86${username}"
#     username_type="huami_phone"
# fi

# # 登录并获取 access token
# access=$(mi_login "${username}" "${password}")
# if [ "$?" -eq 1 ]; then
#     echo "登录失败，请检查帐号密码"
#     exit 1
# fi

# # 获取用户信息
# body=$(mi_userinfo "${access}" "${username_type}")

# # 获取用户 ID
# user_id=$(echo ${body} | jq -r .token_info.user_id)
# # login_token=$(echo ${body} | jq -r .token_info.login_token)
# app_token=$(echo ${body} | jq -r .token_info.app_token)

# if [[ "${user_id}" == "" || "${user_id}" == "null" ]]; then
#     echo "登录失败，未能获取用户 user_id"
#     exit 3
# fi

# 换取 app_token
# app_token=$(mi_get_apptoken "${login_token}")

user_id=1181084583
app_token="ZQVBQFJyQktGHlp6QkpbRl5LRl5qek4uXAQABAAAAABhkUKBrcJE2JvnY7GwJhNRYl5XW0r7dEc9C5wAK2e_Q3Jlka56FDsRhxMuov1Vw5Ll5nAODtMhS1pKuRGZRWY_qxHKAksOFvkfS705II0PUsSZVX7RFzPZuOtrjZD12KYFNpDC2TbWUTcIayhi8pHLaena69e7RUw6BCBh0q_E4ZFEyFXBUXhlfzAa5PdlThg"

# 修改用户步数
mi_step_submit ${user_id} "${app_token}" ${step}
