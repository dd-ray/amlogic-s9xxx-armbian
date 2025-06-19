#!/bin/bash
#================================================================================================
#
# 用于创建包含原厂分区的Flash刷机包
# Flash镜像结构：1-5分区为原厂分区，6为boot分区，7为系统分区
#
#================================================================================================

# 设置颜色输出
STEPS="[\033[95m STEPS \033[0m]"
INFO="[\033[94m INFO \033[0m]"
SUCCESS="[\033[92m SUCCESS \033[0m]"
ERROR="[\033[91m ERROR \033[0m]"

# 错误处理函数
error_msg() {
    echo -e "${ERROR} ${1}"
    exit 1
}

# 下载OEC基础镜像
download_oec_base() {
    local output_dir="$1"
    local factory_part_url="https://github.com/dd-ray/amlogic-s9xxx-armbian/releases/download/tools/part_factory.img.tar.gz"
    local factory_part_archive="${output_dir}/part_factory.img.tar.gz"
    local factory_part_file="${output_dir}/part_factory.img"
    
    if [[ ! -f "${factory_part_file}" ]]; then
        echo -e "${INFO} 下载OEC基础分区表镜像..." >&2
        # 下载压缩包
        if [[ ! -f "${factory_part_archive}" ]]; then
            wget -O "${factory_part_archive}" "${factory_part_url}" || error_msg "下载OEC基础镜像失败"
        fi
        
        # 解压缩
        echo -e "${INFO} 解压分区表镜像..." >&2
        tar -xzf "${factory_part_archive}" -C "${output_dir}" || error_msg "解压分区表镜像失败"
        
        # 清理压缩包
        rm -f "${factory_part_archive}"
    fi
    echo "${factory_part_file}"
}

# 创建Flash镜像的函数
create_flash_image() {
    local source_img="$1"
    local device_name="$2"
    local output_dir="$3"
    
    echo -e "${STEPS} 开始创建Flash镜像..."
    
    # 检查输入参数
    [[ -z "${source_img}" ]] && error_msg "源镜像文件路径不能为空"
    [[ -z "${device_name}" ]] && error_msg "设备名称不能为空"
    [[ -z "${output_dir}" ]] && error_msg "输出目录不能为空"
    
    # 检查源镜像文件是否存在
    [[ ! -f "${source_img}" ]] && error_msg "源镜像文件不存在: ${source_img}"
    
    # 创建输出目录
    mkdir -p "${output_dir}"
    
    # 下载OEC基础镜像
    factory_part_img=$(download_oec_base "${output_dir}")
    echo -e "${INFO} 基础分区表文件路径: ${factory_part_img}"
    
    # 解压源镜像（如果是压缩格式）
    local work_img="${source_img}"
    if [[ "${source_img}" == *.gz ]]; then
        echo -e "${INFO} 解压源镜像..."
        gunzip -c "${source_img}" > "${output_dir}/temp_source.img"
        work_img="${output_dir}/temp_source.img"
    elif [[ "${source_img}" == *.xz ]]; then
        echo -e "${INFO} 解压源镜像..."
        xz -dc "${source_img}" > "${output_dir}/temp_source.img"
        work_img="${output_dir}/temp_source.img"
    fi
    
    # 创建Flash镜像文件名
    # 获取原始文件名（去除路径和扩展名）
    base_name=$(basename "${source_img}")
    # 去除各种压缩格式的扩展名
    base_name="${base_name%.img.gz}"
    base_name="${base_name%.img.xz}"
    base_name="${base_name%.img}"
    
    flash_img_name="Flash_${base_name}.img"
    flash_img_path="${output_dir}/${flash_img_name}"
    
    echo -e "${INFO} 创建Flash镜像: ${flash_img_name}"
    
    # Flash镜像固定大小：7.28 GiB = 7818182656 bytes = 15269888 sectors
    flash_size_bytes=7818182656
    flash_size_mb=$((flash_size_bytes / 1024 / 1024))
    
    # 创建固定大小的Flash镜像文件
    echo -e "${INFO} 创建固定大小的Flash镜像文件 (7.28 GiB)..."
    dd if=/dev/zero of="${flash_img_path}" bs=1 count=${flash_size_bytes} status=progress
    
    # 创建循环设备
    flash_loop=$(losetup -f)
    losetup "${flash_loop}" "${flash_img_path}"
    
    # 创建Flash镜像的GPT分区表结构
    echo -e "${INFO} 创建Flash镜像的GPT分区表..."
    echo -e "${INFO} 检查基础分区表文件: ${factory_part_img}"
    [[ ! -f "${factory_part_img}" ]] && error_msg "基础分区表文件不存在: ${factory_part_img}"
    
    # 先创建空的GPT分区表
    sgdisk -Z "${flash_loop}" || error_msg "清空分区表失败"
    
    # 设置磁盘GUID（对应原厂分区表）
    sgdisk -U 9F6F0000-0000-4505-8000-6666000042BD "${flash_loop}"
    
    # 创建分区1-5，保持与原厂分区完全相同的起止位置和类型
    echo -e "${INFO} 创建分区1-5（与原厂分区完全匹配）..."
    # 使用0000类型码对应"unknown"类型
    sgdisk -n 1:16384:24575 -t 1:0000 -c 1:"uboot" -u 1:67110000-0000-416d-8000-5693000068fa "${flash_loop}"
    sgdisk -n 2:24576:32767 -t 2:0000 -c 2:"misc" -u 2:b8260000-0000-4b79-8000-542300005ce1 "${flash_loop}"
    sgdisk -n 3:32768:163839 -t 3:0000 -c 3:"boot" -u 3:7c500000-0000-4c1e-8000-6d0000000dd8 "${flash_loop}"
    sgdisk -n 4:163840:294911 -t 4:0000 -c 4:"kernel" -u 4:9a250000-0000-4d03-8000-231000002148 "${flash_loop}"
    sgdisk -n 5:294912:360447 -t 5:0000 -c 5:"env" -u 5:fa2c0000-0000-4405-8000-6d3d00006f9a "${flash_loop}"
    
    # 创建分区6和7
    sgdisk -n 6:360448:1409023 -t 6:8300 -c 6:"boot" -u 6:e2389fdb-8450-4192-83b5-f3ee89b17046 "${flash_loop}"
    sgdisk -n 7:1409024:0 -t 7:8300 -c 7:"rootfs" -u 7:8b4e9cfa-ac66-4e91-8209-da8de6772422 "${flash_loop}"
    
    # 通知内核重新读取分区表
    partprobe "${flash_loop}"
    sleep 2
    
    # 创建基础镜像的循环设备以便复制分区数据
    factory_loop=$(losetup -f)
    losetup -P "${factory_loop}" "${factory_part_img}"
    sleep 2
    
    # 复制原厂分区1-5的数据到Flash镜像对应分区
    echo -e "${INFO} 复制原厂分区数据到Flash镜像..."
    echo -e "${INFO} 复制分区1 (uboot)..."
    dd if="${factory_loop}p1" of="${flash_loop}p1" bs=512 conv=notrunc status=progress 2>/dev/null || true
    echo -e "${INFO} 复制分区2 (misc)..."
    dd if="${factory_loop}p2" of="${flash_loop}p2" bs=512 conv=notrunc status=progress 2>/dev/null || true
    echo -e "${INFO} 复制分区3 (boot)..."
    dd if="${factory_loop}p3" of="${flash_loop}p3" bs=512 conv=notrunc status=progress 2>/dev/null || true
    echo -e "${INFO} 复制分区4 (kernel)..."
    dd if="${factory_loop}p4" of="${flash_loop}p4" bs=512 conv=notrunc status=progress 2>/dev/null || true
    echo -e "${INFO} 复制分区5 (env)..."
    dd if="${factory_loop}p5" of="${flash_loop}p5" bs=512 conv=notrunc status=progress 2>/dev/null || true
    
    # 清理基础镜像的循环设备
    losetup -d "${factory_loop}"
    
    # 显示最终分区表状态
    echo -e "${INFO} Flash镜像完整分区表："
    sgdisk -p "${flash_loop}" || echo "无法显示分区表"
    
    # 挂载源镜像以提取分区内容
    echo -e "${INFO} 挂载源镜像..."
    source_loop=$(losetup -f)
    losetup -P "${source_loop}" "${work_img}"
    sleep 2
    
    # 创建临时挂载点
    temp_mount_boot="/tmp/flash_build_boot"
    temp_mount_root="/tmp/flash_build_root"
    temp_mount_source_boot="/tmp/source_boot"
    temp_mount_source_root="/tmp/source_root"
    
    mkdir -p "${temp_mount_boot}" "${temp_mount_root}" "${temp_mount_source_boot}" "${temp_mount_source_root}"
    
    # 定义UUID变量
    BOOT_UUID="e05f8383-636b-4308-aa37-7867505dd45d"
    ROOTFS_UUID="f961d49a-2cdc-4aa1-b894-e54c56a384f5"
    
    # 格式化Flash镜像的boot和rootfs分区，设置正确的UUID
    echo -e "${INFO} 格式化Flash镜像分区..."
    mkfs.ext4 -F -L "BOOT_EMMC" -U "${BOOT_UUID}" "${flash_loop}p6"
    mkfs.ext4 -F -L "ROOTFS_EMMC" -U "${ROOTFS_UUID}" "${flash_loop}p7"
    
    # 挂载分区
    echo -e "${INFO} 挂载分区进行数据复制..."
    mount "${source_loop}p1" "${temp_mount_source_boot}"
    mount "${source_loop}p2" "${temp_mount_source_root}"
    mount "${flash_loop}p6" "${temp_mount_boot}"
    mount "${flash_loop}p7" "${temp_mount_root}"
    
    # 复制boot分区内容
    echo -e "${INFO} 复制boot分区内容..."
    cp -a "${temp_mount_source_boot}"/* "${temp_mount_boot}/" 2>/dev/null || true
    sync
    
    # 复制rootfs分区内容
    echo -e "${INFO} 复制rootfs分区内容..."
    cp -a "${temp_mount_source_root}"/* "${temp_mount_root}/" 2>/dev/null || true
    sync
    
    # 更新配置文件中的UUID
    echo -e "${INFO} 更新配置文件中的UUID..."
    
    # 更新boot分区中的extlinux.conf
    extlinux_conf="${temp_mount_boot}/extlinux/extlinux.conf"
    if [[ -f "${extlinux_conf}" ]]; then
        echo -e "${INFO} 更新extlinux.conf中的rootfs UUID..."
        # 更新root=UUID=xxx部分
        sed -i "s/root=UUID=[a-fA-F0-9-]*/root=UUID=${ROOTFS_UUID}/g" "${extlinux_conf}"
        echo -e "${INFO} extlinux.conf更新完成"
    else
        echo -e "${INFO} 未找到extlinux.conf文件，跳过更新"
    fi
    
    # 更新rootfs分区中的fstab
    fstab_file="${temp_mount_root}/etc/fstab"
    if [[ -f "${fstab_file}" ]]; then
        echo -e "${INFO} 更新fstab中的UUID..."
        
        # 备份原始fstab
        cp "${fstab_file}" "${fstab_file}.bak"
        
        # 更新rootfs分区的UUID
        sed -i "s/UUID=[a-fA-F0-9-]*\s*\/\s*ext4/UUID=${ROOTFS_UUID} \/ ext4/g" "${fstab_file}"
        
        # 更新boot分区的UUID（如果存在）
        sed -i "s/UUID=[a-fA-F0-9-]*\s*\/boot\s*ext4/UUID=${BOOT_UUID} \/boot ext4/g" "${fstab_file}"
        
        echo -e "${INFO} fstab更新完成"
        echo -e "${INFO} 新的fstab内容："
        cat "${fstab_file}"
    else
        echo -e "${INFO} 未找到fstab文件，跳过更新"
    fi
    
    sync
    
    # 卸载所有分区
    echo -e "${INFO} 卸载分区..."
    umount "${temp_mount_boot}" "${temp_mount_root}" "${temp_mount_source_boot}" "${temp_mount_source_root}" 2>/dev/null || true
    
    # 清理循环设备
    losetup -d "${source_loop}" "${flash_loop}"
    
    # 清理临时文件
    rm -rf "${temp_mount_boot}" "${temp_mount_root}" "${temp_mount_source_boot}" "${temp_mount_source_root}"
    [[ -f "${output_dir}/temp_source.img" ]] && rm -f "${output_dir}/temp_source.img"
    [[ -f "${factory_part_img}" ]] && rm -f "${factory_part_img}"
    
    # 压缩Flash镜像
    echo -e "${INFO} 压缩Flash镜像..."
    cd "${output_dir}"
    zip "${flash_img_name}.zip" "${flash_img_name}"
    rm -f "${flash_img_name}"
    
    echo -e "${SUCCESS} Flash镜像创建完成: ${flash_img_name}.zip"
    echo -e "${INFO} 文件大小: $(ls -lh ${flash_img_name}.zip | awk '{print $5}')"
}

# 主函数
main() {
    echo -e "${STEPS} Flash镜像构建工具启动..."
    
    # 检查参数
    if [[ $# -lt 3 ]]; then
        echo "用法: $0 <源镜像文件> <设备名称> <输出目录>"
        echo "示例: $0 /path/to/Armbian_xxx.img.gz efused-wxy-oec /output"
        exit 1
    fi
    
    create_flash_image "$1" "$2" "$3"
}

# 执行主函数
main "$@" 