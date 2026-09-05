# DeepSeek-V4-Flash-Vision-512k 双机 TP=2 部署方案（DSpark 官方配方）

> 更新时间：2026-09-05
> 部署目录：`/opt/lexdata-ai/cluster-scripts/dsv4-vision-512k/`
> 上游官方仓库：[MiaAI-Lab/DeepSeek-V4-Flash-DSpark-2x-DGX-Spark](https://github.com/MiaAI-Lab/DeepSeek-V4-Flash-DSpark-2x-DGX-Spark)（本目录为其完整副本 + 本地适配）
> 关联实例：现网 `dsv4-vision-exp-new`（1M 上下文，端口 4111，`nvfp4_ds_mla` KV）——本实例为其 **512k 共存变体**（端口 4112，`fp8` KV）

---

## 1. 部署目标

在 2× DGX Spark（GB10, Grace-Blackwell）上以 **TP=2 双机集群** 方式部署
**DeepSeek-V4-Flash-Vision-512k**（官方 vision 版本，512k 上下文 profile），并注册到
Lexdata-AI-Platform 模型管理平台（http://192.0.2.10:8889/#model-manage），由平台统一管理启停与日志查看。

关键特性：

- 官方 **vision hotfix** 支持（多模态，`LIMIT_MM_PER_PROMPT=image=8`）
- `MTP_NUM_TOKENS=6` 多 token 预测、`DEFAULT_THINKING=low` 低思考档
- `MAX_MODEL_LEN=524288`（512k 上下文），`fp8` KV cache dtype（`--kv-cache-dtype fp8`）
- 3 个 opt-in hotfix 开启：`ROPE_SWA_FIX` / `DSPARK_SWA_PREFIX` / `DSML_RECOVERY`
- 与 1M 实例同机共存：`VLLM_PORT=4112`、`MASTER_PORT=25002` 错开

## 2. 环境清单

| 项 | 值 |
|---|---|
| head 节点 | 10.10.12.11（对外 192.0.2.10） |
| worker 节点 | 10.10.12.21（spark-cefb） |
| 模型镜像 | `ghcr.nju.edu.cn/anemll/dspark-vllm-gx10:0.1.1`（NJU 镜像，digest 与官方一致） |
| 模型权重 | `/data/models/deepseek-ai/DeepSeek-V4-Flash-Vision-Exp`（约 157G，双机已同步） |
| HF commit pin | `86f746b36186f0e567729a5c06a8c918caba82a9` |
| vLLM 端口 | 4112（head 对外 API：`http://192.0.2.10:4112/v1`） |
| MASTER_PORT | 25002（NCCL rendezvous，与 1M 实例 25001 错开） |
| served 模型名 | `deepseek-v4-flash-vision-512k` |
| head→worker SSH | 免密已配置（官方 start 脚本硬性要求 `ssh -o BatchMode=yes`） |

## 3. 方案核心：官方配方 + 本地适配点

### 3.1 镜像

官方仓库 pin 的 `ghcr.io/anemll/dspark-vllm-gx10:0.1.1` 在本机/worker 均可用；
镜像名改写为 NJU 镜像 `ghcr.nju.edu.cn/anemll/...`（因直连 ghcr.io 受限），digest 与官方一致。

### 3.2 模型加载路径（扁平目录 → HF hub 结构）

官方 compose 从 HF hub 缓存读取权重。本机权重为扁平目录，采用 **symlink 适配**：

```
/root/.cache/huggingface/hub/models--deepseek-ai--DeepSeek-V4-Flash-Vision-Exp/
├── refs/main          → 86f746b36186f0e567729a5c06a8c918caba82a9
└── snapshots/<commit> → /data/models/deepseek-ai/DeepSeek-V4-Flash-Vision-Exp
```

同时在 `docker-compose.dspark.yml` 增加挂载（让扁平目录权重进容器）并指定 fp8 KV：

```yaml
volumes:
  - ${HF_CACHE:-${HOME}/.cache/huggingface}:/cache/huggingface
  - /data/models:/data/models:ro      # ← 本地新增
# 启动命令内: --kv-cache-dtype fp8    # ← 本地改为 fp8（1M 实例为 nvfp4_ds_mla）
```

### 3.3 平台集成（包装脚本 + 注册）

- 平台通过 `start.sh / stop.sh / status.sh / logs.sh`（与模型实例同目录）驱动集群启停与日志；
- `start.sh` 透传调用官方 `start-deepseek-v4-flash-dspark.sh`（阻塞式，含 boot warmup）；
- `logs.sh` 按平台解析约定输出 head/worker 两节点容器日志（容器名 `dsv4-vision-512k-vllm-dspark-1`）；
- `PROJECT_NAME=dsv4-vision-512k` 与 1M 实例 `dsv4-vision-exp-new` 错开，容器名不冲突。

## 4. 关键文件清单（本目录 = 官方副本 + 本地适配）

### 4.1 官方配方文件（从 GitHub 下载）

| 文件 | 说明 |
|---|---|
| `start-deepseek-v4-flash-dspark.sh` | 官方启动脚本（worker 同步、校验、双机拉起、boot warmup） |
| `stop-deepseek-v4-flash-dspark.sh` / `status-...sh` | 官方停止/状态脚本 |
| `validate-dspark-config.sh` | 官方配置校验脚本 |
| `docker-compose.dspark.yml` | 官方双机 compose（**本地已修改**，见 4.2） |
| `.env.dspark.example` | 官方环境变量模板 |
| `patches/` | 全部 hotfix 脚本，含 vision 关键件：`hotfix-dsv4-vision-exp.py`、`vision_exp/` |
| `recipe/`、`scripts/`、`docs/`、`tests/`、`lmcache/`、`vllm_patch_gb10/` | 官方配套脚本/文档/测试 |

### 4.2 本地修改/新增文件（本次部署的关键产物）

| 文件 | 类型 | 说明 |
|---|---|---|
| `docker-compose.dspark.yml` | **修改** | `/data/models:/data/models:ro` 挂载 + `--kv-cache-dtype fp8` |
| `.env.dspark` | **新增** | 本地生产配置（被 `.gitignore` 忽略、不提交）：端口 4112、MASTER_PORT 25002、commit pin、RoCE 网卡、3 个 hotfix =1、`PROJECT_NAME` / `SERVED_MODEL_NAME` 等 |
| `start.sh` / `stop.sh` / `status.sh` | **新增** | 平台集群启停/状态包装 → 官方脚本 |
| `logs.sh` | **新增** | 平台日志脚本：head + worker 双节点 `docker logs --tail` |
| `DEPLOY-PLAN-VISION-EXP.md` | **新增** | 本文档（部署方案总结） |

## 5. 校验结果（已完成，双端通过）

1. 官方 `validate-dspark-config.sh .env.dspark` ✅（vLLM 启动命令渲染正确）
2. head `docker compose -p dsv4-vision-512k --env-file .env.dspark config --quiet` ✅
3. worker 同参数校验 ✅
4. head→worker 免密 `ssh -o BatchMode=yes` ✅
5. 平台 `_parse_logs_script_container_names` 解析 `logs.sh` → head/worker 容器名 ✅

## 6. 平台注册信息

> 操作入口：模型管理页（`#model-manage`）→ **推理引擎管理**（`vLLM-dsv4flash`，镜像
> `ghcr.nju.edu.cn/anemll/dspark-vllm-gx10:0.1.1`）→ **模型实例管理**（添加模型）。

| 项 | 值 |
|---|---|
| 名称 | `deepseek-v4-flash-vision-512k` |
| engine | vLLM-dsv4flash（anemll 镜像） |
| 部署模式 | cluster（双机 TP=2） |
| 集群启动/停止脚本 | `/opt/lexdata-ai/cluster-scripts/dsv4-vision-512k/start.sh` / `stop.sh` |
| 端口 | 4112 |
| 健康检查 | `http://127.0.0.1:4112/health` |
| 访问地址 | `http://192.0.2.10:4112/v1` |
| tags | `vision,cluster,dsv4`；`vision_enabled=1` |

## 7. 部署结果（2026-09-05）

- ✅ 独立目录 / compose 工程 `dsv4-vision-512k` 就绪（与 1M 实例 `dsv4-vision-exp-new` 同机共存）
- ✅ 双机 TP=2 分布式建立，vLLM 加载 157G 权重成功
- ✅ `:4112/health` → healthy
- ✅ `MAX_MODEL_LEN=524288` 生效，KV cache dtype = `fp8`
- ✅ 日志查看：平台日志页 / `logs.sh`（head + worker 双节点聚合）

## 8. 部署过程踩坑记录（重要）

### 8.1 `LIMIT_MM_PER_PROMPT` 双引号被 env 文件解析吃掉 → vllm serve 直接退出

**现象**：head 容器日志 `vllm serve: error: argument --limit-mm-per-prompt: Value {image:8} cannot be converted to <function loads ...>`

**原因**：`.env.dspark` 写 `LIMIT_MM_PER_PROMPT={"image":8}`，docker compose 解析 env 文件时把双引号当值定界符移除，容器内实际拿到 `{image:8}`（非合法 JSON），vLLM CLI `json.loads` 失败。

**解决**：改用 compose 内置简写 `LIMIT_MM_PER_PROMPT=image=8`，容器 entrypoint 自动渲染为合法 JSON `{"image":8}`。

**经验**：docker compose `--env-file` 的值里**不能依赖双引号**传递 JSON；能用官方简写就用简写。

### 8.2 head 显存不足 → `Engine core initialization failed`（OOM）

**现象**：`ValueError: Free memory on device cuda:0 (...) is less than desired GPU memory utilization (0.835, ...)`

**原因**：head GPU 被其他进程占用（llama-server / qwen3 等），空闲显存 < `GPU_MEMORY_UTILIZATION_TEXT=0.835` 所需，vLLM 拒绝启动。

**解决**：释放 head GPU 显存；保持 `0.835` 不动或下调（需保证权重 + KV cache 装得下）。

**经验**：DGX Spark（GB10）`nvidia-smi` Memory-Usage 显示 **Not Supported**，总显存/空闲以 vLLM 启动日志为准（`119.63 GiB`）；head 上并行跑其他 GPU 服务需预留显存。

### 8.3 与 1M 实例同机共存

host 网络双实例必须错开端口：本实例 `VLLM_PORT=4112` / `MASTER_PORT=25002`（1M 实例 4111 / 25001），
且容器工程名 `PROJECT_NAME=dsv4-vision-512k` 不同，`logs.sh` 容器名指向各自容器。

> 注意：镜像拉取需直连 NJU 镜像站（本机 shell 无代理变量；docker daemon 配了全局代理，拉取需按需处理直连）。
