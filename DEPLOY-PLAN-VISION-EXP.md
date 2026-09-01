# DeepSeek-V4-Flash-Vision-Exp 双机 TP=2 部署方案（DSpark 官方配方）

> 更新时间：2026-09-01
> 部署目录：`/opt/lexdata-ai/cluster-scripts/dsv4-vision-exp/`
> 上游官方仓库：[MiaAI-Lab/DeepSeek-V4-Flash-DSpark-2x-DGX-Spark](https://github.com/MiaAI-Lab/DeepSeek-V4-Flash-DSpark-2x-DGX-Spark)（本目录为其完整副本 + 本地适配）

---

## 1. 部署目标

在 2× DGX Spark（GB10, Grace-Blackwell）上以 **TP=2 双机集群** 方式部署
**DeepSeek-V4-Flash-Vision-Exp**（官方 vision 版本），并注册到 Lexdata-AI-Platform
模型管理平台（http://192.168.21.234:8889/#model-manage），由平台统一管理启停与日志查看。

关键特性：

- 官方 **vision hotfix** 支持（多模态，`LIMIT_MM_PER_PROMPT={"image":8}`）
- `MTP_NUM_TOKENS=6` 多 token 预测、`DEFAULT_THINKING=max` 深度思考
- `MAX_MODEL_LEN=1048576` 超长上下文，`nvfp4_ds_mla` KV 缓存量化
- DSpark 官方预构建镜像 + 全套 hotfix 脚本（与官方配方一致）

## 2. 环境清单

| 项 | 值 |
|---|---|
| head 节点 | 10.10.12.11（对外 192.168.21.234） |
| worker 节点 | 10.10.12.21（spark-cefb, root/Admin@9000） |
| 模型镜像 | `ghcr.nju.edu.cn/anemll/dspark-vllm-gx10:0.1.1`（NJU 镜像，官方 pin `ghcr.io/anemll/...` 改写，digest 与官方一致） |
| 模型权重 | `/data/models/deepseek-ai/DeepSeek-V4-Flash-Vision-Exp`（约 157G，双机已同步） |
| HF commit pin | `86f746b36186f0e567729a5c06a8c918caba82a9` |
| vLLM 端口 | 4110（head 对外 API：`http://192.168.21.234:4110/v1`） |
| head→worker SSH | 免密已配置（官方 start 脚本硬性要求 `ssh -o BatchMode=yes`） |

## 3. 方案核心：官方配方 + 3 个本地适配点

### 3.1 镜像

官方仓库 pin 的 `ghcr.io/anemll/dspark-vllm-gx10:0.1.1` 在本机/worker 均可用；
镜像名改写为 NJU 镜像 `ghcr.nju.edu.cn/anemll/...`（因直连 ghcr.io 受限），
**digest 与官方一致**（两侧 docker 版本不同导致 `docker image inspect` 显示的 ID 不同，属正常现象）。

### 3.2 模型加载路径（扁平目录 → HF hub 结构）

官方 compose 从 HF hub 缓存读取权重。本机权重为扁平目录，采用 **symlink 适配**：

```
/root/.cache/huggingface/hub/models--deepseek-ai--DeepSeek-V4-Flash-Vision-Exp/
├── refs/main          → 86f746b36186f0e567729a5c06a8c918caba82a9
└── snapshots/<commit> → /data/models/deepseek-ai/DeepSeek-V4-Flash-Vision-Exp
```

同时在 `docker-compose.dspark.yml` 增加挂载（让扁平目录权重进容器）：

```yaml
volumes:
  - ${HF_CACHE:-${HOME}/.cache/huggingface}:/cache/huggingface
  - /data/models:/data/models:ro      # ← 本地新增
```

### 3.3 平台集成（包装脚本 + 注册）

- 平台通过 `start.sh / stop.sh / status.sh / logs.sh`（与模型实例同目录）驱动集群启停与日志；
- `start.sh` 透传调用官方 `start-deepseek-v4-flash-dspark.sh`（阻塞式，含 boot warmup）；
- `logs.sh` 按平台解析约定输出 head/worker 两节点容器日志（容器名 `dsv4-vision-exp-vllm-dspark-1`）；
- `PROJECT_NAME=dsv4-vision-exp` 避免与 legacy `deepseek-v4-flash` 实例容器名冲突。

## 4. 关键文件清单（本仓库 = 官方副本 + 本地适配）

### 4.1 官方配方文件（从 GitHub 下载，本机原本缺失）

| 文件 | 说明 |
|---|---|
| `start-deepseek-v4-flash-dspark.sh` | 官方启动脚本（worker 同步、校验、双机拉起、boot warmup） |
| `stop-deepseek-v4-flash-dspark.sh` / `status-...sh` | 官方停止/状态脚本 |
| `validate-dspark-config.sh` | 官方配置校验脚本 |
| `docker-compose.dspark.yml` | 官方双机 compose（**本地已修改**，见 4.2） |
| `.env.dspark.example` | 官方环境变量模板 |
| `patches/` | 全部 hotfix 脚本，含 vision 关键件：`patches/hotfix-dsv4-vision-exp.py`、`patches/vision_exp/`（apply.py / vision.py / image_processor.py / processor.py / __init__.py） |
| `recipe/` | vLLM overlay（deepseek_v4 模型实现、spec_decode 等） |
| `scripts/`、`docs/`、`tests/`、`lmcache/`、`vllm_patch_gb10/` | 官方配套脚本/文档/测试 |

### 4.2 本地修改/新增文件（本次部署的关键产物）

| 文件 | 类型 | 说明 |
|---|---|---|
| `docker-compose.dspark.yml` | **修改** | 增加 `/data/models:/data/models:ro` 挂载（其余保持官方原样） |
| `.env.dspark` | **新增** | 本地生产配置，基于官方 example 适配：镜像、端口 4110、commit pin、RoCE 网卡、`PROJECT_NAME` 等（完整内容见文件本身） |
| `start.sh` | **新增** | 平台启动包装 → 官方 start 脚本 |
| `stop.sh` | **新增** | 平台停止包装 → 官方 stop 脚本 |
| `status.sh` | **新增** | 平台状态包装 → 官方 status 脚本 |
| `logs.sh` | **新增** | 平台日志脚本：head + worker 双节点 `docker logs --tail` |
| `DEPLOY-PLAN-VISION-EXP.md` | **新增** | 本文档（部署方案总结） |

## 5. 校验结果（已完成，双端通过）

1. 官方 `validate-dspark-config.sh .env.dspark` ✅（vLLM 启动命令渲染正确）
2. head `docker compose -p dsv4-vision-exp --env-file .env.dspark config --quiet` ✅
3. worker 同参数校验 ✅
4. head→worker 免密 `ssh -o BatchMode=yes` ✅
5. 平台 `_parse_logs_script_container_names` 解析 `logs.sh` → head/worker 容器名 ✅

## 6. 平台注册信息（已完成）

| 项 | 值 |
|---|---|
| 模型 ID | 20 |
| 名称 | `deepseek-v4-flash-vision-exp` |
| engine | vLLM-dsv4flash（id=6，anemll 镜像） |
| 部署模式 | cluster（双机 TP=2） |
| 端口 | 4110 |
| 状态 | `stop`（未启动） |
| 健康检查 | `http://127.0.0.1:4110/health` |
| 访问地址 | `http://192.168.21.234:4110/v1` |
| tags | `vision,cluster,dsv4`；`vision_enabled=1` |

## 7. 当前状态与下一步

- ✅ 模型权重双机就绪（157G 扁平目录 + HF hub symlink）
- ✅ 镜像双机就绪（NJU 镜像，digest 一致）
- ✅ 部署目录与配置双机就绪、双端 compose 校验通过
- ✅ 平台注册完成（id=20），模型管理页刷新可见
- ⏳ **待启动**：由用户在模型管理页点「启动」按钮（平台调用 `start.sh` → 官方脚本，双机拉起，页面可看日志），或确认后代执行 `start.sh`
- ⏳ 启动后监控 `logs.sh` 与 `:4110/health`、`:4110/v1/models`，确认 vision hotfix 生效、多模态推理可用
- ⏳ 验证通过后在平台将模型标记为启用可用

> 注意：镜像拉取需直连 NJU 镜像站（本机 shell 无代理变量；docker daemon 配了全局代理，拉取需按需处理直连）。
