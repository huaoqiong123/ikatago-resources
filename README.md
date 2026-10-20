# ikatago-resources

一键在 **Linux + NVIDIA GPU** 机器上安装 [KataGo](https://github.com/lightvector/KataGo)（CUDA 版）、推荐权重和 [ikatago-server](https://github.com/kinfkong/ikatago-server)。

## 快速开始

```bash
curl -fsSL https://raw.githubusercontent.com/huaoqiong123/ikatago-resources/main/install.sh | bash
# 带参数：
curl -fsSL https://raw.githubusercontent.com/huaoqiong123/ikatago-resources/main/install.sh | bash -s -- --network b28
```

安装完成后：

```bash
~/ikatago/start-benchmark.sh          # 测速，按建议调整 configs/gtp.cfg 中的 numSearchThreads
~/ikatago/start-gtp.sh                # GTP 模式（接 Sabaki / Lizzie 等）
~/ikatago/start-analysis.sh           # JSON analysis 引擎
~/ikatago/start-ikatago-server.sh --help   # ikatago-server，参数以 --help 为准
```

## 选项

| 参数 | 环境变量 | 说明 |
|---|---|---|
| `--dry-run` | `DRY_RUN=1` | 只检测并打印计划，不下载、不写文件 |
| `--network b18\|b28` | `NETWORK` | 权重，默认 b18（更快）；b28 更强但更慢、显存需求更大 |
| `--install-dir DIR` | `INSTALL_DIR` | 默认 `~/ikatago` |
| `--cuda 12.1\|12.8\|13.2` | `FORCE_CUDA` | 强制指定 KataGo CUDA 版本（其他取值会报错） |
| `--no-upstream-fallback` | `UPSTREAM_FALLBACK=0` | 本仓库 Release 下载失败时不回退到上游地址 |
| `--skip-gpu-check` | `SKIP_GPU_CHECK=1` | 无 nvidia-smi 也继续 |
| | `MANIFEST_FILE` / `MANIFEST_URL` | 使用外部 manifest 替代脚本内嵌的 manifest |
| | `RETRIES` | 每个地址的重试次数，默认 3 |

## 安装流程

1. 检查依赖：`curl`/`wget`、`unzip`、`sha256sum`。
2. 通过 `nvidia-smi` 读取驱动版本和驱动支持的最高 CUDA 版本，选择 KataGo 构建：
   - CUDA ≥ 13.2 → `cuda13.2-cudnn9.24.0`
   - CUDA ≥ 12.8 → `cuda12.8-cudnn9.8.0`
   - CUDA ≥ 12.1 → `cuda12.1-cudnn8.9.7`
   - 更低版本 → 报错，提示升级驱动
   - 找不到 `nvidia-smi` → 以退出码 2 退出，并给出中英文提示
3. 先从本仓库 GitHub Releases 下载，校验 sha256；失败会重试（递增等待），仍失败则回退到上游原始地址（同样校验 sha256）。已下载且校验通过的文件不会重复下载。
4. 解压并生成启动脚本。

### CUDA / cuDNN 运行库（重要）

KataGo v1.18.2 的 Linux 包是 **AppImage**，但**不包含** CUDA 运行库（实测缺 `libcublas.so.12`）。你需要自行安装与文件名一致的 CUDA Toolkit 运行库（cudart、cuBLAS）和 cuDNN，例如 `cuda12.8-cudnn9.8.0` 对应 CUDA 12.8 和 cuDNN 9.x。没有 FUSE2 时，四个启动脚本（含 `start-ikatago-server.sh`）都会自动加上 `APPIMAGE_EXTRACT_AND_RUN=1`。安装结束时脚本会在 `ldconfig` 缓存里查找 `libcublas` / `libcudnn`，找不到只给出警告（通过 `LD_LIBRARY_PATH` 提供的库不会出现在缓存里，可忽略）。

## 安装后的目录结构

```
~/ikatago/
├── downloads/                 # 原始下载文件（用于缓存和校验）
├── katago/katago              # KataGo 可执行文件（AppImage）及官方示例配置
├── networks/<权重>.bin.gz      # 权重；default.bin.gz 是指向它的软链接
├── configs/gtp.cfg            # 来自 default_gtp.cfg
├── configs/analysis.cfg       # 来自 analysis_example.cfg
├── ikatago-server/ikatago-server-5.0.1-linux/ikatago-server
├── start-gtp.sh  start-analysis.sh  start-benchmark.sh  start-ikatago-server.sh
```

## 仓库结构

```
install.sh                 # 安装脚本（内嵌 manifest）
manifest.tsv               # 资源清单：id filename url sha256 size source_url license
scripts/update-manifest.sh # 重新计算 sha256/size，并把 manifest 写回 install.sh
tests/test_install.sh      # 不需要 GPU 的测试（模拟 nvidia-smi + dry-run）
licenses/                  # KataGo LICENSE、katagotraining 权重许可证
```

## 更新版本 / Release 资源

1. 把新文件下载到 `../ikatago-resources-release-assets/`。
2. 编辑 `manifest.tsv`：修改文件名、`url`（`https://github.com/huaoqiong123/ikatago-resources/releases/download/<tag>/<file>`）和 `source_url`；新增 CUDA 版本时还要修改 `install.sh` 中的版本选择逻辑。
3. 运行 `scripts/update-manifest.sh ../ikatago-resources-release-assets`，它会重新计算 sha256/size 并更新 `install.sh` 内嵌的 manifest。
4. 测试：`bash -n install.sh && shellcheck install.sh && tests/test_install.sh`。
5. 发布：

```bash
TAG=v1.0.1
gh release create "$TAG" --repo huaoqiong123/ikatago-resources --title "$TAG" --notes "KataGo/networks update"
gh release upload "$TAG" --repo huaoqiong123/ikatago-resources ../ikatago-resources-release-assets/*
git commit -am "Update assets to $TAG" && git push
```

## 来源与许可证

| 资源 | 来源 | 许可证 |
|---|---|---|
| KataGo v1.18.2（CUDA Linux x64） | https://github.com/lightvector/KataGo/releases/tag/v1.18.2 | MIT（`licenses/KataGo-LICENSE.txt`） |
| kata1-b18c384nbt-s9996604416-d4316597426 | https://katagotraining.org/networks/ | katagotraining.org 网络许可证（MIT 式，`licenses/katago-network-license.txt`，见 https://katagotraining.org/network_license/） |
| kata1-b28c512nbt-s13255194368-d5935380940 | 同上 | 同上 |
| ikatago-server 5.0.1（linux） | https://github.com/kinfkong/ikatago-server/releases/tag/v5.0.1 | **上游仓库没有 LICENSE 文件**，是否允许再分发不明确 |

> 关于 ikatago-server：上游没有声明许可证，二次分发的授权不明确。在得到作者 kinfkong 的许可之前，不要把它上传到本仓库的 Release：`manifest.tsv` 中 `ikatago_server` 的 `url` 直接指向上游地址，安装脚本始终从上游下载并校验 sha256。

本仓库脚本本身采用 MIT 许可证。
