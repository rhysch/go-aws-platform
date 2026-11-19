#!/usr/bin/env bash
set -euo pipefail
source /etc/go-aws-platform/host.env
healthy=0
if curl -fsS --max-time 5 http://127.0.0.1:8080/healthz | grep -qx ok; then healthy=1; fi
aws cloudwatch put-metric-data --region "$AWS_REGION" --namespace GoAWSPlatform \
  --metric-data "[{\"MetricName\":\"AppHealthy\",\"Dimensions\":[{\"Name\":\"Project\",\"Value\":\"$PROJECT\"}],\"Value\":$healthy,\"Unit\":\"Count\"}]"
