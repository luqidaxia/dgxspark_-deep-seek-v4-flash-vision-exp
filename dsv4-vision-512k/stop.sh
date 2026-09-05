#!/usr/bin/env bash
# Platform cluster wrapper: stop DeepSeek-V4-Flash-Vision-Exp
set -uo pipefail
cd "$(dirname "$0")"
exec ./stop-deepseek-v4-flash-dspark.sh "$@"
