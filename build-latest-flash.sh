#!/bin/bash
#================================================================================================
#
# 快速构建最新 Flash 镜像脚本
# 用法: ./build-latest-flash.sh [设备名称]
#
#================================================================================================

# 设置颜色输出
STEPS="[\033[95m STEPS \033[0m]"
INFO="[\033[94m INFO \033[0m]"
SUCCESS="[\033[92m SUCCESS \033[0m]"
ERROR="[\033[91m ERROR \033[0m]"
WARNING="[\033[93m WARNING \033[0m]"

# 错误处理函数
error_msg() {
    echo -e "${ERROR} ${1}"
    exit 1
}

# 默认参数
DEVICE_NAME="${1:-efused-wxy-oec}"
REPO_OWNER="dd-ray"
REPO_NAME="amlogic-s9xxx-armbian"
SOURCE_RELEASE="Armbian_bookworm_save_2025.06"
WORK_DIR="./flash_build_workspace"

echo -e "${STEPS} 快速构建最新 Flash 镜像"
echo -e "${INFO} 目标设备: ${DEVICE_NAME}"
echo -e "${INFO} 源 Release: ${SOURCE_RELEASE}"

# 检查必要工具
echo -e "${STEPS} 检查构建环境..."
for tool in curl jq wget unzip sgdisk tar; do
    if ! command -v $tool >/dev/null 2>&1; then
        error_msg "缺少必要工具: $tool，请先安装"
    fi
done

# 检查是否有管理员权限
if [[ $EUID -ne 0 ]]; then
    error_msg "此脚本需要管理员权限，请使用 sudo 运行"
fi

# 创建工作目录
echo -e "${STEPS} 准备工作环境..."
rm -rf "${WORK_DIR}" 2>/dev/null
mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

# 获取最新的镜像下载链接
echo -e "${STEPS} 获取最新镜像信息..."
RELEASE_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases/tags/${SOURCE_RELEASE}"
RELEASE_INFO=$(curl -s "${RELEASE_URL}")

if [[ -z "${RELEASE_INFO}" ]] || [[ "$(echo "${RELEASE_INFO}" | jq -r '.message // empty')" == "Not Found" ]]; then
    error_msg "无法获取 release 信息: ${SOURCE_RELEASE}"
fi

# 查找匹配的镜像文件，选择日期最新的
echo -e "${INFO} 查找所有匹配 '${DEVICE_NAME}' 的镜像文件..."

# 获取所有匹配的文件名和对应的下载链接
MATCHING_FILES=$(echo "${RELEASE_INFO}" | jq -r --arg device "${DEVICE_NAME}" '.assets[] | select(.name | contains($device) and (.name | endswith(".img.gz") or endswith(".img.xz") or endswith(".img"))) | "\(.name)|\(.browser_download_url)"')

if [[ -z "${MATCHING_FILES}" ]]; then
    echo -e "${WARNING} 未找到包含 '${DEVICE_NAME}' 的镜像文件"
    echo -e "${INFO} 可用的镜像文件："
    echo "${RELEASE_INFO}" | jq -r '.assets[].name' | grep -E '\.(img|gz|xz)' | head -10
    error_msg "请检查设备名称或手动选择镜像文件"
fi

echo -e "${INFO} 找到的匹配镜像文件："
echo "${MATCHING_FILES}"

# 解析文件名中的日期并找到最新的
LATEST_FILE=""
LATEST_DATE=""
LATEST_URL=""

while IFS='|' read -r filename download_url; do
    # 从文件名中提取日期 (格式: YYYY.MM.DD)
    DATE_PART=$(echo "${filename}" | grep -oE '[0-9]{4}\.[0-9]{2}\.[0-9]{2}' | tail -1)
    
    if [[ -n "${DATE_PART}" ]]; then
        echo -e "${INFO} 文件: ${filename} -> 日期: ${DATE_PART}"
        
        # 将日期转换为可比较的格式 (YYYYMMDD)
        COMPARABLE_DATE=$(echo "${DATE_PART}" | sed 's/\.//g')
        
        if [[ -z "${LATEST_DATE}" ]] || [[ "${COMPARABLE_DATE}" > "${LATEST_DATE}" ]]; then
            LATEST_DATE="${COMPARABLE_DATE}"
            LATEST_FILE="${filename}"
            LATEST_URL="${download_url}"
        fi
    else
        echo -e "${WARNING} 文件 ${filename} 中未找到日期信息"
    fi
done <<< "${MATCHING_FILES}"

if [[ -z "${LATEST_FILE}" ]]; then
    error_msg "未找到带有日期信息的镜像文件"
fi

FILENAME="${LATEST_FILE}"
DOWNLOAD_URL="${LATEST_URL}"
ORIGINAL_DATE="${LATEST_DATE:0:4}.${LATEST_DATE:4:2}.${LATEST_DATE:6:2}"

echo -e "${SUCCESS} 选择最新镜像: ${FILENAME} (日期: ${ORIGINAL_DATE})"
echo -e "${INFO} 下载链接: ${DOWNLOAD_URL}"

# 下载镜像文件
echo -e "${STEPS} 下载镜像文件..."
if ! wget -O "${FILENAME}" "${DOWNLOAD_URL}"; then
    error_msg "下载失败: ${FILENAME}"
fi

echo -e "${SUCCESS} 下载完成，文件大小: $(ls -lh "${FILENAME}" | awk '{print $5}')"

# 构建 Flash 镜像
echo -e "${STEPS} 开始构建 Flash 镜像..."
SCRIPT_PATH="../build-armbian/create-flash-image.sh"

if [[ ! -f "${SCRIPT_PATH}" ]]; then
    error_msg "找不到构建脚本: ${SCRIPT_PATH}"
fi

if ! bash "${SCRIPT_PATH}" "${PWD}/${FILENAME}" "${DEVICE_NAME}" "${PWD}"; then
    error_msg "Flash 镜像构建失败"
fi

# 显示构建结果
echo -e "${STEPS} 构建完成统计..."
FLASH_IMAGE=$(ls Flash_*.zip 2>/dev/null | head -1)

if [[ -n "${FLASH_IMAGE}" ]]; then
    echo -e "${SUCCESS} Flash 镜像构建成功！"
    echo -e "${INFO} 源镜像: ${FILENAME}"
    echo -e "${INFO} Flash 镜像: ${FLASH_IMAGE}"
    echo -e "${INFO} 镜像大小: $(ls -lh "${FLASH_IMAGE}" | awk '{print $5}')"
    echo -e "${INFO} SHA256校验: ${FLASH_IMAGE}.sha256"
    echo ""
    echo -e "${WARNING} 使用说明："
    echo -e "  1. 解压: unzip ${FLASH_IMAGE}"
    echo -e "  2. 校验: sha256sum -c ${FLASH_IMAGE}.sha256"
    echo -e "  3. 刷写: 使用 rkdevtool 写入到设备 Flash"
    echo ""
    echo -e "${WARNING} ⚠️  警告：刷写前请备份重要数据！"
    
    # 移动文件到上级目录
    mv "${FLASH_IMAGE}" ../
    mv "${FLASH_IMAGE}.sha256" ../
    echo -e "${INFO} 文件已移动到: $(realpath ../)/${FLASH_IMAGE}"
else
    error_msg "未找到构建完成的 Flash 镜像"
fi

# 清理工作目录
cd ..
rm -rf "${WORK_DIR}"

echo -e "${SUCCESS} 所有操作完成！" 