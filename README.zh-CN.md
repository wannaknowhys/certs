# certs

[English](README.md) | [简体中文](README.zh-CN.md)

轻量级自动化 SSL 证书申请（acme.sh DNS-01）与 Cloudflare DDNS 容器，基于 Alpine Linux 构建，极简依赖。

## 核心特性

- **极致精简**：完全剔除不必要的 `bash`、`gawk` 与 `socat`，纯粹依托 BusyBox ash 与 POSIX 标准 shell 运行。
- **构建期固化 acme.sh**：在 Dockerfile 构建阶段直接将官方 `acme.sh` 固化进镜像，启动时不再从公网动态 `curl | sh` 安装，具备完全的离线与不可变能力。
- **滚动更新策略**：由 GitHub Actions 每日自动探测 Alpine 上游关键依赖（`curl`、`openssl`、`ca-certificates`）的版本变动，有更新时自动发布。
- **只读加固兼容**：完美支持 `read_only: true`（根只读 + tmpfs 临时目录）。
