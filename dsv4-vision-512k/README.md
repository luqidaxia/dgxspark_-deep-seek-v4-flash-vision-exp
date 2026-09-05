# DeepSeek-V4-Flash-Vision-512k · 双机 DSpark 部署（2× DGX Spark, TP=2）

本部署用于在 **2× NVIDIA DGX Spark（GB10, Grace-Blackwell）** 上以 **TP=2 双机集群** 方式部署
**DeepSeek-V4-Flash-Vision-512k**（官方多模态版本、512k 上下文 profile），并集成到
Lexdata-AI-Platform 模型管理平台统一管理启停与日志。

本部署 = **官方配方完整副本**（[MiaAI-Lab/DeepSeek-V4-Flash-DSpark-2x-DGX-Spark](https://github.com/MiaAI-Lab/DeepSeek-V4-Flash-DSpark-2x-DGX-Spark)，含全部历史提交）
**+ 本地部署适配**（模型路径挂载、平台包装脚本、生产环境变量）。

> 与现网 vision-exp-new（1M 上下文 / 端口 4111 / `nvfp4_ds_mla` KV / 5 hotfix 全开）的区别：
> 本实例为 **512k 上下文 / 端口 4112 / `fp8` KV / 3 个 hotfix 开启**，served 模型名
> `deepseek-v4-flash-vision-512k`，双实例同机共存互不影响。

---

## 📋 部署方案

完整方案与适配说明见：**[DEPLOY-PLAN-VISION-EXP.md](./DEPLOY-PLAN-VISION-EXP.md)**

官方英文配方文档（上游原样）：**[README-official.en.md](./README-official.en.md)**

## 🏗 架构概览

```
head (10.10.12.11 / 192.0.2.10)  ──── RoCE ────  worker (10.10.12.21)
└─ docker: dspark-vllm-gx10:0.1.1                     └─ docker: dspark-vllm-gx10:0.1.1
   TP rank 0, port 4112                                  TP rank 1
                    │
                    ▼
  Lexdata-AI-Platform  (http://192.0.2.10:8889/#model-manage)
  · 部署目录: /opt/lexdata-ai/cluster-scripts/dsv4-vision-512k · engine vLLM-dsv4flash · cluster 模式
  · 容器/工程: dsv4-vision-512k · API: http://192.0.2.10:4112/v1 · health: :4112/health
```

## ✨ 关键特性

- ✅ **官方 vision hotfix**：多模态推理（`LIMIT_MM_PER_PROMPT=image=8`）
- ✅ **MTP_NUM_TOKENS=6** 多 token 预测 + `DEFAULT_THINKING=low`（默认低思考档，实测 max 每请求延迟 ≈ low 的 3 倍，请求级 `reasoning_effort` 仍可覆盖）
- ✅ **MAX_MODEL_LEN=524288（512k 上下文）** + **`fp8` KV cache dtype**（docker-compose 内 `--kv-cache-dtype fp8`）
- ✅ **3 个 opt-in hotfix 开启**：ROPE_SWA_FIX / DSPARK_SWA_PREFIX / DSML_RECOVERY（`MXFP4_INDEXER_CACHE` / `DEEPGEMM_SM121_ALIAS` 保持关，详见「📰 更新记录」）
- ✅ 双机 TP=2、157G 权重、commit pin `86f746b3…`、MASTER_PORT=25002（与 1M 实例 25001 错开）

## 📂 关键文件

### 本地新增 / 修改（本次部署核心产物）

| 文件 | 说明 |
|---|---|
| `.env.dspark` | **生产环境配置**（`.gitignore` 忽略、不提交）：镜像、端口 4112、MASTER_PORT 25002、commit pin、RoCE 网卡、3 个 hotfix 开关 =1、`PROJECT_NAME=dsv4-vision-512k`、`SERVED_MODEL_NAME=deepseek-v4-flash-vision-512k` |
| `docker-compose.dspark.yml` | 官方 compose **+ `/data/models:/data/models:ro` 挂载** + `--kv-cache-dtype fp8` |
| `start.sh` / `stop.sh` / `status.sh` | 平台集群启停/状态包装 → 调用官方脚本 |
| `logs.sh` | 平台日志脚本：head + worker 双节点 `docker logs --tail`（容器名 `dsv4-vision-512k-vllm-dspark-1`） |
| `DEPLOY-PLAN-VISION-EXP.md` | 部署方案总结（本文档的详细版） |

### 官方配方（GitHub 下载，本机原本缺失）

| 文件 | 说明 |
|---|---|
| `start-deepseek-v4-flash-dspark.sh` | 官方启动脚本（worker 同步、双机拉起、boot warmup） |
| `stop-…` / `status-…` / `validate-dspark-config.sh` | 官方停止 / 状态 / 配置校验 |
| `patches/` | 全部 hotfix，含 vision 关键件：`hotfix-dsv4-vision-exp.py`、`vision_exp/` |
| `recipe/` · `scripts/` · `docs/` · `tests/` | vLLM overlay 与配套脚本文档 |

## ⚠️ 踩坑速查（部署前必看）

| # | 坑 | 现象 | 对策 |
|---|---|---|---|
| 1 | `LIMIT_MM_PER_PROMPT` 双引号被 env 解析吃掉 | vllm serve 报 `--limit-mm-per-prompt: Value {image:8} cannot be converted` 直接退出 | `.env.dspark` 用简写 `LIMIT_MM_PER_PROMPT=image=8`，**不要写 `{"image":8}`** |
| 2 | head 显存不足 | `Free memory ... is less than desired GPU memory utilization`（Engine core init failed / OOM） | 释放 head 上占显存的进程（llama-server / qwen3 等）；保持 `GPU_MEMORY_UTILIZATION_TEXT=0.835` 或下调 |
| 3 | GB10 显存 `nvidia-smi` 显示 **Not Supported** | Memory-Usage 查不到显存 | 以 vLLM 启动日志为准（`119.63 GiB`）判断总 / 空闲显存 |
| 4 | 镜像拉取需直连 NJU 镜像站 | 拉取失败 / 超时 | `ghcr.nju.edu.cn/anemll/dspark-vllm-gx10:0.1.1` 需直连；daemon 全局代理按需处理 |
| 5 | 双机权重 / SSH 凭据 | worker 缺权重或免密失败 | 双机各放一份权重；`start.sh` 需平台注入 `HEAD_IP/WORKER_IP/WORKER_SSH_PW` |
| 6 | 与 1M 实例同机共存端口冲突 | host 网络双实例端口冲突 | 已错开：本实例 `VLLM_PORT=4112`、`MASTER_PORT=25002`（1M 实例为 4111 / 25001） |

> 详细过程见 [DEPLOY-PLAN-VISION-EXP.md](./DEPLOY-PLAN-VISION-EXP.md) 第 8 节。

## 🚀 快速部署（回顾）

```bash
# 0. 前置：权重同步到双机 /data/models/...（157G），镜像双机就绪
# 1. head→worker SSH 免密（官方 start 脚本硬性要求）
ssh-copy-id root@10.10.12.21

# 2. 配置校验（双端均需通过）
bash validate-dspark-config.sh .env.dspark

# 3. 双机 compose 校验（工程名取自 .env.dspark 的 PROJECT_NAME=dsv4-vision-512k）
docker compose -p dsv4-vision-512k --env-file .env.dspark -f docker-compose.dspark.yml config --quiet

# 4. 启动（双机 TP=2，阻塞式含 warmup；也可在平台点「启动」）
./start.sh

# 5. 查看日志（head + worker）
./logs.sh 60
```

> ⚠️ 镜像 `ghcr.nju.edu.cn/anemll/dspark-vllm-gx10:0.1.1` 需**直连** NJU 镜像站拉取
> （本机 shell 无代理变量；docker daemon 配了全局代理，拉取时按需处理直连）。

## 🖥 在平台 `#model-manage` 加载（平台跑通经验）

在 Lexdata-AI-Platform 模型管理页（`http://192.0.2.10:8889/#model-manage`）直接加载该模型：

**① 推理引擎管理（确认/添加推理引擎）**

| 字段 | 值 |
|---|---|
| 引擎名称 | `vLLM-dsv4flash` |
| 镜像（docker_image） | `ghcr.nju.edu.cn/anemll/dspark-vllm-gx10:0.1.1` |

**② 模型实例管理（添加模型）**

| 字段 | 值 |
|---|---|
| 模型名称 | `deepseek-v4-flash-vision-512k` |
| 推理引擎 | `vLLM-dsv4flash` |
| 模型类型 | 大语言模型（llm）+ 多模态（`vision_enabled=1`，tags `vision,cluster,dsv4`） |
| 模型路径 | `/data/models/deepseek-ai/DeepSeek-V4-Flash-Vision-Exp`（157G，双机各一份） |
| 部署模式 | **多节点集群（SSH 编排 2 节点）** |
| 集群启动脚本（主节点本地路径） | `/opt/lexdata-ai/cluster-scripts/dsv4-vision-512k/start.sh` |
| 集群停止脚本 | `/opt/lexdata-ai/cluster-scripts/dsv4-vision-512k/stop.sh` |
| 健康检查 URL | `http://127.0.0.1:4112/health` |
| 访问地址（用户浏览器可达） | `http://192.0.2.10:4112` |

**③ 启动** → 平台状态 `running / healthy`，API：`http://192.0.2.10:4112/v1`
（served 模型名 = `SERVED_MODEL_NAME=deepseek-v4-flash-vision-512k`，见 `.env.dspark`）

> vLLM 专属参数（`MTP_NUM_TOKENS=6`、`LIMIT_MM_PER_PROMPT=image=8`、`MAX_MODEL_LEN=524288`、
> `DEFAULT_THINKING=low`、`GPU_MEMORY_UTILIZATION_TEXT=0.835`、hotfix env、`--kv-cache-dtype fp8`）
> 在 `.env.dspark` / `docker-compose.dspark.yml` 内配置，平台侧通过 `start.sh` 包装脚本读取，
> **无需在页面重复填**。
>
> ⚠️ 集群模式下 `start.sh` 需平台注入 `HEAD_IP/WORKER_IP/WORKER_SSH_HOST/WORKER_SSH_PW` 环境变量，
> 并依赖节点纳管配置的 worker SSH 凭据（脚本用 `sshpass` 以密码推送/执行 worker 端）。

## 📰 更新记录

### 2026-09-05：新增 `dsv4-vision-512k` 实例（512k 上下文 profile）

- **新增独立实例**：在现网 `dsv4-vision-exp-new`（1M）之外，复制创建 512k profile 实例
  `/opt/lexdata-ai/cluster-scripts/dsv4-vision-512k`，双实例同机共存。
- **与 1M 实例差异**：
  | 项 | 1M 实例（exp-new） | 本实例（512k） |
  |---|---|---|
  | `SERVED_MODEL_NAME` | `deepseek-v4-flash-vision-exp-new` | `deepseek-v4-flash-vision-512k` |
  | `VLLM_PORT` / `MASTER_PORT` | 4111 / 25001 | **4112 / 25002** |
  | `MAX_MODEL_LEN` | 1048576（1M） | **524288（512k）** |
  | KV cache dtype | `nvfp4_ds_mla`（+ MXFP4 indexer K cache） | **`fp8`**（`--kv-cache-dtype fp8`） |
  | hotfix | 5 个全开 | **3 个开启**：`ROPE_SWA_FIX` / `DSPARK_SWA_PREFIX` / `DSML_RECOVERY` =1；`MXFP4_INDEXER_CACHE` / `DEEPGEMM_SM121_ALIAS` =0 |
  | `MAX_NUM_SEQS` / `MAX_NUM_BATCHED_TOKENS` | — | 6 / 8192 |
- **512k 上下文基准结论**（参考 `cluster/benchmark-context-20260902/`，fp8-512k 实例 4108 实测）：
  512k 满上下文功能可用（KV 无压力），但未命中 prefix cache 时全量 prefill 约 ~107s；
  命中缓存时 512k TTFT 仅 ~0.5–0.7s —— **长上下文场景应复用固定前缀以命中缓存**。

**hotfix 开关语义**（`.env.dspark` 内 =1 的 3 个）：

| Env（=1） | 修复内容 |
|---|---|
| `DSPARK_ENABLE_ROPE_SWA_FIX` | 移植上游 vllm#54815：启动时不再把 YARN 提升到所有层；稀疏 SWA 层（`compress_ratio<=1`）恢复使用 plain RoPE，长上下文推理正确 |
| `DSPARK_ENABLE_DSPARK_SWA_PREFIX` | 移植 Anemll/dspark-vllm-gx10#2：修 prefix cache 命中时 draft（滑动窗口草稿模型）错误复用其窗口之外的旧 KV；=1 后 target 总重算 draft 滑窗，投机解码不串窗 |
| `DSPARK_ENABLE_DSML_RECOVERY` | 移植上游 vllm#52645：DSML 工具调用输出 wrapper 损坏/裸文本时，不再泄漏进 `content` 正文；请求已声明 tool 前提下在 serving 层恢复为结构化 tool_call |

> 相对上游默认的本地差异：`NCCL_GIN_ENABLE=0`（NCCL 网络不发 GPU，按现网 IB 拓扑保持默认 CPU 路径）、
> `DEFAULT_THINKING=low`（实测 max 每请求延迟 ≈ low 的 3 倍，同硬件 2×DGX Spark）；
> ISSUE136/ISSUE191/BLOCK_K/SP_INDEXER/MXFP4_INDEXER_CACHE/DEEPGEMM_SM121_ALIAS 等保持默认关。

## 📌 当前状态（2026-09-05）

| 项目 | 状态 |
|---|---|
| 工作目录 / compose 工程 | ✅ `/opt/lexdata-ai/cluster-scripts/dsv4-vision-512k`，`PROJECT_NAME=dsv4-vision-512k` |
| served 模型名 | ✅ `deepseek-v4-flash-vision-512k` |
| 端口 | ✅ `VLLM_PORT=4112`（与 1M 实例 4111 共存） |
| 3 个 opt-in hotfix | ✅ ROPE_SWA_FIX / DSPARK_SWA_PREFIX / DSML_RECOVERY =1 |
| KV cache | ✅ `fp8` |
| 健康检查 | ✅ `http://192.0.2.10:4112/health` |
| 访问地址 | ✅ `http://192.0.2.10:4112/v1` |

> 💡 部署过程踩坑（`LIMIT_MM_PER_PROMPT` 引号、head 显存不足）见
> [DEPLOY-PLAN-VISION-EXP.md](./DEPLOY-PLAN-VISION-EXP.md) 第 8 节。

## 🔗 相关

- 上游官方仓库：<https://github.com/MiaAI-Lab/DeepSeek-V4-Flash-DSpark-2x-DGX-Spark>
- 模型权重（HF）：`deepseek-ai/DeepSeek-V4-Flash-Vision-Exp`，commit `86f746b36186f0e567729a5c06a8c918caba82a9`
