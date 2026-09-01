#!/bin/bash
# DeepSeek V4 Flash Vision-Exp 双机 TP=2 — 聚合查看两节点日志 (tail)
# Platform parses head container first, worker second (see _parse_logs_script_container_names).
set -u

WORKER_SSH_HOST="${WORKER_SSH_HOST:-10.10.12.21}"
SSH_USER="${WORKER_SSH_USER:-root}"
SSH_PW="${WORKER_SSH_PW:-}"
TAIL_N="${1:-60}"
CONTAINER="dsv4-vision-exp-vllm-dspark-1"

echo "############################################"
echo "### HEAD 节点日志 (本机 ${CONTAINER}, 最近 ${TAIL_N} 行)"
echo "############################################"
docker logs --tail "$TAIL_N" "$CONTAINER" 2>&1

echo ""
echo "############################################"
echo "### WORKER 节点日志 ($WORKER_SSH_HOST ${CONTAINER}, 最近 ${TAIL_N} 行)"
echo "############################################"
if [ -z "$SSH_PW" ]; then
    ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10 "${SSH_USER}@${WORKER_SSH_HOST}" \
        "docker logs --tail $TAIL_N $CONTAINER 2>&1" 2>&1
else
    sshpass -p "$SSH_PW" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "${SSH_USER}@${WORKER_SSH_HOST}" \
        "docker logs --tail $TAIL_N $CONTAINER 2>&1" 2>&1
fi
