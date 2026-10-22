# uni-api musl build

本仓库**只存放一个 GitHub Actions workflow，没有源码**。

工作流从上游 [`yym68686/uni-api`](https://github.com/yym68686/uni-api) 的 **latest release tag** 拉取源码，编译成静态链接的 **musl** 二进制（x86_64 Linux），发布到本仓库的 Releases。

> 版本号 = 上游 tag，代码 = 上游同 tag 源码，严格对应。

编译产物是 uni-api 的**核心网关**（单个二进制，无 Web 前端、无外部依赖）。

- 大小：约 11 MB
- 内存：实测 RSS **约 5 MB**
- 兼容：Alpine / Debian / Ubuntu 等任意 x86_64 Linux（静态链接，无 .so 依赖）

---

## 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/clerzg/uni-api/main/install.sh | sh
```

脚本会自动完成：

1. 下载最新二进制 → 安装为 `/usr/local/bin/uni-api`
2. sha256 校验
3. 生成配置模板 `/etc/uni-api/api.yaml`
4. 配置**开机自启**（systemd 或 OpenRC 自动识别）
5. 启动服务并做健康检查

安装后编辑配置、重启服务即可使用。

## 手动安装

```bash
# 1. 下载（固定地址，永远指向最新版）
curl -L -o uni-api \
  https://github.com/clerzg/uni-api/releases/latest/download/uni-api-linux-x86_64-musl
chmod +x uni-api

# 2. 校验（可选）
curl -L -O https://github.com/clerzg/uni-api/releases/latest/download/uni-api-linux-x86_64-musl.sha256
sha256sum -c uni-api-linux-x86_64-musl.sha256

# 3. 准备配置（必须与二进制同目录，文件名固定为 api.yaml）
cat > api.yaml <<'EOF'
providers:
  - provider: custom
    base_url: https://api.doulor.cn/v1
    api: sk-你的上游密钥
    model:
      - workbuddy-auto

api_keys:
  - api: sk-给客户端用的密钥
EOF

# 4. 运行（默认监听 0.0.0.0:8000）
./uni-api
```

---

## 配置说明

配置文件默认路径 `/etc/uni-api/api.yaml`（一键安装）或二进制同目录的 `api.yaml`（手动安装）。

| 字段 | 作用 |
|---|---|
| `providers` | 上游服务列表，可写多个，自动负载均衡 / 故障切换 |
| `providers[].base_url` | 上游 OpenAI 兼容端点 |
| `providers[].api` | 上游密钥 |
| `providers[].model` | 该上游支持的模型列表 |
| `api_keys` | 本服务对外发放的密钥，客户端用这个调用 |

### 上游示例

直连服务商：

```yaml
providers:
  - provider: custom
    base_url: https://api.doulor.cn/v1
    api: sk-xxx
    model:
      - workbuddy-auto
```

走 Cloudflare AI Gateway（自带路由与缓存）：

```yaml
providers:
  - provider: custom
    base_url: https://gateway.ai.cloudflare.com/v1/<account_id>/<gateway_id>/compat
    api: <cf-gateway-token>
    model:
      - dynamic/main
```

多个上游会按权重轮询，某个失败自动切换。

---

## 服务管理

### systemd（Debian / Ubuntu / CentOS）

```bash
systemctl status uni-api
systemctl restart uni-api
journalctl -u uni-api -f          # 实时日志
systemctl disable uni-api         # 取消开机自启
```

### OpenRC（Alpine）

```bash
rc-service uni-api status
rc-service uni-api restart
tail -f /var/log/uni-api.log      # 实时日志
rc-update del uni-api default     # 取消开机自启
```

---

## 客户端调用

服务启动后，任何 OpenAI 兼容客户端都能连：

```bash
curl http://127.0.0.1:8000/v1/chat/completions \
  -H "Authorization: Bearer sk-给客户端用的密钥" \
  -H "Content-Type: application/json" \
  -d '{"model":"workbuddy-auto","messages":[{"role":"user","content":"hi"}]}'
```

Base URL 填 `http://<主机>:8000/v1`，API Key 填 `api_keys` 里那个。

---

## 更新

```bash
# 重新跑一遍安装脚本即可（配置会保留）
curl -fsSL https://raw.githubusercontent.com/clerzg/uni-api/main/install.sh | sh
```

或手动替换二进制后重启服务。下载地址固定，不需要改任何客户端配置。

---

## 卸载

```bash
# systemd
systemctl disable --now uni-api 2>/dev/null
rm -f /etc/systemd/system/uni-api.service
systemctl daemon-reload

# OpenRC
rc-service uni-api stop 2>/dev/null
rc-update del uni-api default 2>/dev/null
rm -f /etc/init.d/uni-api

rm -f /usr/local/bin/uni-api
rm -rf /etc/uni-api        # 如需保留配置可跳过
```

---

## 构建

仓库 → **Actions** → `Build uni-api musl binary (amd64)` → **Run workflow**。

工作流会：

1. 查询上游 latest release tag（如 `v1.7.276`）
2. checkout 上游该 tag 的源码
3. 在 `rust:1.84-alpine` 容器内编译（原生 musl）
4. 发布到 Releases，资产名固定不带版本号
5. 同时保留一份 Actions artifact 备份

Release 资产：

- `uni-api-linux-x86_64-musl`
- `uni-api-linux-x86_64-musl.sha256`
