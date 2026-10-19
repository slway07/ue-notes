<#
.SYNOPSIS
  금칙어 게이트 -> 목차 생성 -> 금칙어 게이트 -> 커밋 -> 푸시 순서로 배포한다.
.DESCRIPTION
  하나라도 실패하면 거기서 멈추고 push 하지 않는다.
  게이트를 건너뛰는 옵션은 두지 않는다.
#>
param(
    [string]$Root = "D:\Work\Notes",
    [string]$Message = ""
)

$checkScript = Join-Path $Root "tools\check-forbidden.ps1"
$indexScript = Join-Path $Root "tools\build-index.ps1"
$siteUrl = "https://slway07.github.io/ue-notes/"

if ($Message -eq "") {
    $Message = "노트 갱신 " + (Get-Date -Format "yyyy-MM-dd HH:mm")
}

# ---------------------------------------------------------------
# 1. 1차 금칙어 게이트
# ---------------------------------------------------------------
if (-not (Test-Path -LiteralPath $checkScript -PathType Leaf)) {
    Write-Host "[중단] 금칙어 게이트 스크립트가 없습니다: $checkScript" -ForegroundColor Red
    exit 2
}

Write-Host "[1/6] 1차 금칙어 게이트 실행"
& powershell -NoProfile -ExecutionPolicy Bypass -File $checkScript -Root $Root
if ($LASTEXITCODE -ne 0) {
    Write-Host "[중단] 1차 금칙어 게이트 실패 (종료 코드 $LASTEXITCODE). 배포하지 않습니다." -ForegroundColor Red
    exit $LASTEXITCODE
}

# ---------------------------------------------------------------
# 2. 목차 생성
# ---------------------------------------------------------------
if (-not (Test-Path -LiteralPath $indexScript -PathType Leaf)) {
    Write-Host "[중단] 목차 생성 스크립트가 없습니다: $indexScript" -ForegroundColor Red
    exit 2
}

Write-Host "[2/6] 목차 생성"
& powershell -NoProfile -ExecutionPolicy Bypass -File $indexScript -Root $Root
if ($LASTEXITCODE -ne 0) {
    Write-Host "[중단] 목차 생성 실패 (종료 코드 $LASTEXITCODE). 배포하지 않습니다." -ForegroundColor Red
    exit $LASTEXITCODE
}

# ---------------------------------------------------------------
# 3. 2차 금칙어 게이트 (생성된 index.html 포함 재검사)
# ---------------------------------------------------------------
Write-Host "[3/6] 2차 금칙어 게이트 실행 (생성된 index.html 포함)"
& powershell -NoProfile -ExecutionPolicy Bypass -File $checkScript -Root $Root
if ($LASTEXITCODE -ne 0) {
    Write-Host "[중단] 2차 금칙어 게이트 실패 (종료 코드 $LASTEXITCODE). 배포하지 않습니다." -ForegroundColor Red
    exit $LASTEXITCODE
}

# ---------------------------------------------------------------
# 4. 변경 확인
# ---------------------------------------------------------------
Write-Host "[4/6] 변경 확인"
$status = @(git -C $Root status --porcelain)
if ($LASTEXITCODE -ne 0) {
    Write-Host "[중단] git status 실패 (종료 코드 $LASTEXITCODE). Root 가 Git 저장소인지 확인하세요." -ForegroundColor Red
    exit 1
}
$changed = @($status | Where-Object { $_ -ne "" })
if ($changed.Count -eq 0) {
    Write-Host "변경 사항이 없다 — 배포할 것이 없음" -ForegroundColor Yellow
    exit 0
}

# ---------------------------------------------------------------
# 5. 커밋
# ---------------------------------------------------------------
Write-Host "[5/6] 커밋: $Message"
git -C $Root add -A
if ($LASTEXITCODE -ne 0) {
    Write-Host "[실패] git add 실패 (종료 코드 $LASTEXITCODE)" -ForegroundColor Red
    exit 1
}
git -C $Root commit -m $Message
if ($LASTEXITCODE -ne 0) {
    Write-Host "[실패] git commit 실패 (종료 코드 $LASTEXITCODE)" -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------
# 6. 푸시
# ---------------------------------------------------------------
Write-Host "[6/6] 푸시: origin main"
git -C $Root push origin main
if ($LASTEXITCODE -ne 0) {
    Write-Host "[실패] git push 실패 (종료 코드 $LASTEXITCODE)" -ForegroundColor Red
    exit 1
}

$hash = git -C $Root rev-parse --short HEAD
Write-Host "[배포 완료] $siteUrl" -ForegroundColor Green
Write-Host "커밋 해시: $hash" -ForegroundColor Green
exit 0
