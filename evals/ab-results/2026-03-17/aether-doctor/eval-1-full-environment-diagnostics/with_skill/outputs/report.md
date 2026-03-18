Aether 环境诊断
===============
诊断时间: 2026-03-18 (首次使用诊断)
配置来源: 全局 (~/.aether/config.yaml)

---

[PASS] aether CLI
    版本: 0.7.2
    路径: /usr/local/bin/aether
    [WARNING] 版本兼容性: Plugin v0.9.1 推荐 CLI >= 0.8.0，当前 0.7.2 可能缺少部分功能
    修复建议: 升级 CLI 到 0.8.0+
      方案 A (自动): 运行 /aether:doctor --fix
      方案 B (手动): 从 https://forgejo.10cg.pub/10CG/Aether/releases 下载 aether-linux-amd64

[PASS] 配置文件
    位置: ~/.aether/config.yaml
    内容:
      nomad_addr:    http://192.168.69.70:4646
      consul_addr:   http://192.168.69.70:8500
      registry:      forgejo.10cg.pub
      registry_url:  forgejo.10cg.pub
    [WARNING] 缺少 nomad_token 配置
    修复建议: 在 ~/.aether/config.yaml 中添加:
      cluster:
        nomad_token: <your-nomad-token>
    或设置环境变量:
      export NOMAD_TOKEN="<your-nomad-token>"

[PASS] 配置验证
    配置地址: http://192.168.69.70:4646 (infra-server-1)
    集群 Raft Server 列表:
      - 192.168.69.70:4647 (infra-server-1, follower)
      - 192.168.69.71:4647 (当前 leader)
      - 192.168.69.72:4647 (follower)
    状态: 配置有效 - 地址在 Server 列表中

[PASS] 集群连接 - Nomad
    版本: 1.11.2
    构建日期: 2026-02-11
    节点名称: infra-server-1.global
    Leader: 192.168.69.71:4647
    Client 节点: 8 个 (全部 ready)
      heavy_workload (3):
        - heavy-1  192.168.69.80  ready
        - heavy-2  192.168.69.81  ready
        - heavy-3  192.168.69.82  ready
      light_exec (5):
        - light-1  192.168.69.90  ready
        - light-2  192.168.69.91  ready
        - light-3  192.168.69.92  ready
        - light-4  192.168.69.93  ready
        - light-5  192.168.69.94  ready

[PASS] 集群连接 - Consul
    版本: 1.22.3
    数据中心: dc1
    节点名称: infra-server-1
    Leader: 192.168.69.70:8300

[PASS] SSH 密钥
    密钥: ~/.ssh/id_ed25519 (权限: 600)
    目录: ~/.ssh (权限: 700)
    SSH Config: 已配置 heavy-*/light-* 规则
      User: root
      IdentityFile: ~/.ssh/id_ed25519
      StrictHostKeyChecking: no

[PASS] SSH 连接测试 - heavy-1
    目标: root@192.168.69.80
    主机名: heavy-1
    状态: 连接成功

[PASS] CI/CD 配置
    平台: Forgejo (在主仓库 /home/dev/Aether/.forgejo/workflows/)
    Workflow 文件:
      - ci.yml (CI: Go test + lint)
      - cli-release.yml (Release: 多平台构建)
    Secrets 引用: GITHUB_TOKEN (用于 GitHub mirror 推送)
    硬编码 IP: 无
    状态: CI 配置正常

---

诊断总结
========

状态: PASS (可用，有 2 个警告)

| 诊断项 | 状态 | 备注 |
|--------|------|------|
| aether CLI | PASS (WARNING) | v0.7.2 已安装，建议升级到 0.8.0+ |
| 配置文件 | PASS (WARNING) | 全局配置存在，缺少 nomad_token |
| 配置验证 | PASS | 地址有效，在 Raft Server 列表中 |
| Nomad 连接 | PASS | v1.11.2, 8 Client 节点全部 ready |
| Consul 连接 | PASS | v1.22.3, dc1 |
| SSH 密钥 | PASS | ed25519, 权限正确 |
| SSH 连接 (heavy-1) | PASS | 连接成功 |
| CI/CD 配置 | PASS | Forgejo CI + Release 配置就绪 |

---

修复建议
========

### 1. [WARNING] CLI 版本偏低

当前 CLI 版本 0.7.2，Plugin v0.9.1 推荐 CLI >= 0.8.0。虽然基础功能可用，但新版 Plugin 的部分功能可能需要更高版本的 CLI 支持。

**修复方法**:
```bash
# 方案 A: 自动下载安装
RELEASE_API="https://forgejo.10cg.pub/api/v1/repos/10CG/Aether/releases/latest"
DOWNLOAD_URL=$(curl -s "$RELEASE_API" | jq -r '.assets[] | select(.name == "aether-linux-amd64") | .browser_download_url' | head -n1)
sudo curl -sL "$DOWNLOAD_URL" -o /usr/local/bin/aether
sudo chmod +x /usr/local/bin/aether
aether version

# 方案 B: 从源码构建
git clone https://forgejo.10cg.pub/10CG/aether-cli.git /tmp/aether-cli
cd /tmp/aether-cli
go build -ldflags="-s -w -X main.Version=$(cat VERSION)" -o aether .
sudo mv aether /usr/local/bin/aether
rm -rf /tmp/aether-cli
```

注意: 如果 Forgejo 在 Cloudflare Access 后面，需要先配置 CF Token:
```bash
export CF_ACCESS_TOKEN="your-token-here"
```

### 2. [WARNING] 缺少 Nomad Token

配置文件中没有 `nomad_token`，部分需要认证的 Nomad API 操作（如提交 Job、部署等）可能失败。

**修复方法**:
```bash
# 编辑全局配置
cat >> ~/.aether/config.yaml << 'EOF'
  nomad_token: <your-nomad-token>
EOF

# 或设置环境变量（添加到 ~/.bashrc）
echo 'export NOMAD_TOKEN="<your-nomad-token>"' >> ~/.bashrc
source ~/.bashrc
```

---

环境信息
========

- 操作系统: Linux x86_64
- 用户: dev
- 主目录: /home/dev
- Plugin 版本: 0.9.1
- CLI 版本: 0.7.2
- CLI 路径: /usr/local/bin/aether
- Nomad: 1.11.2 (3 servers, 8 clients)
- Consul: 1.22.3 (dc1)
- SSH 密钥: ed25519
