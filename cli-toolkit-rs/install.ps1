#Requires -Version 5.1
<#
.SYNOPSIS
  cli-toolkit-rs 安装器：一行安装 / 本地 zip 离线安装 / 幂等升级 / 卸载。
.DESCRIPTION
  设计参考（AGENTS.md 规则，先调研）：
   - apm 的 `irm ... | iex` 引导脚本（https://github.com/microsoft/apm/blob/main/install.ps1）
   - supply chain 的 SHA256SUMS 校验实践（https://codafort.dev/docs/supply-chain）
   一行安装示例：
   irm https://v6.gh-proxy.org/https://raw.githubusercontent.com/zeno-ling/cli-toolkit-rs/main/cli-toolkit-rs/install.ps1 | iex
#>
param(
  [string]$Version = '1.0.0',
  [string]$ZipUrl,                       # 留空则从 DefaultZipUrl 拼 Version
  [string]$ZipPath,                      # 本地 zip 离线路径
  [string]$InstallDir,                   # 默认 $env:LOCALAPPDATA\cli-toolkit-rs
  [switch]$NoPath,                       # 不写用户 PATH
  [switch]$Force,                        # 允许跨版本替换
  [switch]$Uninstall,
  [switch]$WhatIfRun                     # 只解析路径，不落盘
)

$ErrorActionPreference = 'Stop'
$DefaultZipUrl = 'https://v6.gh-proxy.org/https://raw.githubusercontent.com/zeno-ling/cli-toolkit-rs/main/cli-toolkit-rs/cli-toolkit-rs-{0}.zip'

# 固定 pin：发布 zip 的 SHA-256（改版本必须同步改这里）
$PinnedZipSha = @{
  '1.0.0' = '73fb405dc2d7576a1d2d63d525ee3e536ecfe33773d9a097c07798266372a3c9'
}

if (-not $InstallDir) { $InstallDir = Join-Path $env:LOCALAPPDATA 'cli-toolkit-rs' }

function Add-UserPath([string]$dir) {
  $cur = [Environment]::GetEnvironmentVariable('Path', 'User')
  if (-not $cur) { $cur = '' }
  $entries = $cur -split ';' | Where-Object { $_ }
  if ($entries -contains $dir) { Write-Host "PATH UP-TO-DATE $dir"; return }
  $new = if ($cur.TrimEnd(';')) { "$cur;$dir" } else { $dir }
  [Environment]::SetEnvironmentVariable('Path', $new, 'User')
  Write-Host "PATH ADDED -> $dir"
}
function Remove-UserPath([string]$dir) {
  $cur = [Environment]::GetEnvironmentVariable('Path', 'User')
  if (-not $cur) { return }
  $entries = $cur -split ';' | Where-Object { $_ -and $_ -ne $dir }
  [Environment]::SetEnvironmentVariable('Path', ($entries -join ';'), 'User')
  Write-Host "PATH REMOVED <- $dir"
}

# ---------- 卸载 ----------
if ($Uninstall) {
  Remove-UserPath $InstallDir
  Write-Host "UNINSTALLED PATH 条目。文件保留在 $InstallDir（如需删除请手动 Remove-Item -Recurse）"
  return
}

# ---------- 解析 zip ----------
if (-not $ZipPath) {
  if (-not $ZipUrl) { $ZipUrl = $DefaultZipUrl -f $Version }
  $tmpDir = Join-Path ([IO.Path]::GetTempPath()) ("ctk-dl-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
  $ZipPath = Join-Path $tmpDir "cli-toolkit-rs-$Version.zip"
  Write-Host "DOWNLOAD $ZipUrl"
  Invoke-WebRequest -Uri $ZipUrl -OutFile $ZipPath -UseBasicParsing
}

if (-not (Test-Path $ZipPath)) { throw "zip 不存在：$ZipPath" }
$actual = (Get-FileHash $ZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
$expected = $PinnedZipSha[$Version]
if (-not $expected) { throw "版本 $Version 没有 pin，拒绝安装（防止供应链投毒）" }
if ($actual -ne $expected) { throw "SHA-256 校验失败：期望 $expected，实际 $actual。整包拒绝。" }
Write-Host "VERIFIED zip sha256=$actual"

# ---------- 版本检查 ----------
$verFile = Join-Path $InstallDir 'version.txt'
if ((Test-Path $verFile) -and (($ver = (Get-Content $verFile -Raw).Trim()) -ne $Version) -and -not $Force) {
  throw "已安装版本 $ver，与请求的 $Version 不同。要替换请加 -Force。"
}

if (-not $WhatIfRun) {
  # 解压到临时目录再拷贝，避免半成品
  $extractDir = Join-Path ([IO.Path]::GetTempPath()) ("ctk-ex-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
  Expand-Archive -LiteralPath $ZipPath -DestinationPath $extractDir -Force
  $pkgRoot = Join-Path $extractDir 'cli-toolkit-rs'
  if (-not (Test-Path $pkgRoot)) { throw "zip 结构错误：缺少 cli-toolkit-rs/ 根目录" }

  # 逐文件校验 checksums.txt
  $sums = Join-Path $pkgRoot 'checksums.txt'
  if (-not (Test-Path $sums)) { throw "zip 缺少 checksums.txt" }
  foreach ($line in (Get-Content $sums)) {
    if ($line -notmatch '^([0-9a-f]{64})\s+(.+)$') { continue }
    $h = $matches[1]; $f = $matches[2]
    $fp = Join-Path $pkgRoot $f
    if (-not (Test-Path $fp)) { throw "checksums.txt 引用的文件不存在：$f" }
    $ah = (Get-FileHash $fp -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($ah -ne $h) { throw "文件 $f 校验失败：期望 $h 实际 $ah" }
  }
  Write-Host "VERIFIED all files via checksums.txt"

  # 备份旧版本
  if ((Test-Path $verFile) -and ((Get-Content $verFile -Raw).Trim() -ne $Version)) {
    $bak = "$verFile.bak-$((Get-Date).ToString('yyyyMMdd-HHmmss'))"
    Copy-Item $verFile $bak -Force
    Write-Host "BACKUP $bak"
  }

  New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
  foreach ($f in @('cli-toolkit.exe','README.md','RELEASE.md','checksums.txt')) {
    Copy-Item (Join-Path $pkgRoot $f) (Join-Path $InstallDir $f) -Force
  }
  $Version | Set-Content $verFile -Encoding ascii

  if (-not $NoPath) { Add-UserPath $InstallDir }

  Remove-Item -Recurse -Force $extractDir
  if ($tmpDir -and (Test-Path $tmpDir)) { Remove-Item -Recurse -Force $tmpDir }
  Write-Host "INSTALLED cli-toolkit-rs $Version -> $InstallDir"
  Write-Host "重开终端生效；当前会话可执行： & `"$InstallDir\cli-toolkit.exe`" --list"
}
