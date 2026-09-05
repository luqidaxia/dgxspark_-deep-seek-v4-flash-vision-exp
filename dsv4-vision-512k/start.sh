#!/usr/bin/env bash
# Platform cluster wrapper: DeepSeek-V4-Flash-Vision-Exp (official DSpark recipe)
# Called by Lexdata-AI-Platform with HEAD_IP/WORKER_IP/WORKER_SSH_HOST/WORKER_SSH_PW env.
set -uo pipefail
cd "$(dirname "$0")"
exec ./start-deepseek-v4-flash-dspark.sh "$@"
