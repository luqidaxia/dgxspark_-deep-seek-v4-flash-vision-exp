# DeepSeek-V4-Flash-Vision-Exp · 双机 DSpark 部署（2× DGX Spark, TP=2）

本仓库用于在 **2× NVIDIA DGX Spark（GB10, Grace-Blackwell）** 上以 **TP=2 双机集群** 方式部署
**DeepSeek-V4-Flash-Vision-Exp**（官方多模态版本），并集成到 Lexdata-AI-Platform
模型管理平台统一管理启停与日志。

本仓库 = **官方配方完整副本**（[MiaAI-Lab/DeepSeek-V4-Flash-DSpark-2x-DGX-Spark](https://github.com/MiaAI-Lab/DeepSeek-V4-Flash-DSpark-2x-DGX-Spark)，含全部历史提交）
**+ 本地部署适配**（模型路径挂载、平台包装脚本、生产环境变量）。

---

## 📋 部署方案

完整方案与适配说明见：**[DEPLOY-PLAN-VISION-EXP.md](./DEPLOY-PLAN-VISION-EXP.md)**

官方英文配方文档（上游原样）：**[README-official.en.md](./README-official.en.md)**

## 🏗 架构概览

```
head (10.10.12.11 / 192.0.2.10)  ──── RoCE ────  worker (10.10.12.21)
└─ docker: dspark-vllm-gx10:0.1.1                     └─ docker: dspark-vllm-gx10:0.1.1
   TP rank 0, port 4111                                  TP rank 1
                    │
                    ▼
  Lexdata-AI-Platform  (http://192.0.2.10:8889/#model-manage)
  · 模型 id=21 · engine vLLM-dsv4flash · cluster 模式
  · 容器/工程: dsv4-vision-exp-new · API: http://192.0.2.10:4111/v1 · health: :4111/health
```

## ✨ 关键特性

- ✅ **官方 vision hotfix**：多模态推理（`LIMIT_MM_PER_PROMPT={"image":8}`）
- ✅ **MTP_NUM_TOKENS=6** 多 token 预测 + `DEFAULT_THINKING=low`（默认低思考档，实测 max 每请求延迟 ≈ low 的 3 倍，请求级 `reasoning_effort` 仍可覆盖）
- ✅ **MAX_MODEL_LEN=1048576** 超长上下文 + **`nvfp4_ds_mla` KV 缓存量化 + MXFP4 indexer K cache**（KV 池 ≈ 216 万 token = 1M 的 2.07×）
- ✅ **5 个 opt-in hotfix 现网全开**：ROPE_SWA_FIX / DSPARK_SWA_PREFIX / DSML_RECOVERY / MXFP4_INDEXER_CACHE / DEEPGEMM_SM121_ALIAS（详见「📰 更新记录」）
- ✅ 双机 TP=2、157G 权重、commit pin `86f746b3…`

## 📂 关键文件

### 本地新增 / 修改（本次部署核心产物）

| 文件 | 说明 |
|---|---|
| `.env.dspark` | **生产环境配置**（`.gitignore` 忽略、不提交）：镜像、端口 4111、commit pin、RoCE 网卡、5 个 hotfix 开关全开、`PROJECT_NAME=dsv4-vision-exp-new` |
| `docker-compose.dspark.yml` | 官方 compose **+ `/data/models:/data/models:ro` 挂载**（扁平目录权重进容器） |
| `start.sh` / `stop.sh` / `status.sh` | 平台集群启停/状态包装 → 调用官方脚本 |
| `logs.sh` | 平台日志脚本：head + worker 双节点 `docker logs --tail` |
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
| 2 | head 显存不足 | `Free memory ... is less than desired GPU memory utilization`（Engine core init failed / OOM） | 释放 head 上占显存的进程（llama-server / qwen3 等）；保持 `GPU_MEMORY_UTILIZATION=0.835` 或下调 |
| 3 | GB10 显存 `nvidia-smi` 显示 **Not Supported** | Memory-Usage 查不到显存 | 以 vLLM 启动日志为准（`119.63 GiB`）判断总 / 空闲显存 |
| 4 | 镜像拉取需直连 NJU 镜像站 | 拉取失败 / 超时 | `ghcr.nju.edu.cn/anemll/dspark-vllm-gx10:0.1.1` 需直连；daemon 全局代理按需处理 |
| 5 | 双机权重 / SSH 凭据 | worker 缺权重或免密失败 | 双机各放一份权重；`start.sh` 需平台注入 `HEAD_IP/WORKER_IP/WORKER_SSH_PW` |

> 详细过程见 [DEPLOY-PLAN-VISION-EXP.md](./DEPLOY-PLAN-VISION-EXP.md) 第 8 节。

## 🚀 快速部署（回顾）

```bash
# 0. 前置：权重同步到双机 /data/models/...（157G），镜像双机就绪
# 1. head→worker SSH 免密（官方 start 脚本硬性要求）
ssh-copy-id root@10.10.12.21

# 2. 配置校验（双端均需通过）
bash validate-dspark-config.sh .env.dspark

# 3. 双机 compose 校验（工程名取自 .env.dspark 的 PROJECT_NAME=dsv4-vision-exp-new）
docker compose -p dsv4-vision-exp-new --env-file .env.dspark -f docker-compose.dspark.yml config --quiet

# 4. 启动（双机 TP=2，阻塞式含 warmup；也可在平台点「启动」）
./start.sh

# 5. 查看日志（head + worker）
./logs.sh 60
```

> ⚠️ 镜像 `ghcr.nju.edu.cn/anemll/dspark-vllm-gx10:0.1.1` 需**直连** NJU 镜像站拉取
> （本机 shell 无代理变量；docker daemon 配了全局代理，拉取时按需处理直连）。

## 🖥 在平台 `#model-manage` 加载（平台跑通经验）

在 Lexdata-AI-Platform 模型管理页（`http://192.0.2.10:8889/#model-manage`）直接加载该模型（本次实际跑通方式）：

**① 推理引擎管理（确认/添加推理引擎）**

| 字段 | 值 |
|---|---|
| 引擎名称 | `vLLM-dsv4flash` |
| 镜像（docker_image） | `ghcr.nju.edu.cn/anemll/dspark-vllm-gx10:0.1.1` |

**② 模型实例管理（添加模型）**

| 字段 | 值 |
|---|---|
| 模型名称 | `deepseek-v4-flash-vision-exp-new` |
| 推理引擎 | `vLLM-dsv4flash` |
| 模型类型 | 大语言模型（llm）+ 多模态（`vision_enabled=1`，tags `vision,cluster,dsv4`） |
| 模型路径 | `/data/models/deepseek-ai/DeepSeek-V4-Flash-Vision-Exp`（157G，双机各一份） |
| 部署模式 | **多节点集群（SSH 编排 2 节点）** |
| 集群启动脚本（主节点本地路径） | `/opt/lexdata-ai/cluster-scripts/dsv4-vision-exp-new/start.sh` |
| 集群停止脚本 | `/opt/lexdata-ai/cluster-scripts/dsv4-vision-exp-new/stop.sh` |
| 健康检查 URL | `http://127.0.0.1:4111/health` |
| 访问地址（用户浏览器可达） | `http://192.0.2.10:4111` |

**③ 启动** → 平台状态 `running / healthy`，API：`http://192.0.2.10:4111/v1`
（served 模型名 = `SERVED_MODEL_NAME=deepseek-v4-flash-vision-exp-new`，见 `.env.dspark`；平台模型 id=21）

> vLLM 专属参数（`MTP_NUM_TOKENS=6`、`LIMIT_MM_PER_PROMPT=image=8`、`MAX_MODEL_LEN=1048576`、
> `DEFAULT_THINKING=low`、`GPU_MEMORY_UTILIZATION=0.835`、5 个 hotfix env）在 `.env.dspark` / `docker-compose.dspark.yml`
> 内配置，平台侧通过 `start.sh` 包装脚本读取，**无需在页面重复填**。
>
> ⚠️ 集群模式下 `start.sh` 需平台注入 `HEAD_IP/WORKER_IP/WORKER_SSH_HOST/WORKER_SSH_PW` 环境变量，
> 并依赖节点纳管配置的 worker SSH 凭据（脚本用 `sshpass` 以密码推送/执行 worker 端）。

## 📰 更新记录

### 2026-09-05（二）：现网切换到 `dsv4-vision-exp-new`，5 个 hotfix 全开 + KV cache 实测数据

> 承接上一条「同步上游 PR#226」：该次仅合入代码，**容器未重建**；本条即重建后的结果。
> 现网（本仓库新工作副本 `/opt/lexdata-ai/cluster-scripts/dsv4-vision-exp-new`）已 `./stop` / `./start`
> 重建双机，**5 个 opt-in hotfix 全部 =1 并验证生效**，平台模型 id=21（端口 4111，取代旧 4110 / id=20 实例）。

**5 个 hotfix 开关与各自修复内容**（`.env.dspark` 内 =1）：

| Env（=1） | 修复内容 |
|---|---|
| `DSPARK_ENABLE_ROPE_SWA_FIX` | 移植上游 vllm#54815：启动时不再把 YARN 提升到所有层；稀疏 SWA 层（`compress_ratio<=1`）恢复使用 plain RoPE，长上下文推理正确 |
| `DSPARK_ENABLE_DSPARK_SWA_PREFIX` | 移植 Anemll/dspark-vllm-gx10#2：修 prefix cache 命中时 draft（滑动窗口草稿模型）错误复用其窗口之外的旧 KV；=1 后 target 总重算 draft 滑窗，投机解码不串窗 |
| `DSPARK_ENABLE_DSML_RECOVERY` | 移植上游 vllm#52645：DSML 工具调用输出 wrapper 损坏/裸文本时，不再泄漏进 `content` 正文；请求已声明 tool 前提下在 serving 层恢复为结构化 tool_call |
| `DSPARK_ENABLE_MXFP4_INDEXER_CACHE` | Lightning indexer 的 K 缓存改打包 **MXFP4** 格式（`--attention-config {"use_fp4_indexer_cache":true}`），logits 内核每 key 少读一半字节，降 KV 显存/带宽 |
| `DSPARK_ENABLE_DEEPGEMM_SM121_ALIAS` | DeepGEMM 内核按精确 CC `sm121_*` 命名而镜像只带 `sm120_*`；=1 时 boot 写 alias 头，冷启动无持久 JIT 缓存也能加载 fp4 内核。**官方要求与 MXFP4_INDEXER_CACHE 同开** |

其余相对上游默认的本地差异：`NCCL_GIN_ENABLE=0`（NCCL 网络不发 GPU，按现网 IB 拓扑保持默认 CPU 路径）、
`DEFAULT_THINKING=low`（实测 max 每请求延迟 ≈ low 的 3 倍，同硬件 2×DGX Spark）；ISSUE136/ISSUE191/BLOCK_K/SP_INDEXER
等保持默认关。

**KV cache 实测数据**（以容器启动日志为准，head 为 0.835 GPU util / 119 GiB 统一内存预算）：

| 项 | 实测值 | 说明 |
|---|---|---|
| KV cache dtype | `nvfp4_ds_mla` | DeepSeek V4 padded nvfp4 MLA KV（MXFP4 压缩），`cache.py:287` / `attention.py:107` 确认 |
| indexer K cache | `use_fp4_indexer_cache=True`（indexer_kv_dtype=bf16） | MXFP4 indexer K cache 生效 |
| `block_size` | 256 | — |
| 单 rank 可用 KV 显存 | **18.36 GiB** | `Available KV cache memory`（权重 80.04 GiB + CUDA graph 1.22 GiB 之外的余量） |
| GPU KV cache 池 | **≈2,165,415 tokens**（≈1M 的 **2.07×**） | `Maximum concurrency for 1,048,576 tokens per request: 2.07x` |
| `max_model_len` | **1048576（1M）** | 单请求输入+输出共用上限（显式配置）；KV 池按显存余量自动算出、非恰好 1M |

> 说明：DGX Spark（GB10）`nvidia-smi` 显存栏显示 Not Supported（N/A），显存/KV 数字一律以 vLLM 启动日志为准。

**配套脚本更新**：`logs.sh` 默认容器名改为 `dsv4-vision-exp-new-vllm-dspark-1`（head+worker 双节点）。

### 2026-09-05：同步上游 PR#226（92 commits）

- **同步上游**：本地从 PR#170（`de230b4`，08-31）追上 MiaAI-Lab 上游 `main`（`b1b8dfb` = PR#226，09-05），合入 92 个提交、110 文件（+34578 / −1601）。
- **新增 opt-in hotfix（默认全关，需显式开启后才生效）**：
  - `DSPARK_ENABLE_MXFP4_INDEXER_CACHE=1`：MXFP4 indexer K cache，indexer K 读取带宽减半（需配合 `DSPARK_ENABLE_DEEPGEMM_SM121_ALIAS=1`）
  - `NCCL_GIN_ENABLE`：GPU 发起网络，NCCL comm-init 约 2min → 13s
  - `DSPARK_ENABLE_ROPE_SWA_FIX=1`：移植 vllm#54815，sparse-SWA 层改用 plain RoPE
  - `DSPARK_ENABLE_DSPARK_SWA_PREFIX=1`：修复 prefix cache 命中时 draft 窗口未回填、重复 prompt 退化为截断响应
  - `DSPARK_ENABLE_DSML_RECOVERY=1`：移植 vllm#52645，修复 DSML tool call 泄露进正文
- **vision-exp 补丁链更新**：image token 走 `bias_vl`（#175）、encoder 缓存加 image block 盐（#172）、引号 `<image>` 当正文（#181）、healthcheck 探 `VLLM_HOST`（#185）等。
- **`.env.dspark` 停止跟踪**：移出版本控制（`.gitignore` 忽略），本地文件保留；以后以 `.env.dspark.example` 为源，不再提交生产 env。
- **合并 gitee 3 个文档提交**：README 踩坑速查表、`#model-manage` 加载实操步骤、公开文档内网 IP 脱敏。

> ⚠️ 以上均为代码 / 配置更新，**现网 running 容器（镜像 0.1.1）未重建**；新 hotfix 需显式开启对应 env 开关并 `./stop` / `./start` 重建双机后才生效。

---

## 📌 当前状态（2026-09-05 重建切换后 running）

| 项目 | 状态 |
|---|---|
| 工作目录 / compose 工程 | ✅ `/opt/lexdata-ai/cluster-scripts/dsv4-vision-exp-new`，`PROJECT_NAME=dsv4-vision-exp-new` |
| 平台注册（模型 id=21，端口 4111） | ✅ 完成（替代旧 4110 / id=20 实例） |
| 5 个 opt-in hotfix | ✅ 全部 =1，重建后验证生效（见「📰 更新记录」） |
| KV cache | ✅ `nvfp4_ds_mla` + MXFP4 indexer K cache，单 rank 18.36 GiB / 池 ≈216 万 token |
| 模型启动 | ✅ **running**（双机 TP=2 拉起成功） |
| 健康检查 | ✅ `http://192.0.2.10:4111/health` → healthy |
| 访问地址 | ✅ `http://192.0.2.10:4111/v1`（vLLM 监听 4111，served = `deepseek-v4-flash-vision-exp-new`） |

> 💡 部署过程踩坑（`LIMIT_MM_PER_PROMPT` 引号、head 显存不足）见
> [DEPLOY-PLAN-VISION-EXP.md](./DEPLOY-PLAN-VISION-EXP.md) 第 8 节。

## 🔗 相关

- 上游官方仓库：<https://github.com/MiaAI-Lab/DeepSeek-V4-Flash-DSpark-2x-DGX-Spark>
- 模型权重（HF）：`deepseek-ai/DeepSeek-V4-Flash-Vision-Exp`，commit `86f746b36186f0e567729a5c06a8c918caba82a9`
