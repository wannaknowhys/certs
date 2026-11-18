# certs

[English](README.md) | [简体中文](README.zh-CN.md)

Lightweight automated SSL certificate issuance (acme.sh DNS-01) and Cloudflare DDNS container, based on Alpine Linux with minimal dependencies.

## Key Highlights

- **Dependency Reduction**: Stripped unnecessary `bash`, `gawk`, and `socat`. Runs purely on BusyBox ash and POSIX shell.
- **Pre-bundled acme.sh**: `acme.sh` is packaged during image build time, eliminating runtime `curl | sh` internet downloads.
- **Rolling Update Strategy**: Daily automated GitHub Actions build monitoring Alpine upstream security patches (`curl`, `openssl`, `ca-certificates`).
- **Read-Only Compatible**: Operates cleanly with `read_only: true` on rootfs.
