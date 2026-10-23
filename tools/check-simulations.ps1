<#
.SYNOPSIS
  학습 페이지 시뮬레이션 게이트. pages/*.html 에 Viz.animate() 가 있는지 확인한다.
.DESCRIPTION
  종료 코드
    0  모든 페이지에 시뮬레이션이 있음 (또는 data-nosim 예외)
    1  시뮬레이션이 없는 페이지가 있음
    2  설정 오류
  정적 다이어그램만 있는 페이지를 배포하지 않기 위한 검사다.
#>
[CmdletBinding()]
param(
    [string]$Root = "D:\Work\Notes"
)

$ErrorActionPreference = "Stop"

$pagesDir = Join-Path $Root "pages"
if (-not (Test-Path -LiteralPath $pagesDir -PathType Container)) {
    Write-Host "[오류] pages 폴더가 없습니다: $pagesDir" -ForegroundColor Red
    exit 2
}

$missing = New-Object System.Collections.Generic.List[string]
$exceptions = New-Object System.Collections.Generic.List[string]
$ok = 0

foreach ($file in Get-ChildItem -LiteralPath $pagesDir -Filter *.html -File | Where-Object { -not $_.Name.StartsWith('_') } | Sort-Object Name) {
    $text = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    $hasSim = $text -match 'Viz\.animate\s*\('
    $hasException = $text -match 'data-nosim\s*='

    if ($hasSim) {
        $ok++
    } elseif ($hasException) {
        $exceptions.Add($file.Name)
    } else {
        $missing.Add($file.Name)
    }
}

Write-Host "[시뮬레이션] 통과 $ok / 예외 $($exceptions.Count) / 누락 $($missing.Count)"

if ($exceptions.Count -gt 0) {
    Write-Host "  예외:"
    foreach ($name in $exceptions) { Write-Host "    - $name" }
}

if ($missing.Count -gt 0) {
    Write-Host "  누락:" -ForegroundColor Yellow
    foreach ($name in $missing) { Write-Host "    - $name" }
    Write-Host "  각 페이지에 Viz.animate() 로 실제 진행되는 시뮬레이션을 넣거나, 참조 표라면 data-nosim 이유를 적는다."
    exit 1
}

Write-Host "[OK] 모든 페이지에 시뮬레이션이 있습니다." -ForegroundColor Green
exit 0
