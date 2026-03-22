# 输出示例

## 1. 全部正常

```
Aether 环境诊断
===============
诊断时间: 2026-03-08 12:00:00
配置来源: 项目级 (./.aether/config.yaml)

[✓] aether CLI
    版本: 0.7.0
    路径: ~/.aether/aether

[✓] 配置验证
    配置地址: http://192.168.1.70:4646
    集群 Server: 192.168.1.70, 192.168.1.71, 192.168.1.72
    状态: 配置有效

[✓] 集群连接
    Nomad: v1.11.2
    Consul: v1.22.3

[✓] SSH 连接
    所有节点: 11/11 正常

状态: ✓ 健康
缓存已更新
```

## 2. CLI 未安装

```
Aether 环境诊断
===============

[✗] aether CLI
    状态: 未安装

    是否自动安装？ [Y/n]
    选项:
      1. 自动安装（推荐）
      2. 从源码构建
      3. 手动安装命令
```

## 3. 配置地址无效

```
Aether 环境诊断
===============

[✓] aether CLI
    版本: 0.7.0

[!] 配置验证
    配置地址: http://192.168.1.100:4646
    集群 Server 列表:
      - 192.168.1.70:4646
      - 192.168.1.71:4646 (leader)
      - 192.168.1.72:4646

    ⚠ 配置的地址不在 Server 列表中

    建议修改为:
      - http://192.168.1.70:4646
      - http://192.168.1.71:4646

    是否自动修复？ [Y/n]
```

## 4. 部分 SSH 失败

```
Aether 环境诊断
===============

[✓] aether CLI
[✓] 配置验证
[✓] 集群连接

[✗] SSH 连接测试
    Server: 3/3 正常
    Client: 6/8 正常

    失败:
      - light-2 (192.168.1.91): Connection timed out
      - light-4 (192.168.1.93): Permission denied

状态: ⚠ 降级（部分 SSH 功能受限）
```

## 5. CI 配置问题

```
Aether 环境诊断
===============

[✓] aether CLI
[✓] 配置验证
[✓] 集群连接
[✓] SSH 连接

[!] CI/CD 配置
    平台: Forgejo
    Workflow: .forgejo/workflows/deploy.yaml

    问题:
      1. [WARNING] secrets.REGISTRY_TOKEN → secrets.FORGEJO_TOKEN
      2. [WARNING] Nomad 地址硬编码

    需配置 Secrets:
      - NOMAD_ADDR
      - NOMAD_TOKEN

状态: ⚠ 环境可用，CI 可优化
```

## 6. 严重问题

```
Aether 环境诊断
===============

[✗] aether CLI
    错误: command not found

[?] 配置文件 - 跳过
[?] 集群连接 - 跳过

状态: ✗ 环境未就绪

建议:
1. 安装 aether CLI: /aether:doctor --fix
2. 配置集群: /aether:setup
3. 配置 SSH: ssh-keygen -t ed25519
```
