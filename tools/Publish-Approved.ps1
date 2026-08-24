[CmdletBinding()]
param(
    [string]$Message = "Update approved daily display"
)

$ErrorActionPreference = "Stop"

$mirrorRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $mirrorRoot
$sourceRoot = Join-Path $workspaceRoot "daily-wallpaper-player\public"
$sourceSchedule = Join-Path $sourceRoot "schedule.json"
$sourceVersions = Join-Path $sourceRoot "versions"
$targetSchedule = Join-Path $mirrorRoot "schedule.json"
$targetVersions = Join-Path $mirrorRoot "versions"

if (-not (Test-Path -LiteralPath $sourceSchedule)) {
    throw "正式播放器缺少 public/schedule.json。"
}
if (-not (Test-Path -LiteralPath $sourceVersions)) {
    throw "正式播放器缺少 public/versions。"
}

$schedule = Get-Content -LiteralPath $sourceSchedule -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]$schedule.approvedDate -notmatch '^\d{4}-\d{2}-\d{2}$') {
    throw "schedule.json 的 approvedDate 不合法。"
}
if ([string]::IsNullOrWhiteSpace([string]$schedule.versionPath)) {
    throw "schedule.json 缺少 versionPath。"
}

$relativeVersion = ([string]$schedule.versionPath).TrimStart('/')
$sourceVersion = Join-Path $sourceRoot $relativeVersion
if (-not (Test-Path -LiteralPath $sourceVersion)) {
    throw "批准版本文件不存在：$relativeVersion"
}
$versionText = Get-Content -LiteralPath $sourceVersion -Raw -Encoding UTF8
if (
    $versionText.Length -lt 10000 -or
    $versionText -notmatch 'data-target-resolution="1280x960"' -or
    $versionText -match '(?is)sorry.{0,120}blocked|you have been blocked|cf-error-details'
) {
    throw "批准版本没有通过 1280×960 完整性检查。"
}

$scheduledVersions = @($schedule.scheduledVersions)
foreach ($scheduled in $scheduledVersions) {
    $scheduledDate = [string]$scheduled.date
    $scheduledPath = [string]$scheduled.versionPath
    if ($scheduledDate -notmatch '^\d{4}-\d{2}-\d{2}$' -or [string]::IsNullOrWhiteSpace($scheduledPath)) {
        throw "预约版本字段不合法。"
    }
    $scheduledRelative = $scheduledPath.TrimStart('/')
    $scheduledSource = Join-Path $sourceRoot $scheduledRelative
    if (-not (Test-Path -LiteralPath $scheduledSource)) {
        throw "预约版本文件不存在：$scheduledRelative"
    }
    $scheduledText = Get-Content -LiteralPath $scheduledSource -Raw -Encoding UTF8
    if (
        $scheduledText.Length -lt 10000 -or
        $scheduledText -notmatch 'data-target-resolution="1280x960"' -or
        $scheduledText -match '(?is)sorry.{0,120}blocked|you have been blocked|cf-error-details'
    ) {
        throw "预约版本没有通过 1280×960 完整性检查：$scheduledRelative"
    }
}

New-Item -ItemType Directory -Path $targetVersions -Force | Out-Null
Copy-Item -LiteralPath $sourceSchedule -Destination $targetSchedule -Force
Get-ChildItem -LiteralPath $sourceVersions -File -Filter "*.html" | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $targetVersions $_.Name) -Force
}

& git -C $mirrorRoot add -- schedule.json versions index.html .nojekyll README.md tools/Publish-Approved.ps1
if ($LASTEXITCODE -ne 0) {
    throw "备用源 git add 失败。"
}

& git -C $mirrorRoot diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
    Write-Host "备用源内容没有变化。"
    exit 0
}
if ($LASTEXITCODE -ne 1) {
    throw "备用源 git diff 检查失败。"
}

& git -C $mirrorRoot commit -m $Message
if ($LASTEXITCODE -ne 0) {
    throw "备用源 git commit 失败。"
}
Write-Host "备用更新源内容已经提交，等待推送。"
