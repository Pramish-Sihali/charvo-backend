#requires -Version 5.1
<#
.SYNOPSIS
  Scale CharcoalX ECS service to zero to pause Fargate billing between demos.
.DESCRIPTION
  Fargate has no scale-to-zero; the only way to stop the bill is desired-count=0.
  Use scripts\deploy.ps1 to bring it back up.
#>
$ErrorActionPreference = 'Stop'
$AWS_REGION = 'us-east-1'
$CLUSTER    = 'charcoalx'
$SERVICE    = 'charcoalx-backend'

Write-Host "[stop] Scaling $SERVICE to desired-count=0..." -ForegroundColor Cyan
aws ecs update-service --cluster $CLUSTER --service $SERVICE --desired-count 0 --region $AWS_REGION | Out-Null
Write-Host "[stop] Done. Run scripts\deploy.ps1 to redeploy." -ForegroundColor Green
