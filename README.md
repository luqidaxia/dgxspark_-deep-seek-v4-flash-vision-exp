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
head (10.10.12.11 / 192.168.21.234)  ──── RoCE ────  worker (10.10.12.21)
└─ docker: dspark-vllm-gx10:0.1.1                     └─ docker: dspark-vllm-gx10:0.1.1
   TP rank 0, port 4110                                  TP rank 1
                     │
                     ▼
   Lexdata-AI-Platform  (http://192.168.21.234:8889/#model-manage)
   · 模型 id=20 · engine vLLM-dsv4flash · cluster 模式
   · API: http://192.168.21.234:4110/v1 · health: :4110/health
```

## ✨ 关键特性

- ✅ **官方 vision hotfix**：多模态推理（`LIMIT_MM_PER_PROMPT={"image":8}`）
- ✅ **MTP_NUM_TOKENS=6** 多 token 预测 + `DEFAULT_THINKING=max` 深度思考
- ✅ **MAX_MODEL_LEN=1048576** 超长上下文 + `nvfp4_ds_mla` KV 缓存量化
- ✅ 双机 TP=2、157G 权重、commit pin `86f746b3…`

## 📂 关键文件

### 本地新增 / 修改（本次部署核心产物）

| 文件 | 说明 |
|---|---|
| `.env.dspark` | **生产环境配置**：镜像、端口 4110、commit pin、RoCE 网卡、`PROJECT_NAME=dsv4-vision-exp` |
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

# 3. 双机 compose 校验
docker compose -p dsv4-vision-exp --env-file .env.dspark -f docker-compose.dspark.yml config --quiet

# 4. 启动（双机 TP=2，阻塞式含 warmup；也可在平台点「启动」）
./start.sh

# 5. 查看日志（head + worker）
./logs.sh 60
```

> ⚠️ 镜像 `ghcr.nju.edu.cn/anemll/dspark-vllm-gx10:0.1.1` 需**直连** NJU 镜像站拉取
> （本机 shell 无代理变量；docker daemon 配了全局代理，拉取时按需处理直连）。

## 🖥 在平台 `#model-manage` 加载（平台跑通经验）

在 Lexdata-AI-Platform 模型管理页（`http://192.168.21.234:8889/#model-manage`）直接加载该模型（本次实际跑通方式）：

**① 推理引擎管理（确认/添加推理引擎）**

| 字段 | 值 |
|---|---|
| 引擎名称 | `vLLM-dsv4flash` |
| 镜像（docker_image） | `ghcr.nju.edu.cn/anemll/dspark-vllm-gx10:0.1.1` |

**② 模型实例管理（添加模型）**

| 字段 | 值 |
|---|---|
| 模型名称 | `deepseek-v4-flash-vision-exp` |
| 推理引擎 | `vLLM-dsv4flash` |
| 模型类型 | 大语言模型（llm）+ 多模态（`vision_enabled=1`，tags `vision,cluster,dsv4`） |
| 模型路径 | `/data/models/deepseek-ai/DeepSeek-V4-Flash-Vision-Exp`（157G，双机各一份） |
| 部署模式 | **多节点集群（SSH 编排 2 节点）** |
| 集群启动脚本（主节点本地路径） | `/opt/lexdata-ai/cluster-scripts/deepseek-v4-flash-vision-exp/start.sh` |
| 集群停止脚本 | `/opt/lexdata-ai/cluster-scripts/deepseek-v4-flash-vision-exp/stop.sh` |
| 健康检查 URL | `http://127.0.0.1:4110/health` |
| 访问地址（用户浏览器可达） | `http://192.168.21.234:4110` |

**③ 启动** → 平台状态 `running / healthy`，API：`http://192.168.21.234:4110/v1`
（served 模型名 = `SERVED_MODEL_NAME=deepseek-v4-flash-vision-exp`，见 `.env.dspark`）

> vLLM 专属参数（`MTP_NUM_TOKENS=6`、`LIMIT_MM_PER_PROMPT=image=8`、`MAX_MODEL_LEN=1048576`、
> `DEFAULT_THINKING=max`、`GPU_MEMORY_UTILIZATION=0.835`）在 `.env.dspark` / `docker-compose.dspark.yml`
> 内配置，平台侧通过 `start.sh` 包装脚本读取，**无需在页面重复填**。
>
> ⚠️ 集群模式下 `start.sh` 需平台注入 `HEAD_IP/WORKER_IP/WORKER_SSH_HOST/WORKER_SSH_PW` 环境变量，
> 并依赖节点纳管配置的 worker SSH 凭据（脚本用 `sshpass` 以密码推送/执行 worker 端）。

## 📌 当前状态（2026-09-01 已成功运行）

| 项目 | 状态 |
|---|---|
| 权重 / 镜像 / 免密 / 双端校验 | ✅ 就绪 |
| 平台注册（模型 id=20，端口 4110） | ✅ 完成 |
| 模型启动 | ✅ **running**（双机 TP=2 拉起成功） |
| 健康检查 | ✅ `http://192.168.21.234:4110/health` → healthy |
| 访问地址 | ✅ `http://192.168.21.234:4110/v1`（vLLM 监听 4110） |

> 💡 部署过程踩坑（`LIMIT_MM_PER_PROMPT` 引号、head 显存不足）见
> [DEPLOY-PLAN-VISION-EXP.md](./DEPLOY-PLAN-VISION-EXP.md) 第 8 节。

## 🔗 相关

- 上游官方仓库：<https://github.com/MiaAI-Lab/DeepSeek-V4-Flash-DSpark-2x-DGX-Spark>
- 模型权重（HF）：`deepseek-ai/DeepSeek-V4-Flash-Vision-Exp`，commit `86f746b36186f0e567729a5c06a8c918caba82a9`
