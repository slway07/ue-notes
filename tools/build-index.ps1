<#
.SYNOPSIS
  pages\*.html 의 meta 태그를 읽어 index.html 목차를 만든다.
.DESCRIPTION
  읽는 meta: note-title (필수), note-summary, note-tags (쉼표 구분), note-order (정수).
  종료 코드
    0  생성 완료 (페이지 0개 포함)
    1  note-title 이 없는 페이지가 있음
#>
param(
    [string]$Root = "D:\Work\Notes"
)

$utf8 = New-Object System.Text.UTF8Encoding($false)

# HTML 이스케이프. & 를 가장 먼저 처리해야 이중 이스케이프가 되지 않는다.
function Escape-Html([string]$s) {
    $s = $s.Replace('&', '&amp;')
    $s = $s.Replace('<', '&lt;')
    $s = $s.Replace('>', '&gt;')
    $s = $s.Replace('"', '&quot;')
    return $s
}

# 파일명(href 용): 파일명 부분만 URL 처리 후 HTML 이스케이프.
function Get-HrefName([string]$fileName) {
    $s = $fileName.Replace('%', '%25')
    $s = $s.Replace('#', '%23')
    $s = $s.Replace('?', '%3F')
    $s = $s.Replace(' ', '%20')
    return (Escape-Html $s)
}

$pagesDir = Join-Path $Root "pages"
$indexPath = Join-Path $Root "index.html"

$files = @()
if (Test-Path -LiteralPath $pagesDir -PathType Container) {
    $files = @(Get-ChildItem -LiteralPath $pagesDir -Filter "*.html" -File | Sort-Object Name)
}

$pages = New-Object System.Collections.Generic.List[object]

foreach ($f in $files) {
    $text = [System.IO.File]::ReadAllText($f.FullName, [System.Text.Encoding]::UTF8)

    # <head> 블록만 본다. head 가 없으면 빈 문자열이 되어 note-title 없음으로 처리된다.
    $headMatch = [regex]::Match($text, '(?is)<head\b.*?</head>')
    $head = if ($headMatch.Success) { $headMatch.Value } else { "" }

    # meta 태그 하나 전체. 따옴표 안의 > 는 태그 끝으로 보지 않는다.
    $meta = @{}
    $tagMatches = [regex]::Matches($head, '(?is)<meta\b(?:[^>"'']|"[^"]*"|''[^'']*'')*>')
    foreach ($tm in $tagMatches) {
        $tag = $tm.Value
        $nm = [regex]::Match($tag, '(?i)(?<![\w-])name\s*=\s*"([^"]*)"')
        $ct = [regex]::Match($tag, '(?i)(?<![\w-])content\s*=\s*"([^"]*)"')
        if ($nm.Success -and $ct.Success) {
            $key = $nm.Groups[1].Value.Trim().ToLowerInvariant()
            if (-not $meta.ContainsKey($key)) {
                # 속성값의 HTML 엔티티를 풀어서 평문으로 보관한다 (출력 시 다시 이스케이프).
                $meta[$key] = [System.Net.WebUtility]::HtmlDecode($ct.Groups[1].Value)
            }
        }
    }

    if (-not $meta.ContainsKey('note-title') -or [string]::IsNullOrWhiteSpace($meta['note-title'])) {
        Write-Host "[오류] note-title 메타 태그가 없습니다: $($f.FullName)" -ForegroundColor Red
        exit 1
    }

    $title = $meta['note-title'].Trim()

    $summary = ""
    if ($meta.ContainsKey('note-summary')) { $summary = $meta['note-summary'].Trim() }

    $tags = @()
    if ($meta.ContainsKey('note-tags')) {
        $tags = @($meta['note-tags'].Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    }

    $order = 999
    if ($meta.ContainsKey('note-order')) {
        $raw = $meta['note-order'].Trim()
        if ($raw -match '^-?\d+$') {
            $parsed = 0
            if ([int]::TryParse($raw, [System.Globalization.NumberStyles]::AllowLeadingSign, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
                $order = $parsed
            }
        }
    }

    $pages.Add([pscustomobject]@{
        FileName = $f.Name
        Title    = $title
        Summary  = $summary
        Tags     = $tags
        Order    = $order
    })
}

# 정렬: note-order 오름차순, 같으면 note-title 가나다순 (대소문자 무시).
$sorted = New-Object System.Collections.Generic.List[object]
$sorted.AddRange($pages)
$sorted.Sort([System.Comparison[object]]{
    param($a, $b)
    if ($a.Order -ne $b.Order) { return [int]([long]$a.Order - [long]$b.Order) }
    return [string]::Compare($a.Title, $b.Title, $true)
})

$count = $sorted.Count

$listLines = New-Object System.Collections.Generic.List[string]
if ($count -eq 0) {
    $listLines.Add('<p class="empty">아직 페이지가 없다.</p>')
} else {
    $listLines.Add('<ul class="toc">')
    foreach ($p in $sorted) {
        $href = Get-HrefName $p.FileName
        $listLines.Add("<li><a href=""pages/$href"">")
        $listLines.Add('<span class="t">' + (Escape-Html $p.Title) + '</span>')
        if ($p.Summary -ne "") {
            $listLines.Add('<span class="s">' + (Escape-Html $p.Summary) + '</span>')
        }
        if ($p.Tags.Count -gt 0) {
            $tagHtml = ($p.Tags | ForEach-Object { '<span class="tag">' + (Escape-Html $_) + '</span>' }) -join ''
            $listLines.Add('<span class="tags">' + $tagHtml + '</span>')
        }
        $listLines.Add('</a></li>')
    }
    $listLines.Add('</ul>')
}

$today = Get-Date -Format "yyyy-MM-dd"

$template = @(
    '<!doctype html>',
    '<html lang="ko">',
    '<head>',
    '<meta charset="utf-8">',
    '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">',
    '<title>ue-notes</title>',
    '<meta name="description" content="언리얼 엔진 학습 노트">',
    '<meta name="theme-color" content="#2f6f4f">',
    '<link rel="stylesheet" href="assets/style.css">',
    '</head>',
    '<body>',
    '<div class="wrap">',
    '<header class="site-head">',
    '<h1>ue-notes</h1>',
    '<p>언리얼 엔진 학습 노트 &middot; 눈으로 보는 쪽에 가깝게</p>',
    '</header>',
    '<main>',
    '<!-- LIST -->',
    '</main>',
    '<footer class="site-foot">',
    "<p>마지막 갱신 $today &middot; 페이지 ${count}개</p>",
    '</footer>',
    '</div>',
    '</body>',
    '</html>'
)

$outLines = New-Object System.Collections.Generic.List[string]
foreach ($line in $template) {
    if ($line -eq '<!-- LIST -->') {
        foreach ($l in $listLines) { $outLines.Add($l) }
    } else {
        $outLines.Add($line)
    }
}

$text = ($outLines -join "`n") + "`n"
[System.IO.File]::WriteAllText($indexPath, $text, $utf8)

Write-Host "[목차] index.html 생성 — 페이지 ${count}개" -ForegroundColor Green
exit 0
