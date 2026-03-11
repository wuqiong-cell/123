#!/usr/bin/env bash
set -euo pipefail

INSTALLER="/opt/codex/skills/.system/skill-installer/scripts/install-skill-from-github.py"
SKILLS_ROOT="${CODEX_HOME:-$HOME/.codex}/skills"
SKILL_DEST="$SKILLS_ROOT/open-claw"

# 借鉴社区常见方案：镜像 URL + 内网制品 URL + 本地目录/zip 离线安装
MIRROR_ZIP_URLS=(
  "https://ghproxy.net/https://github.com/openai/skills/archive/refs/heads/main.zip"
  "https://ghproxy.com/https://github.com/openai/skills/archive/refs/heads/main.zip"
  "https://download.fastgit.org/openai/skills/archive/refs/heads/main.zip"
)

log() { printf '[open-claw] %s\n' "$*"; }

usage() {
  cat <<'USAGE'
用法:
  ./install_open_claw.sh
  ./install_open_claw.sh --local-dir /path/to/open-claw
  ./install_open_claw.sh --local-zip /path/to/skills-main.zip
  ./install_open_claw.sh --artifact-url https://your-artifact/skills-main.zip

说明:
  1) 默认先走官方安装器。
  2) 官方失败后，会尝试社区镜像下载 zip 并提取 open-claw。
  3) 仍失败时，可使用本地目录/zip 或内网制品 URL 离线安装。
USAGE
}

check_host() {
  local url="$1"
  python - "$url" <<'PY'
import sys, urllib.request
u = sys.argv[1]
try:
    with urllib.request.urlopen(u, timeout=12) as r:
        print(f"OK {r.status}")
except Exception as e:
    print(f"ERR {e}")
PY
}

install_from_github() {
  local err_file
  err_file="$(mktemp)"
  if python "$INSTALLER" --repo openai/skills --path skills/.curated/open-claw 2>"$err_file"; then
    rm -f "$err_file"
    return 0
  fi
  log "官方安装报错摘要: $(tail -n 1 "$err_file")"
  rm -f "$err_file"
  return 1
}

extract_skill_from_repo_tree() {
  local repo_root="$1"
  local src="$repo_root/skills/.curated/open-claw"
  if [[ ! -f "$src/SKILL.md" ]]; then
    return 1
  fi
  mkdir -p "$SKILLS_ROOT"
  if [[ -e "$SKILL_DEST" ]]; then
    log "目标已存在，跳过: $SKILL_DEST"
    return 0
  fi
  cp -R "$src" "$SKILL_DEST"
}

install_from_local_dir() {
  local src_dir="$1"
  if [[ ! -f "$src_dir/SKILL.md" ]]; then
    log "本地目录缺少 SKILL.md: $src_dir"
    return 2
  fi
  mkdir -p "$SKILLS_ROOT"
  if [[ -e "$SKILL_DEST" ]]; then
    log "目标已存在，跳过: $SKILL_DEST"
    return 0
  fi
  cp -R "$src_dir" "$SKILL_DEST"
}

install_from_local_zip() {
  local zip_path="$1"
  local tmp
  tmp="$(mktemp -d)"
  unzip -q "$zip_path" -d "$tmp"
  local root
  root="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  if [[ -z "$root" ]]; then
    log "zip 解压失败或内容为空: $zip_path"
    rm -rf "$tmp"
    return 2
  fi
  if extract_skill_from_repo_tree "$root"; then
    rm -rf "$tmp"
    return 0
  fi
  rm -rf "$tmp"
  log "zip 中未找到 skills/.curated/open-claw/SKILL.md"
  return 2
}

install_from_artifact_url() {
  local url="$1"
  local tmp_zip
  tmp_zip="$(mktemp --suffix=.zip)"
  if ! curl -fsSL "$url" -o "$tmp_zip"; then
    rm -f "$tmp_zip"
    return 1
  fi
  install_from_local_zip "$tmp_zip"
  local rc=$?
  rm -f "$tmp_zip"
  return $rc
}

install_from_mirror_urls() {
  local u
  for u in "${MIRROR_ZIP_URLS[@]}"; do
    log "尝试镜像下载: $u"
    if install_from_artifact_url "$u"; then
      log "通过镜像安装成功。"
      return 0
    fi
  done
  return 1
}

main() {
  local local_dir=""
  local local_zip=""
  local artifact_url=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --local-dir)
        local_dir="${2:-}"; shift 2 ;;
      --local-zip)
        local_zip="${2:-}"; shift 2 ;;
      --artifact-url)
        artifact_url="${2:-}"; shift 2 ;;
      -h|--help)
        usage; return 0 ;;
      *)
        log "未知参数: $1"; usage; return 2 ;;
    esac
  done

  if [[ -n "$local_dir" ]]; then
    log "使用本地目录离线安装: $local_dir"
    install_from_local_dir "$local_dir"
    log "离线安装完成。请重启 Codex。"
    return 0
  fi

  if [[ -n "$local_zip" ]]; then
    log "使用本地 zip 离线安装: $local_zip"
    install_from_local_zip "$local_zip"
    log "离线安装完成。请重启 Codex。"
    return 0
  fi

  if [[ -n "$artifact_url" ]]; then
    log "使用制品 URL 安装: $artifact_url"
    install_from_artifact_url "$artifact_url"
    log "安装完成。请重启 Codex。"
    return 0
  fi

  log "尝试官方安装 open-claw..."
  if install_from_github; then
    log "官方安装成功。请重启 Codex。"
    return 0
  fi

  log "官方安装失败，尝试社区镜像方案..."
  if install_from_mirror_urls; then
    log "安装成功。请重启 Codex。"
    return 0
  fi

  log "镜像也失败，开始诊断网络连通性..."
  log "github.com: $(check_host https://github.com)"
  log "api.github.com: $(check_host https://api.github.com)"
  log "codeload.github.com: $(check_host https://codeload.github.com)"

  cat <<'MSG'
仍无法在线安装。建议按优先级排查：
1) 放通 github.com / api.github.com / codeload.github.com 的 CONNECT。
2) 将 openai/skills 仓库 zip 上传到内网制品库后执行：
   ./install_open_claw.sh --artifact-url https://your-artifact/skills-main.zip
3) 手工下载后离线安装：
   ./install_open_claw.sh --local-zip /path/to/skills-main.zip
   或
   ./install_open_claw.sh --local-dir /path/to/open-claw
MSG
  return 1
}

main "$@"
