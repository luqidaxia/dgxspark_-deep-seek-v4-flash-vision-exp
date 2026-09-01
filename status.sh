#!/usr/bin/env bash
# Platform cluster wrapper: status DeepSeek-V4-Flash-Vision-Exp
set -uo pipefail
cd "$(dirname "$0")"
exec ./status-deepseek-v4-flash-dspark.sh "$@"
