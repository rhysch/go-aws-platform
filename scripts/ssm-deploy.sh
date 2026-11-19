#!/usr/bin/env bash
set -euo pipefail
: "${RELEASE_SHA:?}" "${RELEASE_BUCKET:?}" "${INSTANCE_ID:?}" "${AWS_REGION:?}" "${SSM_LOG_GROUP:?}"
[[ $RELEASE_SHA =~ ^[a-f0-9]{40}$ ]]
[[ $RELEASE_BUCKET =~ ^[a-z0-9][a-z0-9.-]+[a-z0-9]$ ]]
[[ $INSTANCE_ID =~ ^i-[a-f0-9]+$ ]]
# JSON encoding is done by jq, not by concatenating unescaped JSON strings.
# The full release is downloaded with the instance role, verified, then executed.
remote_script=$(cat <<EOF
set -eu
cloud-init status --wait
 test -f /opt/go-aws-platform/bootstrap-complete
release=/opt/go-aws-platform/releases/$RELEASE_SHA
mkdir -p "\$release"
cd "\$release"
aws s3 cp s3://$RELEASE_BUCKET/releases/$RELEASE_SHA/release.tar.gz . --region $AWS_REGION
aws s3 cp s3://$RELEASE_BUCKET/releases/$RELEASE_SHA/release.tar.gz.sha256 . --region $AWS_REGION
sha256sum -c release.tar.gz.sha256
tar -xzf release.tar.gz --no-same-owner
bash ./deploy.sh $RELEASE_SHA
EOF
)
parameters=$(jq -n --arg script "$remote_script" '{commands:[$script],executionTimeout:["900"]}')
command_id=$(aws ssm send-command --region "$AWS_REGION" --instance-ids "$INSTANCE_ID" \
  --document-name AWS-RunShellScript --parameters "$parameters" \
  --cloud-watch-output-config "CloudWatchOutputEnabled=true,CloudWatchLogGroupName=$SSM_LOG_GROUP" \
  --query 'Command.CommandId' --output text)
echo "SSM command: $command_id"
for ((attempt = 1; attempt <= 190; attempt++)); do
    invocation=$(aws ssm get-command-invocation --region "$AWS_REGION" \
      --command-id "$command_id" --instance-id "$INSTANCE_ID" --output json 2>/dev/null || true)
    if [[ -z $invocation ]]; then invocation='{}'; fi
    status=$(jq -r '.Status // "Pending"' <<< "$invocation")
    case "$status" in
      Success)
        jq -r '.StandardOutputContent' <<< "$invocation"
        exit 0 ;;
      Failed|TimedOut|Cancelled|Cancelling)
        jq -r '.StandardOutputContent,.StandardErrorContent' <<< "$invocation" >&2
        exit 1 ;;
    esac
    sleep 5
done
echo "Timed out waiting; inspect command $command_id in Systems Manager before redeploying" >&2
exit 1
