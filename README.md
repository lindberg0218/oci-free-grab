# oci-free-grab

Oracle Cloud 免费机自动抢注（新加坡 ap-singapore-1）。

每 10 分钟由 GitHub Actions 触发，单次跑 8 分钟：
1. 先试 `VM.Standard.A1.Flex` 2 OCPU / 12GB（2026-06 起 Always Free 额度，旧文里写的 4/24 已失效）
2. 没货再试 `VM.Standard.E2.1.Micro` 1 OCPU / 1GB
3. 任一建成即退出，日志里打印实例 OCID、公网 IP

## Secrets（Settings → Secrets and variables → Actions）

| 名称 | 值 |
|---|---|
| `OCI_TENANCY_OCID` | 租户 OCID |
| `OCI_USER_OCID` | 用户 OCID |
| `OCI_FINGERPRINT` | API 密钥指纹 |
| `OCI_PRIVATE_KEY` | API 私钥 PEM 全文 |
| `OCI_SUBNET_ID` | 公共子网 OCID |
| `SSH_PUBKEY` | 登录公钥全文 |

## 停手

抢到后进 Settings → Actions → 停用本 workflow，或删除 `schedule` 段。

注意：免费额度上限为 A1 4C24G 或 E2 两台；抢到后不要再手动重复建，会超免费额度。
