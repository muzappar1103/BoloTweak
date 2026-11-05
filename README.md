# BoloTweak

菠萝自用 Tweak 源 · Sileo / Irisin 兼容

**源地址**

```
https://muzappar1103.github.io/BoloTweak/
```

---

## 已有包

| 包名 | 版本 | 架构 | 说明 |
|---|---|---|---|
| `com.bolo.zztaoji` | 1.1.0 | arm64e | **帮我淘鸡** — 转转二手 iPhone 淘机助手：按 iOS 系统版本区间过滤搜索结果，命中商品自动生成清单并直达详情。带悬浮胶囊随时改区间、验机报告缓存。详见 `sileodepiction/com.bolo.zztaoji.html` |
| `com.shijian.filzatofila` | 0.0.14 | arm64e | **FilzaToFila** — Filza 长按菜单加「用 Fila 打开」。基于原作者 **时间会惩罚我** 的 0.0.1-2 版本适配 **iOS 17.2 / RootHide**，保留原始 `fila://view<路径>` 跳转方式，源码见 `source/FilzaToFila/`，适配说明见 `sileodepiction/com.shijian.filzatofila.html` |

---

## 怎么加包

1. 把编译好的 `.deb` 放进 `debs/`
2. 提交并推送

```bash
git add debs/你的包.deb
git commit -m "add 某个 tweak"
git push
```

推上去后 GitHub Actions 会自动重建 `Packages`，1～2 分钟后 Sileo 刷新即可看到。

> **不要手改 `Packages`**。里面的 `Size` / `MD5sum` / `SHA1` / `SHA256`
> 必须和 deb 真实字节一致，手改必错，Sileo 会校验失败。

## 本地预览（可选）

Windows 上没有 `dpkg-scanpackages`，所以带了一个 Python 版生成器：

```bash
python scripts/gen_packages.py            # 生成 Packages + Packages.bz2
python scripts/gen_packages.py --verify   # 只检查，不写文件
```

它会列出每个包的 Package / Version / Architecture，方便你推之前先核对。

重新生成源图标：

```bash
python scripts/make_icon.py
```

## 目录说明

| 路径 | 作用 |
|---|---|
| `index.html` | 引导页（加源按钮） |
| `CydiaIcon.png` | 源图标，Sileo / Irisin 列表里显示 |
| `Release` | 源元信息（名字/维护者/架构） |
| `Packages` | 包索引，**自动生成** |
| `Packages.bz2` | 同上，压缩版 |
| `debs/` | 放 deb 的地方 |
| `source/` | 各包的 tweak 源码（按包名分目录） |
| `sileodepiction/` | 可选，包的详情页 `<包名>.html` |
| `scripts/` | 本地工具 |

## 架构支持

`Release` 里声明了三种架构，RootHide / Dopamine / palera1n 都能正确识别：

```
Architectures: iphoneos-arm iphoneos-arm64 iphoneos-arm64e
```

如果你的包是 `iphoneos-arm64e`（RootHide rootless），只要 deb 的
`Architecture` 字段写对了，Sileo 就会正常归类，不会提示「不兼容」。

## 加源链接

引导页上的两个按钮分别调用：

| 工具 | URL Scheme |
|---|---|
| Sileo | `sileo://source/https://muzappar1103.github.io/BoloTweak/` |
| Irisin | `irisin://repository/add?url=https%3A%2F%2Fmuzappar1103.github.io%2FBoloTweak%2F` |

## 首次部署记得做

仓库 **Settings → Pages** 里：

- Source 选 `Deploy from a branch`
- Branch 选 `main`，目录选 `/ (root)`