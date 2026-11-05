# FilzaToFila

在 Filza 文件长按菜单中添加「用 Fila 打开」。

## 来源与适配说明

本 tweak 基于原作者 **时间会惩罚我** 的 `com.shijian.filzatofila` 0.0.1-2 工作进行适配，保留原有的 `fila://view<Filza 当前路径>` 跳转方式。

本仓库版本适配设备环境：**iOS 17.2 / RootHide**，并针对该设备 Filza bundle id `com.bat.petal` 调整注入过滤与 RootHide 打包。菜单识别和当前浏览路径发现逻辑也根据实际设备行为做了适配，并保留诊断日志。

作者署名和原始实现来源均予保留；本版本不是原作者发布的官方更新。

## 目录内容

- `Tweak.x`：Logos / Objective-C tweak 实现
- `Makefile`：roothide/Theos 构建配置，目标架构 `arm64e arm64`
- `FilzaToFila.plist`：仅注入 Filza bundle id `com.bat.petal`
- `control`：RootHide 可安装 deb 的包元数据

## 在已配置 roothide/theos 的 macOS 环境编译

```sh
export THEOS="$HOME/theos-roothide"
cd FilzaToFila
make clean
make package
```

生成的 deb 位于 `packages/`。安装到设备后，彻底退出并重新打开 Filza。

## 当前行为

「用 Fila 打开」会调用 `fila://view` 并传递 Filza 当前浏览路径。因此，文件和文件夹均会在 Fila 中打开其所在目录。菜单仅在包含文件操作项目（包括重命名操作）的主文件菜单中插入一次。

诊断日志写入 Filza 的 `Documents/filzatofila.log`；可在设备的 `/var/mobile/Documents/filzatofila.log` 检查运行记录。

## 适配验证环境

- iPhone16,2
- iOS 17.2 (21C62)
- RootHide，jbroot 由运行环境动态映射
- Filza bundle id：`com.bat.petal`
- Fila bundle id：`wiki.qaq.fila`

其他 iOS、越狱方案、Filza/Fila 版本尚未验证。

## 仓库发布说明

仓库 `debs/` 里发布的是 `0.0.14-2+debug`：

- tweak 二进制与 `0.0.14-1` **完全一致**（`data.tar.gz` 逐字节相同）
- 只重写了 `control`，把「基于原作者 时间会惩罚我 的工作适配 iOS 17.2 / RootHide」的说明写进 `Description`，
  这样在 Sileo / Irisin 的包页面（介绍区）直接可见，而不是只在网页详情页里

`control` 里仍是 `Version: 0.0.14`（上游版本号），`-1/-2` 是打包修订号，由打包时附加。