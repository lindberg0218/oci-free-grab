#!/usr/bin/env bash
# 抢 Oracle 免费机: 每轮先 A1.Flex(4C24G), 没货再 E2.1.Micro(1C1G), 成功即停。
# 本地跑: 需先 oci setup config; 变量从环境读。
set -u
REGION="${OCI_REGION:-ap-singapore-1}"
COMPARTMENT_ID="${OCI_TENANCY_OCID:?缺 OCI_TENANCY_OCID}"
SUBNET_ID="${OCI_SUBNET_ID:?缺 OCI_SUBNET_ID}"
SSH_PUBKEY="${SSH_PUBKEY:?缺 SSH_PUBKEY}"
DEADLINE_SECS="${DEADLINE_SECS:-480}"
BOOT_GB="${BOOT_GB:-100}"
SLEEP_SECS="${SLEEP_SECS:-45}"
END=$(( $(date +%s) + DEADLINE_SECS ))

log(){ echo "[$(date -u '+%H:%M:%S')Z] $*"; }

AD=$(oci iam availability-domain list --compartment-id "$COMPARTMENT_ID" --region "$REGION" \
      --query 'data[0].name' --raw-output 2>/dev/null)
case "$AD" in ""|null) echo "AD 解析失败"; exit 1;; esac
log "AD=$AD"

img(){ # $1=匹配串
  oci compute image list --compartment-id "$COMPARTMENT_ID" --region "$REGION" \
    --operating-system "Canonical Ubuntu" --operating-system-version "22.04" \
    --query "data[?contains(\"display-name\", \`$1\`)].{id:id,t:\"time-created\"} | sort_by(@,&t) | [-1].id" \
    --raw-output 2>/dev/null
}
IMG_ARM=$(img aarch64); IMG_X86=$(img x86_64)
log "IMG_ARM=$IMG_ARM"; log "IMG_X86=$IMG_X86"

try(){
  oci compute instance launch --region "$REGION" --availability-domain "$AD" \
    --compartment-id "$COMPARTMENT_ID" --shape "$1" --shape-config "$2" \
    --subnet-id "$SUBNET_ID" --assign-public-ip true --display-name "$4" \
    --metadata "{\"ssh_authorized_keys\": \"$SSH_PUBKEY\"}" \
    --source-details "{\"sourceType\":\"image\",\"imageId\":\"$3\",\"bootVolumeSizeInGBs\":$BOOT_GB}" 2>&1
}

report(){ # $1=launch 输出
  IID=$(echo "$1" | grep -o 'ocid1\.instance\.[^"]*' | head -1)
  log "✅ 建成: $IID"
  PIP=$(oci compute instance list-vnics --instance-id "$IID" --region "$REGION" \
        --query 'data[0]."public-ip"' --raw-output 2>/dev/null)
  log "公网IP: $PIP"
  log "登录: ssh -i ~/.ssh/oracle_free ubuntu@$PIP"
}

N=0
while [ "$(date +%s)" -lt "$END" ]; do
  N=$((N+1)); log "第 $N 轮"
  if [ -n "$IMG_ARM" ] && [ "$IMG_ARM" != "null" ]; then
    OUT=$(try VM.Standard.A1.Flex '{"ocpus":4,"memoryInGBs":24}' "$IMG_ARM" a1-free)
    if echo "$OUT" | grep -q '"lifecycle-state"'; then report "$OUT"; exit 0; fi
    echo "$OUT" | grep -qi 'capacity\|容量不足\|OutOfCapacity\|HostCapacity\|429\|TooManyRequests\|timed out' \
      || log "A1 异常: $(echo "$OUT" | tr -d '\n' | cut -c1-300)"
  fi
  if [ -n "$IMG_X86" ] && [ "$IMG_X86" != "null" ]; then
    OUT=$(try VM.Standard.E2.1.Micro '{"ocpus":1,"memoryInGBs":1}' "$IMG_X86" e2-free)
    if echo "$OUT" | grep -q '"lifecycle-state"'; then report "$OUT"; exit 0; fi
    echo "$OUT" | grep -qi 'capacity\|容量不足\|OutOfCapacity\|HostCapacity\|429\|TooManyRequests\|timed out' \
      || log "E2 异常: $(echo "$OUT" | tr -d '\n' | cut -c1-300)"
  fi
  sleep $(( SLEEP_SECS + RANDOM % 15 ))
done
log "本轮没抢到, 下一轮由定时任务继续"
exit 0
