#!/usr/bin/env bash
# 抢 Oracle Always Free 的 A1.Flex (默认 2 OCPU / 12GB, ap-singapore-1)
# 每轮一次 launch, 失败原因原样打印; 成功则输出实例 OCID 与公网 IP。E2 兜底需 TRY_E2=1。
set -u
REGION="${OCI_REGION:-ap-singapore-1}"
COMPARTMENT_ID="${OCI_TENANCY_OCID:?缺 OCI_TENANCY_OCID}"
SUBNET_ID="${OCI_SUBNET_ID:?缺 OCI_SUBNET_ID}"
SSH_PUBKEY="${SSH_PUBKEY:?缺 SSH_PUBKEY}"
DEADLINE_SECS="${DEADLINE_SECS:-480}"
BOOT_GB="${BOOT_GB:-100}"
SLEEP_SECS="${SLEEP_SECS:-20}"
OCPUS="${OCPUS:-2}"
MEM_GB="${MEM_GB:-12}"
END=$(( $(date +%s) + DEADLINE_SECS ))

log(){ echo "[$(date -u '+%H:%M:%S')Z] $*"; }

AD=$(oci iam availability-domain list --compartment-id "$COMPARTMENT_ID" --region "$REGION" \
      --query 'data[0].name' --raw-output 2>/dev/null)
case "$AD" in ""|null) echo "AD 解析失败"; exit 1;; esac
log "AD=$AD"

img(){ # $1=过滤条件
  ERR=$(mktemp)
  OUT=$(oci compute image list --compartment-id "$COMPARTMENT_ID" --region "$REGION" \
    --operating-system "Canonical Ubuntu" --operating-system-version "22.04" \
    --query "data[?contains(\"display-name\", '22.04') && $1] | sort_by(@, &\"time-created\") | [-1].id" \
    --raw-output 2>"$ERR")
  [ -s "$ERR" ] && echo "[img] $(grep -v -i warning "$ERR" | head -2 | tr '\n' ' ')" >&2
  rm -f "$ERR"
  printf '%s' "$OUT"
}
IMG_ARM=$(img "contains(\"display-name\", 'aarch64')")
IMG_X86=$(img "!contains(\"display-name\", 'aarch64')")
log "IMG_ARM=$IMG_ARM"; log "IMG_X86=$IMG_X86"
[ -z "$IMG_ARM" ] && { log "ARM 镜像解析为空, 中止"; exit 1; }

try(){ # $1=shape $2=shape-config $3=image $4=name
  oci compute instance launch --no-retry --region "$REGION" --availability-domain "$AD" \
    --compartment-id "$COMPARTMENT_ID" --shape "$1" --shape-config "$2" \
    --subnet-id "$SUBNET_ID" --assign-public-ip true --display-name "$4" \
    --metadata "{\"ssh_authorized_keys\": \"$SSH_PUBKEY\"}" \
    --source-details "{\"sourceType\":\"image\",\"imageId\":\"$3\",\"bootVolumeSizeInGBs\":$BOOT_GB}" 2>&1 \
    | grep -v -e '^Warning:' -e 'append an extra line'
}

report(){ # $1=launch 输出
  IID=$(echo "$1" | grep -o 'ocid1\.instance\.[^"]*' | head -1)
  log "✅ 建成: $IID"
  PIP=""
  for _ in $(seq 1 10); do
    PIP=$(oci compute instance list-vnics --instance-id "$IID" --region "$REGION" \
          --query 'data[0]."public-ip"' --raw-output 2>/dev/null)
    [ -n "$PIP" ] && [ "$PIP" != "null" ] && break
    sleep 15
  done
  log "公网IP: $PIP"
  log "登录: ssh -i ~/.ssh/oracle_free ubuntu@$PIP"
  touch "${GITHUB_WORKSPACE:-.}/.grabbed"
}

reason(){ echo "$1" | tr '\n' ' ' | tr -s ' ' | cut -c1-200; }

N=0
while [ "$(date +%s)" -lt "$END" ]; do
  N=$((N+1))
  OUT=$(try VM.Standard.A1.Flex "{\"ocpus\":$OCPUS,\"memoryInGBs\":$MEM_GB}" "$IMG_ARM" a1-free)
  if echo "$OUT" | grep -q '"lifecycle-state"'; then
    log "第 $N 轮"; report "$OUT"; exit 0
  fi
  log "第 $N 轮 A1: $(reason "$OUT")"
  echo "$OUT" | grep -qi 'LimitExceeded' && { log "限额已满, 停手"; exit 2; }

  if [ "${TRY_E2:-0}" = "1" ] && [ -n "$IMG_X86" ] && [ "$IMG_X86" != "null" ]; then
    OUT=$(try VM.Standard.E2.1.Micro '{"ocpus":1,"memoryInGBs":1}' "$IMG_X86" e2-free)
    if echo "$OUT" | grep -q '"lifecycle-state"'; then report "$OUT"; exit 0; fi
    log "第 $N 轮 E2: $(reason "$OUT")"
  fi
  sleep $(( SLEEP_SECS + RANDOM % 10 ))
done
log "本轮没抢到, 下一轮由定时任务继续"
exit 0
