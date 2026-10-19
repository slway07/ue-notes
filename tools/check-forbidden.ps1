<#
.SYNOPSIS
  배포 직전 금칙어 게이트. 저장소의 텍스트 파일을 금칙어 패턴 목록으로 검사하고, 저장소 로컬 커밋 신원을 확인한다.
.DESCRIPTION
  종료 코드
    0  통과
    1  금칙어 발견, 읽을 수 없는 파일, 커밋 신원 위반, 또는 검사 중 오류 (배포 중단)
    2  설정 오류 (패턴 파일 없음, 패턴 0개, 정규식 컴파일 실패, 검사 루트 없음)
  fail closed: 판단이 애매하면 통과가 아니라 실패로 끝낸다.
#>
[CmdletBinding()]
param(
    [string]$Root = "D:\Work\Notes",
    [string]$PatternFile = (Join-Path $env:USERPROFILE ".claude\notes-forbidden-patterns.txt")
)

$ErrorActionPreference = "Stop"

function Show-Fail([string]$msg) {
    Write-Host $msg -ForegroundColor Red
}

# 루트 기준 상대 경로. 루트 밑이 아니면 자르지 않고 전체 경로를 그대로 돌려준다
# (경로 형태가 어긋났을 때 앞글자를 잘라먹고 엉뚱한 경로를 보고하는 것보다 낫다).
function Get-RelPath([string]$full, [string]$root) {
    if ($full.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($root.Length + 1)
    }
    return $full
}

# ---------------------------------------------------------------
# 1. 금칙어 목록 로드
# ---------------------------------------------------------------
if (-not (Test-Path -LiteralPath $PatternFile -PathType Leaf)) {
    Show-Fail "[오류] 금칙어 목록 파일이 없습니다: $PatternFile"
    Show-Fail "       파일이 없으면 검사할 수 없으므로 배포를 중단합니다."
    exit 2
}

try {
    $rawLines = @(Get-Content -LiteralPath $PatternFile -Encoding UTF8 -ErrorAction Stop)
} catch {
    Show-Fail "[오류] 금칙어 목록을 읽을 수 없습니다: $PatternFile"
    Show-Fail "       $($_.Exception.Message)"
    exit 2
}

$patterns = New-Object System.Collections.Generic.List[object]
for ($i = 0; $i -lt $rawLines.Count; $i++) {
    $line = ([string]$rawLines[$i]).Trim()
    if ($line -eq "" -or $line.StartsWith("#")) { continue }

    # 'cs:' 접두사가 붙은 줄은 대소문자를 구분한다.
    # 기본이 IgnoreCase 인 이유: 같은 낱말의 대소문자 변형을 한 줄로 모두 잡기 위해서다.
    # 'cs:' 는 대문자 위치 자체가 패턴의 의미인 식별자 접두사에만 쓴다 —
    # 그런 패턴을 IgnoreCase 로 두면 평범한 영어 단어까지 걸려 게이트가 무력해진다.
    # (주의: 이 파일에 금칙어를 예시로라도 적으면 게이트가 자기 자신을 차단한다. 실제로 한 번 걸렸다.)
    $opts = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    $expr = $line
    if ($line.StartsWith("cs:")) {
        $opts = [System.Text.RegularExpressions.RegexOptions]::None
        $expr = $line.Substring(3).Trim()
        if ($expr -eq "") {
            Show-Fail "[오류] 금칙어 목록 $($i + 1)번째 줄의 'cs:' 뒤가 비어 있습니다."
            exit 2
        }
    }

    try {
        $rx = [regex]::new($expr, $opts)
    } catch {
        Show-Fail "[오류] 금칙어 목록 $($i + 1)번째 줄의 정규식이 잘못되었습니다: '$line'"
        Show-Fail "       $($_.Exception.Message)"
        exit 2
    }
    $patterns.Add([pscustomobject]@{ Source = $line; Regex = $rx })
}

if ($patterns.Count -eq 0) {
    Show-Fail "[오류] 유효한 금칙어 패턴이 0개입니다: $PatternFile"
    Show-Fail "       빈 목록은 통과가 아니라 설정 오류로 처리합니다."
    exit 2
}

# ---------------------------------------------------------------
# 2. 검사 대상 파일 수집 (.git 디렉터리는 가지치기로 건너뜀)
# ---------------------------------------------------------------
if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    Show-Fail "[오류] 검사 루트 폴더가 없습니다: $Root"
    exit 2
}

# Resolve-Path 는 8.3 단축 이름(KIMEUN~1)을 그대로 두지만 Get-ChildItem 의 FullName 은 긴 이름으로
# 돌려주기 때문에, 루트는 자식과 같은 형태가 나오는 Get-Item 으로 구한다.
$rootFull = (Get-Item -LiteralPath $Root -Force).FullName.TrimEnd('\')
$binaryExt = @(".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico", ".woff", ".woff2",
               ".ttf", ".otf", ".pdf", ".zip", ".mp4", ".webm")

$candidates = New-Object System.Collections.Generic.List[string]
$stack = New-Object System.Collections.Generic.Stack[string]
$stack.Push($rootFull)

try {
    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        foreach ($item in (Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop)) {
            if ($item.PSIsContainer) {
                if ($item.Name -eq ".git") { continue }
                $stack.Push($item.FullName)
            } else {
                $candidates.Add($item.FullName)
            }
        }
    }
} catch {
    Show-Fail "[차단] 검사 대상 파일 목록을 만들지 못했습니다 — 배포를 중단한다"
    Show-Fail "       $($_.Exception.Message)"
    exit 1
}

$targets = New-Object System.Collections.Generic.List[string]
foreach ($full in $candidates) {
    $relPath = Get-RelPath $full $rootFull
    $fileName = [System.IO.Path]::GetFileName($full)

    # .git 디렉터리 안쪽만 제외한다.
    # .gitignore / .gitattributes / .github\ 는 GitHub 에 그대로 올라가므로 검사 대상이다.
    if ($fileName -eq ".git") { continue }
    if (("\" + $relPath) -like "*\.git\*") { continue }

    $ext = [System.IO.Path]::GetExtension($full).ToLowerInvariant()
    if ($binaryExt -contains $ext) { continue }

    $targets.Add($full)
}

# ---------------------------------------------------------------
# 3. 매칭 (줄 단위, 모든 패턴 적용)
# ---------------------------------------------------------------
$hits = New-Object System.Collections.Generic.List[object]
$readErrors = New-Object System.Collections.Generic.List[string]
$checked = 0

foreach ($full in $targets) {
    $relPath = Get-RelPath $full $rootFull

    try {
        $lines = @(Get-Content -LiteralPath $full -Encoding UTF8 -ErrorAction Stop)
    } catch {
        # 읽지 못한 파일은 검사하지 못한 것이므로 실패 처리한다.
        $readErrors.Add("$relPath  (읽을 수 없음: $($_.Exception.Message))")
        continue
    }
    $checked++

    for ($n = 0; $n -lt $lines.Count; $n++) {
        $text = [string]$lines[$n]
        foreach ($p in $patterns) {
            $m = $p.Regex.Match($text)
            if ($m.Success) {
                $hits.Add([pscustomobject]@{
                    File    = $relPath
                    Line    = $n + 1
                    Pattern = $p.Source
                    Match   = $m.Value
                })
            }
        }
    }
}

# ---------------------------------------------------------------
# 4. 커밋 신원 검사 (저장소 로컬 설정만 본다)
# ---------------------------------------------------------------
$gitIssues = New-Object System.Collections.Generic.List[string]

if (Test-Path -LiteralPath (Join-Path $rootFull ".git")) {
    $email = ""
    $name = ""

    try {
        $emailOut = @(& git -C $rootFull config --local user.email)
        $emailCode = $LASTEXITCODE
        if ($emailOut.Count -gt 0) { $email = ([string]$emailOut[-1]).Trim() }

        if ($emailCode -ne 0 -or $email -eq "") {
            $gitIssues.Add("저장소 로컬 커밋 이메일(user.email)이 비어 있거나 조회 실패(종료 코드 $emailCode)")
        } elseif ($email -notmatch '@users\.noreply\.github\.com$') {
            $gitIssues.Add("저장소 로컬 커밋 이메일이 GitHub noreply 주소가 아님")
        }

        $nameOut = @(& git -C $rootFull config --local user.name)
        $nameCode = $LASTEXITCODE
        if ($nameOut.Count -gt 0) { $name = ([string]$nameOut[-1]).Trim() }

        if ($nameCode -ne 0 -or $name -eq "") {
            $gitIssues.Add("저장소 로컬 커밋 이름(user.name)이 비어 있거나 조회 실패(종료 코드 $nameCode)")
        }
    } catch {
        $gitIssues.Add("git 명령 실행 실패: $($_.Exception.Message)")
    }
} else {
    Write-Host "git 저장소 아님 — 커밋 이메일 검사 건너뜀" -ForegroundColor Yellow
}

# ---------------------------------------------------------------
# 5. 결과 출력
# ---------------------------------------------------------------
$hitCount = $hits.Count
$problemCount = $readErrors.Count + $gitIssues.Count

if ($hitCount -eq 0 -and $problemCount -eq 0) {
    Write-Host "[OK] 금칙어 검사 통과 — 검사 파일 ${checked}개" -ForegroundColor Green
    exit 0
}

if ($hitCount -gt 0) {
    Write-Host "[차단] 금칙어 ${hitCount}건 발견 — 배포를 중단한다" -ForegroundColor Red
    foreach ($h in $hits) {
        Write-Host ("  {0}:{1}  패턴 '{2}'  ->  '{3}'" -f $h.File, $h.Line, $h.Pattern, $h.Match) -ForegroundColor Red
    }
}

if ($readErrors.Count -gt 0) {
    Write-Host "[차단] 읽을 수 없는 파일 $($readErrors.Count)건 — 검사하지 못했으므로 실패 처리한다" -ForegroundColor Red
    foreach ($e in $readErrors) {
        Write-Host "  $e" -ForegroundColor Red
    }
}

if ($gitIssues.Count -gt 0) {
    Write-Host "[차단] 커밋 신원 위반 $($gitIssues.Count)건 — 배포를 중단한다" -ForegroundColor Red
    foreach ($g in $gitIssues) {
        Write-Host "  $g" -ForegroundColor Red
    }
}

exit 1
