#!/bin/sh
# uni-api 安装脚本
# 支持: Alpine (OpenRC) / Debian·Ubuntu·CentOS (systemd)
# 用法: sh install.sh（需要 root 权限）
set -eu

REPO="clerzg/uni-api"
ASSET="uni-api-linux-x86_64-musl"
BASE_URL="https://github.com/${REPO}/releases/latest/download"
BIN_NAME="uni-api"

INSTALL_BIN="${INSTALL_BIN:-/usr/local/bin/${BIN_NAME}}"
CONF_DIR="${CONF_DIR:-/etc/uni-api}"
CONF_FILE="${CONF_DIR}/api.yaml"
PORT="${PORT:-8000}"

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m  %s\n' "$*"; }
die()  { printf '\033[1;31mxx\033[0m  %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "需要 root 权限，请以 root 运行: sh install.sh"

case "$(uname -m)" in
  x86_64|amd64) ;;
  *) die "仅支持 x86_64 架构，当前为: $(uname -m)" ;;
esac

if command -v curl >/dev/null 2>&1; then
  fetch() { curl -fsSL --connect-timeout 15 -o "$2" "$1"; }
elif command -v wget >/dev/null 2>&1; then
  fetch() { wget -qO "$2" "$1"; }
else
  die "需要 curl 或 wget"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

log "下载 ${ASSET} ..."
fetch "${BASE_URL}/${ASSET}" "${TMP}/${ASSET}" || die "下载失败，请检查网络"

log "校验 sha256 ..."
if fetch "${BASE_URL}/${ASSET}.sha256" "${TMP}/${ASSET}.sha256" 2>/dev/null; then
  ( cd "$TMP" && sha256sum -c "${ASSET}.sha256" >/dev/null 2>&1 ) \
    || die "sha256 校验失败，文件可能损坏"
  log "校验通过"
else
  warn "校验文件不可用，跳过 sha256 校验"
fi

log "安装二进制 -> ${INSTALL_BIN}"
mkdir -p "$(dirname "$INSTALL_BIN")"
cp "${TMP}/${ASSET}" "${INSTALL_BIN}"
chmod 755 "${INSTALL_BIN}"

# 生成随机客户端密钥（sk- + 32 位十六进制）。
# 优先用 OpenSSL；无 OpenSSL 时退化为 /dev/urandom + od。
gen_client_key() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 16
  elif [ -r /dev/urandom ]; then
    od -vN 16 -An -tx1 /dev/urandom 2>/dev/null | tr -d ' \n'
  else
    # 最后兜底：时间戳 + 进程号 + 随机数（够用但不算强随机）
    echo "$(date +%s)$$$RANDOM" | md5sum 2>/dev/null | cut -c1-32 \
      || echo "$(date +%s)$$$RANDOM"
  fi
}
CLIENT_KEY="sk-$(gen_client_key)"
if [ -z "$CLIENT_KEY" ] || [ "$CLIENT_KEY" = "sk-" ]; then
  die "无法生成客户端密钥"
fi

mkdir -p "$CONF_DIR"
if [ ! -f "$CONF_FILE" ]; then
  log "生成配置模板 -> ${CONF_FILE}"
  cat > "$CONF_FILE" <<YAML
# uni-api 配置示例
# providers: 上游服务（可写多个，自动负载均衡）
# api_keys:  本服务对外发放的密钥，客户端用它调用

providers:
  - provider: openai
    base_url: https://api.xx.cn/v1
    api: sk-REPLACE-WITH-YOUR-UPSTREAM-KEY
#    model:
#      - deepseek-v4.1-flash
#    不提供model从上游自动发现

api_keys:
  - api: ${CLIENT_KEY}
YAML
  chmod 600 "$CONF_FILE"
  warn "请编辑 ${CONF_FILE} 把 providers[].api 换成真实上游密钥"
  warn "已自动生成客户端密钥（安装结束后会打印）"
else
  log "配置已存在，保持不变: ${CONF_FILE}"
  # 从已有配置读出客户端密钥，便于结束时展示
  EXISTING=$(grep -m1 -A0 '^\s*-\s*api:' "$CONF_FILE" 2>/dev/null \
    | sed -n 's/.*api: *//p' | head -1)
  [ -n "$EXISTING" ] && CLIENT_KEY="$EXISTING"
fi

# ---------------- 开机自启 ----------------
if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
  log "检测到 systemd，安装 unit"
  cat > /etc/systemd/system/uni-api.service <<EOF
[Unit]
Description=uni-api (LLM API gateway)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${CONF_DIR}
ExecStart=${INSTALL_BIN}
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable uni-api >/dev/null 2>&1 || true
  systemctl restart uni-api || warn "服务启动失败，请查看: journalctl -u uni-api -n 50"
  log "开机自启已启用（systemd）"

elif command -v rc-update >/dev/null 2>&1; then
  log "检测到 OpenRC（Alpine），安装 init 脚本"
  cat > /etc/init.d/uni-api <<EOF
#!/sbin/openrc-run
name="uni-api"
description="uni-api (LLM API gateway)"
command="${INSTALL_BIN}"
command_background=true
directory="${CONF_DIR}"
pidfile="/run/\${RC_SVCNAME}.pid"
output_log="/var/log/uni-api.log"
error_log="/var/log/uni-api.err"

depend() {
    need net
    after firewall
}
EOF
  chmod +x /etc/init.d/uni-api
  rc-update add uni-api default >/dev/null 2>&1 || true
  rc-service uni-api restart || warn "服务启动失败，请查看: /var/log/uni-api.err"
  log "开机自启已启用（OpenRC）"

else
  warn "未检测到 systemd / OpenRC，无法自动配置开机启动"
  warn "手动运行: cd ${CONF_DIR} && ${INSTALL_BIN}"
fi

cat <<EOF

$(printf '\033[1;32m✓ 安装完成\033[0m')

  二进制     ${INSTALL_BIN}
  配置       ${CONF_FILE}
  端口       ${PORT}
  客户端密钥 ${CLIENT_KEY}
  日志       /var/log/uni-api.log (OpenRC) 或 journalctl -u uni-api (systemd)

  下一步：
    1. 编辑 ${CONF_FILE}，把 providers[].api 换成真实上游密钥
    2. 重启服务使配置生效
    3. 客户端调用 http://<本机IP>:${PORT}/v1，API Key 用上面的客户端密钥
EOF
