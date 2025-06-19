# Flash 镜像构建指南

## 概述

此工具用于构建包含完整分区结构的 Flash 刷机包，特别针对 efused-wxy-oec 等需要保留原厂分区的设备。

## Flash 镜像分区结构

Flash 镜像包含以下7个分区，完全按照原厂分区布局：

| 分区号 | 分区名 | 扇区范围 | 大小 | PARTUUID | 描述 |
|-------|--------|----------|------|----------|------|
| 1 | uboot | 16384-24575 | 4MB | 67110000-0000-416d-8000-5693000068fa | U-Boot 分区 |
| 2 | misc | 24576-32767 | 4MB | b8260000-0000-4b79-8000-542300005ce1 | 杂项分区 |
| 3 | boot | 32768-163839 | 64MB | 7c500000-0000-4c1e-8000-6d0000000dd8 | 启动分区（原厂） |
| 4 | kernel | 163840-294911 | 64MB | 9a250000-0000-4d03-8000-231000002148 | 内核分区 |
| 5 | env | 294912-360447 | 32MB | fa2c0000-0000-4405-8000-6d3d00006f9a | 环境变量分区 |
| 6 | boot | 360448-1409023 | 512MB | e2389fdb-8450-4192-83b5-f3ee89b17046 | Armbian 启动分区 |
| 7 | rootfs | 1409024-末尾 | 剩余空间 | 8b4e9cfa-ac66-4e91-8209-da8de6772422 | Armbian 根文件系统 |

**重要特性：**
- 磁盘 GUID: `9F6F0000-0000-4505-8000-6666000042BD`
- 分区6 文件系统 UUID: `e05f8383-636b-4308-aa37-7867505dd45d`
- 分区7 文件系统 UUID: `f961d49a-2cdc-4aa1-b894-e54c56a384f5`
- 所有UUID保持与原厂完全一致，确保系统正常启动

## 自动构建方式（推荐）

### 1. 使用 GitHub Actions

1. 进入仓库的 Actions 页面
2. 选择 "Build Flash Images" workflow
3. 点击 "Run workflow"
4. 配置以下参数：
   - **从哪个release获取源镜像**: 选择包含 Armbian 镜像的 release 标签（默认：`Armbian_bookworm_save_2025.06`）
   - **选择构建设备**: 选择目标设备（默认：`efused-wxy-oec`）
   - **Flash镜像发布标签**: 设置发布到哪个 release（默认：`Armbian_debian`）

5. 等待构建完成
6. 构建完成后，Flash 镜像将自动上传到指定的 release

### 2. 构建流程说明

GitHub Action 会自动执行以下步骤：

1. **环境初始化**: 安装必要的工具（gdisk, parted, zip等）
2. **智能源镜像选择**: 
   - 从指定 release 扫描所有匹配设备的镜像文件
   - 自动解析文件名中的日期信息（如 `2025.06.15`）
   - 选择日期最新的版本进行下载
3. **下载基础分区表**: 从 [tools release](https://github.com/dd-ray/amlogic-s9xxx-armbian/releases/tag/tools) 下载 `part_factory.img.tar.gz`
4. **构建 Flash 镜像**: 
   - 复制原厂分区表结构（保持所有PARTUUID不变）
   - 扩展分区7到整个剩余空间
   - 格式化分区6和7，设置正确的文件系统UUID
   - 将 Armbian 镜像的 boot 和 rootfs 内容复制到对应分区
   - 自动更新 extlinux.conf 中的 rootfs UUID 引用
   - 自动更新 fstab 中的分区 UUID 引用
   - 压缩为 zip 格式
5. **发布镜像**: 上传到指定的 release，同时生成 SHA256 校验文件

### 3. 智能文件选择机制

系统会自动处理一个 release 中的多个镜像文件：

**文件名示例**:
```
Armbian_25.08.0_rockchip_efused-wxy-oec_bookworm_6.12.33_server_2025.06.10.img.gz
Armbian_25.08.0_rockchip_efused-wxy-oec_bookworm_6.12.33_server_2025.06.15.img.gz
Armbian_25.08.0_rockchip_efused-wxy-oec_bookworm_6.12.33_server_2025.06.20.img.gz
```

**选择逻辑**:
- 解析日期：`2025.06.10`, `2025.06.15`, `2025.06.20`
- 自动选择：`2025.06.20`（最新日期）

这确保总是使用最新版本的镜像文件进行构建。

## 手动构建方式

如果需要手动构建 Flash 镜像，可以直接使用构建脚本：

```bash
# 下载或准备 Armbian 镜像文件
wget https://github.com/dd-ray/amlogic-s9xxx-armbian/releases/download/Armbian_bookworm_save_2025.06/Armbian_25.08.0_rockchip_efused-wxy-oec_bookworm_6.12.33_server_2025.06.15.img.gz

# 运行构建脚本
sudo bash build-armbian/create-flash-image.sh \
  "Armbian_25.08.0_rockchip_efused-wxy-oec_bookworm_6.12.33_server_2025.06.15.img.gz" \
  "efused-wxy-oec" \
  "/output/directory"
```

### 脚本参数说明

- **参数1**: 源 Armbian 镜像文件路径（支持 .img, .img.gz, .img.xz 格式）
- **参数2**: 设备名称（用于确定分区布局）
- **参数3**: 输出目录路径

## 使用 Flash 镜像

### 1. 下载镜像

从 [Armbian_debian release](https://github.com/dd-ray/amlogic-s9xxx-armbian/releases/tag/Armbian_debian) 下载对应的 Flash 镜像文件。

### 2. 验证镜像

使用 SHA256 校验文件验证镜像完整性：

```bash
sha256sum -c Flash_Armbian_xxx.img.zip.sha256
```

### 3. 刷写镜像

1. **解压镜像文件**:
   ```bash
   unzip Flash_Armbian_xxx.img.zip
   ```

2. **使用 rkdevtool 刷写**（推荐）:
   - 进入 Maskrom 模式
   - 使用 rkdevtool 加载镜像文件
   - 执行刷写操作

3. **使用 dd 命令刷写**（高级用户）:
   ```bash
   sudo dd if=Flash_Armbian_xxx.img of=/dev/sdX bs=1M status=progress
   ```
   ⚠️ **警告**: 请确保 `/dev/sdX` 是正确的设备路径，错误的路径可能损坏数据！

## 注意事项

### ⚠️ 重要警告

1. **备份数据**: 刷写前请务必备份重要数据
2. **确认设备**: 确保下载的镜像适用于您的设备型号
3. **断电风险**: 刷写过程中不要断电或拔除设备
4. **原厂分区**: Flash 镜像会覆盖所有分区，包括原厂分区

### 支持的设备

目前支持的设备：
- efused-wxy-oec
- 其他支持将在后续版本中添加

### 故障排除

1. **构建失败**: 检查源镜像文件是否完整且格式正确
2. **分区错误**: 确保使用 root 权限运行构建脚本
3. **空间不足**: 确保有足够的磁盘空间（至少是源镜像大小的3倍）
4. **权限问题**: 确保对输出目录有写权限

## 技术细节

### 分区创建

脚本使用 `sgdisk` 工具创建 GPT 分区表，支持大容量存储设备。

### 数据复制

使用循环设备 (loop device) 挂载镜像文件，通过文件系统级别的复制确保数据完整性。

### 压缩格式

最终输出为 ZIP 格式，便于分发和存储。

## 贡献

如需添加对新设备的支持或改进构建流程，请提交 Pull Request 或创建 Issue。

## 许可证

本工具遵循与主项目相同的 GPL v2 许可证。 