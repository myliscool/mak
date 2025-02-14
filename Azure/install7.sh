#!/bin/bash
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

install_azure() {
    os=$(grep -oP '(?<=^ID=).+' /etc/os-release | tr -d '"')

    if [ "$os" == "ubuntu" ] || [ "$os" == "debian" ]; then
        sudo apt-get update -y
        sudo apt-get install ca-certificates curl apt-transport-https lsb-release gnupg jq sshpass screen -y

        if [ ! -d "/etc/apt/keyrings" ]; then
            echo -e "${RED}目录不存在，现在创建${NC}"
            sudo mkdir -p /etc/apt/keyrings
        else
            echo -e "${GREEN}目录已存在${NC}"
        fi
        
        echo -e "${GREEN}下载并安装 Microsoft 签名密钥${NC}"
        curl -sLS https://packages.microsoft.com/keys/microsoft.asc |
        gpg --dearmor |
        sudo tee /etc/apt/keyrings/microsoft.gpg > /dev/null
        sudo chmod go+r /etc/apt/keyrings/microsoft.gpg

        echo -e "${GREEN}添加 Azure CLI 软件存储库${NC}"
        AZ_DIST=$(lsb_release -cs)
        echo "deb [arch=`dpkg --print-architecture` signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $AZ_DIST main" |
        sudo tee /etc/apt/sources.list.d/azure-cli.list

        echo -e "${GREEN}更新存储库信息并安装 Azure CLI 包${NC}"
        sudo apt-get update -y
        sudo apt-get install azure-cli -y
    else
        echo -e "${RED}没有适配系统${NC}"
    fi
    menu
}

login() {
    if command -v az > /dev/null 2>&1; then
        output=$(az login --use-device-code)
        if echo "$output" | jq -e . > /dev/null 2>&1; then
            echo -e "${GREEN}登录成功${NC}"
        else
            echo -e "${RED}登录失败，请重试${NC}"
        fi
    else
        echo -e "${RED}未安装 Azure CLI 请先安装${NC}"
    fi
    menu
}

uninstall_azure() {
    if command -v az > /dev/null 2>&1; then
        echo -e "${GREEN}正在卸载 Azure CLI${NC}"
        sudo apt-get remove -y azure-cli
        sudo rm /etc/apt/sources.list.d/azure-cli.list
        sudo rm /etc/apt/trusted.gpg.d/microsoft.gpg
        sudo apt autoremove -y
        rm -rf ~/.azure
        echo -e "${GREEN}Azure CLI 卸载完成${NC}"
    else
        echo -e "${RED}未检测到 Azure CLI 无需卸载${NC}"
    fi

    menu
}

check_azure() {
    if ! command -v az &> /dev/null; then
        echo -e "\e[31m错误: Azure CLI 没有安装. 请先安装 Azure CLI.\e[0m"
        exit 1
    fi

    if ! az account show &> /dev/null; then
        echo -e "\e[31m错误: 你还没有登录 Azure. 请先运行 'az login' 来登录你的 Azure 账户.\e[0m"
        exit 1
    fi
}

create_vm() {
LOCATIONS=("westus3" "australiaeast" "uksouth" "southeastasia" "swedencentral" "centralus" "centralindia" "eastasia" "japaneast" "koreacentral" "canadacentral" "francecentral" "germanywestcentral" "italynorth" "norwayeast" "polandcentral" "switzerlandnorth" "brazilsouth" "northcentralus" "westus" "japanwest" "australiacentral" "canadaeast" "ukwest" "southcentralus" "northeurope" "southafricanorth" "australiasoutheast" "southindia" "uaenorth")

while true; do
    echo -e "\e[32m用户名不能包含大写字符 A-Z、特殊字符 \\/\"[]:|<>+=;,?*@#() ！或以 $ 或 - 开头\e[0m"
    echo -e "\e[32m密码长度必须在 12 到 72 之间。密码必须包含以下 3 个字符：1 个小写字符、1 个大写字符、1 个数字和 1 个特殊字符\e[0m"
    echo -e "\e[32m实例密码的特殊字符适配使用 .!@#\$%^\&*() \e[0m"
    echo -e
    read -p "请输入实例用户名: " USERNAME
    read -p "请输入实例密码: " PASSWORD
    read -p "请输入挖矿钱包: " WALLERT
    if [[ "$USERNAME" =~ [A-Z] ]]; then
        echo -e "\e[32m错误: 用户名不能包含大写字符 A-Z、特殊字符 \\/\"[]:|<>+=;,?*@#()! 或以 $ 或 - 开头\e[0m"
        continue
    fi
    PASSWORD_LENGTH=${#PASSWORD}
if [[ $PASSWORD_LENGTH -lt 12 || $PASSWORD_LENGTH -gt 72 ]]; then
    echo -e "\e[32m错误: 密码长度必须在 12 到 72 之间。\e[0m"
    continue
fi
if ! echo "$PASSWORD" | grep -q '[a-z]'; then
    echo -e "\e[32m错误: 密码必须包含至少一个小写字母。\e[0m"
    continue
fi
if ! echo "$PASSWORD" | grep -q '[A-Z]'; then
    echo -e "\e[32m错误: 密码必须包含至少一个大写字母。\e[0m"
    continue
fi
if ! echo "$PASSWORD" | grep -q '[0-9]'; then
    echo -e "\e[32m错误: 密码必须包含至少一个数字。\e[0m"
    continue
fi
if ! echo "$PASSWORD" | grep -q '[.!@#\$%^\&*()]'; then
    echo -e "\e[32m错误: 密码必须包含至少一个特殊字符。\e[0m"
    continue
fi
    echo -e
    echo -e "\e[32m用户名和密码验证成功\e[0m"
    break
done
declare -a pids
for location in "${LOCATIONS[@]}"; do
    groupInfo=$(az group show --name "$location" 2>&1)
    if [ $? -eq 0 ]; then
        echo -e "\e[33m资源组已存在 $location\e[0m"
    else
        errorMessage=$(echo "$groupInfo" | grep -oP "(?<=Message:\s).+")
        az group create --name "$location" --location "$location"
        if [ $? -eq 0 ]; then
            echo -e "\e[32m资源组创建成功 $location\e[0m"
            nohup az vm create --resource-group "$location" --name "$location" --location "$location" --image Debian11 --size Standard_DS12_v2 --admin-username "$USERNAME" --admin-password "$PASSWORD" --security-type Standard --public-ip-sku Basic --public-ip-address-allocation Dynamic > /dev/null 2>&1 &
            pid=$!
            pids+=($pid)
            echo -e "\e[36m已在后台执行 az vm create 命令\e[0m"
        else
            echo -e "\e[31m资源组创建失败 $location\e[0m"
            echo -e "\e[31m$errorMessage\e[0m"
        fi
    fi
done
for index in "${!pids[@]}"; do
    pid=${pids[$index]}
    location=${LOCATIONS[$index]}
    wait $pid
    if [ $? -eq 0 ]; then
        vmInfo=$(az vm show --name "$location" --resource-group "$location" --query "provisioningState" -o tsv 2>&1)
        if [ "$vmInfo" == "Succeeded" ]; then
            echo -e "\e[32mVM创建成功 $location\e[0m"
        else
            echo -e "\e[31mVM创建失败 $location\e[0m"
        fi
    else
        echo -e "\e[31mVM创建失败 $location\e[0m"
    fi
done
ips=$(az network public-ip list --query "[].ipAddress" -o tsv)
for ip in $ips; do
  {
    nohup sshpass -p "$PASSWORD" ssh -tt -o StrictHostKeyChecking=no $USERNAME@$ip 'sudo bash -c "curl -s -L https://raw.githubusercontent.com/878088/zeph/main/setup_zeph_miner.sh | LC_ALL=en_US.UTF-8 bash -s '$WALLERT'"'
    exit_status=$?
    if [ $exit_status -eq 0 ]; then
        echo -e "\e[32m$ip 的挖矿任务成功启动\e[0m"
    else
        echo -e "\e[31m$ip 的挖矿任务启动失败\e[0m"
    fi
  } &
done

wait

menu

}

resource_group() {
    for rg in $(az group list --query "[].name" -o tsv); do
        nohup az group delete --name $rg --yes --no-wait
        echo -e "\e[32m成功删除资源组: $rg\e[0m"
    done
    menu
}
menu() {
    echo -e "${GREEN}原创者：粑屁 Telegram: MJJBPG${NC}"
    echo -e
    echo -e "${GREEN}1. 安装 Azure CLI${NC}"
    echo -e "${GREEN}2. 登录 Azure CLI${NC}"
    echo -e "${GREEN}3. 卸载 Azure CLI${NC}"
    echo -e
    echo -e "${GREEN}4. 创建全区实例挖矿${NC}"
    echo -e "${GREEN}5. 删除所有资源组  ${NC}"
    echo -e "${GREEN}0. 退出${NC}"
    read -p "输入您的选择: " choice

    case $choice in
        1)
            install_azure
            ;;
        2)
            login
            ;;
        3)
            uninstall_azure
            ;;
        4)
            create_vm
            ;;
        5)
            resource_group
            ;;
        0)
            echo -e "${RED}退出...${NC}"
            exit 1
            ;;
        *)
            echo -e "${RED}选择无效${NC}"
            menu
            ;;
    esac
}

menu
