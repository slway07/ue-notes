<#
.SYNOPSIS
  pages\*.html 의 meta 태그를 읽어 index.html 목차를 만든다.
.DESCRIPTION
  읽는 meta: note-title (필수), note-summary, note-tags (쉼표 구분), note-order (정수),
             note-category (없거나 비면 "기타").
  카테고리 표시 순서는 tools\categories.txt 를 따른다. 없는 카테고리는 목록 뒤에 가나다순.
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

    $category = "기타"
    if ($meta.ContainsKey('note-category') -and -not [string]::IsNullOrWhiteSpace($meta['note-category'])) {
        $category = $meta['note-category'].Trim()
    }

    # 링크에 붙일 버전: 파일 전체 바이트의 SHA256 앞 8자리(소문자).
    # 내용이 그대로면 주소가 그대로라 캐시가 유효하고, 바뀌면 반드시 새로 받는다.
    $version = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.Substring(0, 8).ToLowerInvariant()

    $pages.Add([pscustomobject]@{
        FileName = $f.Name
        Title    = $title
        Summary  = $summary
        Tags     = $tags
        Order    = $order
        Category = $category
        Version  = $version
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

# 카테고리 표시 순서: tools\categories.txt 에 적힌 순서 먼저, 나머지는 가나다순.
$catPath = Join-Path (Join-Path $Root "tools") "categories.txt"
$listedCats = New-Object System.Collections.Generic.List[string]
if (Test-Path -LiteralPath $catPath -PathType Leaf) {
    foreach ($line in [System.IO.File]::ReadAllLines($catPath, [System.Text.Encoding]::UTF8)) {
        $name = $line.Trim()
        if ($name -eq '' -or $name.StartsWith('#')) { continue }
        if (-not $listedCats.Contains($name)) { $listedCats.Add($name) }
    }
} else {
    Write-Host "[알림] 카테고리 목록 파일이 없습니다: $catPath — 순서 없이 가나다순으로 생성합니다." -ForegroundColor Yellow
}

# 카테고리별 묶음. $sorted 는 이미 note-order/제목 순이라 그룹 안 순서도 그대로 유지된다.
$groups = @{}
foreach ($p in $sorted) {
    if (-not $groups.ContainsKey($p.Category)) {
        $groups[$p.Category] = New-Object System.Collections.Generic.List[object]
    }
    $groups[$p.Category].Add($p)
}

$catOrder = New-Object System.Collections.Generic.List[string]
foreach ($c in $listedCats) {
    if ($groups.ContainsKey($c)) { $catOrder.Add($c) }
}
$extraCats = New-Object System.Collections.Generic.List[string]
foreach ($c in $groups.Keys) {
    if (-not $listedCats.Contains($c)) { $extraCats.Add($c) }
}
$extraCats.Sort([System.Comparison[object]]{
    param($a, $b)
    return [string]::Compare($a, $b, $true)
})
foreach ($c in $extraCats) { $catOrder.Add($c) }

# 페이지가 8개 이하면 전부 펼쳐 둔다. 9개 이상이면 전부 접힌 채로 시작한다.
$openAttr = ""
if ($count -le 8) { $openAttr = " open" }

$listLines = New-Object System.Collections.Generic.List[string]
if ($count -eq 0) {
    $listLines.Add('<p class="empty">아직 페이지가 없다.</p>')
} else {
    foreach ($c in $catOrder) {
        $items = $groups[$c]
        $listLines.Add('<details class="cat" data-cat="' + (Escape-Html $c) + '"' + $openAttr + '>')
        $listLines.Add('<summary><span class="chev"></span>' + (Escape-Html $c) + '<span class="n">' + $items.Count + '</span></summary>')
        $listLines.Add('<ul class="toc">')
        foreach ($p in $items) {
            $href = Get-HrefName $p.FileName
            $listLines.Add('<li><a href="pages/' + $href + '?v=' + $p.Version + '">')
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
        $listLines.Add('</details>')
    }
}

$catCount = $catOrder.Count

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

# 펼친 상태를 localStorage 에 기억하는 스크립트. 서버 없이 정적으로 동작한다.
$openScript = @(
    '<script>',
    '(function(){',
    "  var KEY = 'ue-notes-open';",
    '  var saved = {};',
    "  try { saved = JSON.parse(localStorage.getItem(KEY) || '{}'); } catch (e) {}",
    "  var list = document.querySelectorAll('details.cat');",
    '  Array.prototype.forEach.call(list, function(d){',
    "    var k = d.getAttribute('data-cat');",
    '    if (Object.prototype.hasOwnProperty.call(saved, k)) { d.open = !!saved[k]; }',
    "    d.addEventListener('toggle', function(){",
    '      saved[k] = d.open;',
    '      try { localStorage.setItem(KEY, JSON.stringify(saved)); } catch (e) {}',
    '    });',
    '  });',
    '})();',
    '</script>'
)

$outLines = New-Object System.Collections.Generic.List[string]
foreach ($line in $template) {
    if ($line -eq '<!-- LIST -->') {
        foreach ($l in $listLines) { $outLines.Add($l) }
    } elseif ($line -eq '</body>') {
        foreach ($l in $openScript) { $outLines.Add($l) }
        $outLines.Add($line)
    } else {
        $outLines.Add($line)
    }
}

$text = ($outLines -join "`n") + "`n"
[System.IO.File]::WriteAllText($indexPath, $text, $utf8)

Write-Host "[목차] index.html 생성 — 페이지 ${count}개, 분류 ${catCount}개" -ForegroundColor Green
exit 0
