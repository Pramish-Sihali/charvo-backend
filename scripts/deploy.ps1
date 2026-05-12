#requires -Version 5.1
<#
.SYNOPSIS
  Build, push, and deploy the CharcoalX backend to AWS ECS Fargate.

.DESCRIPTION
  Idempotent: safe to re-run. On first run creates ECR repo, CloudWatch log
  group, task definition, ECS service. On subsequent runs builds a new image,
  registers a new task definition revision, and triggers a rolling update.

  Assumes AWS Educate Learner Lab constraints:
  - Region locked to us-east-1
  - LabRole is the only usable IAM role (executionRoleArn + taskRoleArn)
  - Default VPC with public subnets (assignPublicIp=ENABLED, no NAT Gateway)

.PARAMETER ImageTag
  Tag for the Docker image (default: short git SHA + timestamp).

.EXAMPLE
  .\scripts\deploy.ps1
  .\scripts\deploy.ps1 -ImageTag v1
#>
[CmdletBinding()]
param(
  [string]$ImageTag = $(if (Get-Command git -ErrorAction SilentlyContinue) { (git rev-parse --short HEAD 2>$null) } else { (Get-Date -Format 'yyyyMMddHHmm') })
)

$ErrorActionPreference = 'Stop'

# ── Config ────────────────────────────────────────────────────────────────
$AWS_REGION   = 'us-east-1'
$ECR_REPO     = 'charcoalx-backend'
$CLUSTER      = 'charcoalx'
$SERVICE      = 'charcoalx-backend'
$FAMILY       = 'charcoalx-backend'
$LOG_GROUP    = '/ecs/charcoalx'
$CONTAINER    = 'charcoalx-backend'
$TASK_DEF_TPL = Join-Path $PSScriptRoot '..\infra\task-definition.json'
$ENV_LOCAL    = Join-Path $PSScriptRoot '..\.env.local'

function Step($msg) { Write-Host "`n[deploy] $msg" -ForegroundColor Cyan }
function Info($msg) { Write-Host "         $msg" -ForegroundColor DarkGray }
function Ok($msg)   { Write-Host "       OK $msg" -ForegroundColor Green }
function Die($msg)  { Write-Host "    FATAL $msg" -ForegroundColor Red; exit 1 }

# ── Preflight ─────────────────────────────────────────────────────────────
Step 'Preflight checks'
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) { Die 'aws CLI not found on PATH. Install: winget install -e --id Amazon.AWSCLI' }
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Die 'docker not found on PATH. Start Docker Desktop.' }
if (-not (Test-Path $TASK_DEF_TPL)) { Die "Task definition template missing: $TASK_DEF_TPL" }
if (-not (Test-Path $ENV_LOCAL)) { Die "$ENV_LOCAL not found. Copy .env.example -> .env.local and fill DATABASE_URL + JWT_SECRET." }

$caller = aws sts get-caller-identity --output json 2>$null | ConvertFrom-Json
if (-not $caller) { Die 'aws sts get-caller-identity failed. Run aws configure with AWS Educate Learner Lab credentials.' }
$AWS_ACCOUNT_ID = $caller.Account
Ok "AWS account $AWS_ACCOUNT_ID  (caller: $($caller.Arn))"

# ── Load env vars from .env.local for task definition ─────────────────────
Step 'Loading runtime env from .env.local'
$envVars = @{}
Get-Content $ENV_LOCAL | Where-Object { $_ -match '^\s*[A-Z_]+\s*=' } | ForEach-Object {
  $k, $v = $_ -split '=', 2
  $envVars[$k.Trim()] = $v.Trim()
}
foreach ($key in 'DATABASE_URL','JWT_SECRET') {
  if (-not $envVars.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($envVars[$key])) {
    Die "$key missing or empty in .env.local"
  }
}
$ALLOWED_ORIGINS = if ($envVars.ContainsKey('ALLOWED_ORIGINS')) { $envVars['ALLOWED_ORIGINS'] } else { '*' }
Ok "DATABASE_URL + JWT_SECRET present  (ALLOWED_ORIGINS=$ALLOWED_ORIGINS)"

# ── ECR repo ──────────────────────────────────────────────────────────────
Step 'Ensuring ECR repository exists'
$existing = aws ecr describe-repositories --repository-names $ECR_REPO --region $AWS_REGION --output json 2>$null
if (-not $existing) {
  aws ecr create-repository --repository-name $ECR_REPO --region $AWS_REGION --image-scanning-configuration scanOnPush=true | Out-Null
  Ok "Created ECR repo $ECR_REPO"
} else {
  Ok "ECR repo $ECR_REPO already exists"
}
$ECR_URI = "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO"
$IMAGE_URI = "${ECR_URI}:${ImageTag}"

# ── Docker login + build + push ───────────────────────────────────────────
Step "Building image $IMAGE_URI"
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URI | Out-Null
docker build -t $IMAGE_URI -t "${ECR_URI}:latest" (Join-Path $PSScriptRoot '..')
if ($LASTEXITCODE -ne 0) { Die 'docker build failed' }

Step 'Pushing to ECR'
docker push $IMAGE_URI
docker push "${ECR_URI}:latest"
if ($LASTEXITCODE -ne 0) { Die 'docker push failed' }
Ok "Pushed $IMAGE_URI"

# ── CloudWatch log group ──────────────────────────────────────────────────
Step 'Ensuring CloudWatch log group exists'
aws logs describe-log-groups --log-group-name-prefix $LOG_GROUP --region $AWS_REGION --output json > $null 2>&1
if ($LASTEXITCODE -ne 0) {
  aws logs create-log-group --log-group-name $LOG_GROUP --region $AWS_REGION | Out-Null
  aws logs put-retention-policy --log-group-name $LOG_GROUP --retention-in-days 7 --region $AWS_REGION | Out-Null
  Ok "Created $LOG_GROUP (7-day retention)"
} else {
  Ok "$LOG_GROUP already exists"
}

# ── Render and register task definition ───────────────────────────────────
Step 'Rendering task definition'
$tpl = Get-Content $TASK_DEF_TPL -Raw
$tpl = $tpl.Replace('__AWS_ACCOUNT_ID__',  $AWS_ACCOUNT_ID)
$tpl = $tpl.Replace('__ECR_IMAGE_URI__',   $IMAGE_URI)
$tpl = $tpl.Replace('__DATABASE_URL__',    ($envVars['DATABASE_URL'] -replace '"','\"'))
$tpl = $tpl.Replace('__JWT_SECRET__',      ($envVars['JWT_SECRET']   -replace '"','\"'))
$tpl = $tpl.Replace('__ALLOWED_ORIGINS__', ($ALLOWED_ORIGINS         -replace '"','\"'))

$rendered = Join-Path $env:TEMP "charcoalx-task-def-$ImageTag.json"
[System.IO.File]::WriteAllText($rendered, $tpl)

Step 'Registering task definition'
$registered = aws ecs register-task-definition --cli-input-json file://$rendered --region $AWS_REGION --output json | ConvertFrom-Json
$TASK_DEF_ARN = $registered.taskDefinition.taskDefinitionArn
Remove-Item $rendered -Force
Ok "Registered $TASK_DEF_ARN"

# ── ECS cluster ───────────────────────────────────────────────────────────
Step 'Ensuring ECS cluster exists'
$clusterInfo = aws ecs describe-clusters --clusters $CLUSTER --region $AWS_REGION --output json | ConvertFrom-Json
if ($clusterInfo.clusters.Count -eq 0 -or $clusterInfo.clusters[0].status -ne 'ACTIVE') {
  aws ecs create-cluster --cluster-name $CLUSTER --region $AWS_REGION | Out-Null
  Ok "Created cluster $CLUSTER"
} else {
  Ok "Cluster $CLUSTER already ACTIVE"
}

# ── Networking: default VPC subnets + a security group for the task ───────
Step 'Resolving default VPC, subnets, and security group'
$defaultVpc = (aws ec2 describe-vpcs --filters 'Name=is-default,Values=true' --region $AWS_REGION --query 'Vpcs[0].VpcId' --output text).Trim()
if (-not $defaultVpc -or $defaultVpc -eq 'None') { Die 'No default VPC found in this region.' }
$subnetIds = (aws ec2 describe-subnets --filters "Name=vpc-id,Values=$defaultVpc" "Name=map-public-ip-on-launch,Values=true" --region $AWS_REGION --query 'Subnets[].SubnetId' --output text).Trim() -split '\s+'
Info "VPC $defaultVpc  /  $($subnetIds.Count) public subnets"

$sgName = 'charcoalx-task-sg'
$sgId = (aws ec2 describe-security-groups --filters "Name=group-name,Values=$sgName" "Name=vpc-id,Values=$defaultVpc" --region $AWS_REGION --query 'SecurityGroups[0].GroupId' --output text).Trim()
if (-not $sgId -or $sgId -eq 'None') {
  $sgId = (aws ec2 create-security-group --group-name $sgName --description 'CharcoalX Fargate task ingress (open 8000 for MVP)' --vpc-id $defaultVpc --region $AWS_REGION --query 'GroupId' --output text).Trim()
  aws ec2 authorize-security-group-ingress --group-id $sgId --protocol tcp --port 8000 --cidr 0.0.0.0/0 --region $AWS_REGION | Out-Null
  Ok "Created security group $sgId"
} else {
  Ok "Security group $sgId already exists"
}

# ── ECS service ───────────────────────────────────────────────────────────
Step 'Creating or updating ECS service'
$svc = aws ecs describe-services --cluster $CLUSTER --services $SERVICE --region $AWS_REGION --output json | ConvertFrom-Json
$exists = $svc.services.Count -gt 0 -and $svc.services[0].status -eq 'ACTIVE'

if (-not $exists) {
  $subnetList = $subnetIds -join ','
  $netCfg = "awsvpcConfiguration={subnets=[$subnetList],securityGroups=[$sgId],assignPublicIp=ENABLED}"
  aws ecs create-service `
    --cluster $CLUSTER `
    --service-name $SERVICE `
    --task-definition $TASK_DEF_ARN `
    --desired-count 1 `
    --launch-type FARGATE `
    --network-configuration $netCfg `
    --region $AWS_REGION | Out-Null
  Ok "Created service $SERVICE (desiredCount=1)"
} else {
  aws ecs update-service `
    --cluster $CLUSTER `
    --service $SERVICE `
    --task-definition $TASK_DEF_ARN `
    --force-new-deployment `
    --region $AWS_REGION | Out-Null
  Ok "Updated service $SERVICE to new task definition"
}

# ── Wait for task + show public IP ────────────────────────────────────────
Step 'Waiting for task to enter RUNNING state (up to ~3 min)'
$tries = 0
do {
  Start-Sleep -Seconds 10
  $tasks = aws ecs list-tasks --cluster $CLUSTER --service-name $SERVICE --desired-status RUNNING --region $AWS_REGION --output json | ConvertFrom-Json
  $tries++
  Info "  attempt $tries  /  running tasks: $($tasks.taskArns.Count)"
} while ($tasks.taskArns.Count -eq 0 -and $tries -lt 18)

if ($tasks.taskArns.Count -eq 0) {
  Write-Host "`n[deploy] WARNING — task not running yet. Check:" -ForegroundColor Yellow
  Write-Host "  aws ecs describe-services --cluster $CLUSTER --services $SERVICE --region $AWS_REGION" -ForegroundColor Yellow
  exit 0
}

$taskDesc = aws ecs describe-tasks --cluster $CLUSTER --tasks $tasks.taskArns[0] --region $AWS_REGION --output json | ConvertFrom-Json
$eni = ($taskDesc.tasks[0].attachments[0].details | Where-Object name -eq 'networkInterfaceId').value
$publicIp = (aws ec2 describe-network-interfaces --network-interface-ids $eni --region $AWS_REGION --query 'NetworkInterfaces[0].Association.PublicIp' --output text).Trim()

Write-Host ""
Write-Host "==================================================================" -ForegroundColor Green
Write-Host " Deploy complete." -ForegroundColor Green
Write-Host "   Image:     $IMAGE_URI"
Write-Host "   Task def:  $TASK_DEF_ARN"
Write-Host "   Public IP: http://${publicIp}:8000"
Write-Host "   Health:    http://${publicIp}:8000/health"
Write-Host "   Docs:      http://${publicIp}:8000/docs"
Write-Host "==================================================================" -ForegroundColor Green
Write-Host ""
Write-Host "NOTE: This deploy uses the task's public IP directly (no ALB)." -ForegroundColor Yellow
Write-Host "      The IP changes each time the task restarts. To get a stable" -ForegroundColor Yellow
Write-Host "      URL for Vercel, add an Application Load Balancer (~`$16/mo)." -ForegroundColor Yellow
