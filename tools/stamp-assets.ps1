<#
.SYNOPSIS
  assets 아래 공용 파일(style.css, viz.js)의 링크에 내용 해시를 ?v= 로 붙인다.
.DESCRIPTION
  이게 없으면 CSS/JS 를 고쳐도 브라우저가 캐시된 옛 파일을 계속 쓴다.
  페이지 HTML 은 목차에서 ?v= 를 받지만 CSS/JS 링크에는 아무도 붙여 주지 않아서
  "고쳤는데 안 바뀐다" 가 생긴다. deploy.ps1 이 배포 전에 이 스크립트를 부른다.

  바꾸는 것은 href/src 의 쿼리뿐이고 파일 내용은 건드리지 않는다.
  인코딩은 UTF-8(BOM 없음), 줄바꿈 LF 로 유지한다.
#>
param(
    [string]$Root = "D:\Work\Notes"
)

$ErrorActionPreference = "Stop"

# 해시를 붙일 공용 파일들. 파일명(확장자 포함) 기준으로 찾는다.
$assets = @("style.css", "viz.js")

$assetsDir = Join-Path $Root "assets"
if (-not (Test-Path -LiteralPath $assetsDir -PathType Container)) {
    Write-Host "[중단] assets 폴더가 없습니다: $assetsDir" -ForegroundColor Red
    exit 2
}

# 1) 각 에셋의 내용 해시 8자리를 구한다
$hashOf = @{}
foreach ($name in $assets) {
    $path = Join-Path $assetsDir $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $h = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.Substring(0, 8).ToLower()
    $hashOf[$name] = $h
}

if ($hashOf.Count -eq 0) {
    Write-Host "[스탬프] 대상 에셋이 없습니다. 건너뜁니다." -ForegroundColor Yellow
    exit 0
}

# 2) 모든 HTML 에서 링크를 찾아 ?v= 를 새 해시로 바꾼다
$targets = @()
foreach ($sub in @("pages", "drafts")) {
    $dir = Join-Path $Root $sub
    if (Test-Path -LiteralPath $dir -PathType Container) {
        $targets += Get-ChildItem -LiteralPath $dir -Filter "*.html" -File
    }
}
$indexPath = Join-Path $Root "index.html"
if (Test-Path -LiteralPath $indexPath -PathType Leaf) {
    $targets += Get-Item -LiteralPath $indexPath
}

$utf8NoBom = New-Object System.Text.UTF8Encoding $false
$changed = 0
$stamped = 0

foreach ($file in $targets) {
    $text = [System.IO.File]::ReadAllText($file.FullName)
    $orig = $text

    foreach ($name in $hashOf.Keys) {
        $h = $hashOf[$name]
        # (어떤 경로든) .../<name> 또는 .../<name>?v=xxxx 를 .../<name>?v=<해시> 로
        $escaped = [regex]::Escape($name)
        $pattern = "(?<prefix>(?:href|src)\s*=\s*[""'][^""']*?)" + $escaped + "(?:\?v=[A-Za-z0-9]+)?(?<suffix>[""'])"
        $text = [regex]::Replace($text, $pattern, {
            param($m)
            $script:stamped++
            $m.Groups["prefix"].Value + $name + "?v=" + $h + $m.Groups["suffix"].Value
        })
    }

    if ($text -ne $orig) {
        [System.IO.File]::WriteAllText($file.FullName, $text, $utf8NoBom)
        $changed++
    }
}

$list = ($hashOf.Keys | Sort-Object | ForEach-Object { "$_=$($hashOf[$_])" }) -join ", "
Write-Host "[스탬프] 에셋 해시 주입 — $list / 링크 ${stamped}곳, 파일 ${changed}개 수정" -ForegroundColor Green
exit 0
