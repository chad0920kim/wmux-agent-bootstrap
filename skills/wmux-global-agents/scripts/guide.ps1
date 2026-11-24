<#
  guide.ps1 - 사람을 위한 한국어 대화형 안내 (LLM 실행용이 아님: LLM은 setup.ps1 -Json 을 쓰세요)
  이 파일은 한글이 들어 있어 UTF-8 BOM 으로 저장되어야 Windows PowerShell 5.1 에서 깨지지 않습니다.
#>
[CmdletBinding()]
param(
    [string]$HomeDir = $env:USERPROFILE,
    [switch]$TestMode,          # 테스트용: PATH/프로필/실행정책은 건드리지 않음
    [switch]$SimulateNoAgents   # 테스트용: 에이전트가 하나도 없는 상황을 흉내냄
)
$ErrorActionPreference = 'Stop'
$here   = Split-Path -Parent $MyInvocation.MyCommand.Path
$setup  = Join-Path $here 'setup.ps1'
$fixTls = Join-Path $here 'fix-tls-root.ps1'
$ps5    = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Say([string]$t, [string]$c = 'White') { Write-Host $t -ForegroundColor $c }

function Ask-YesNo([string]$q) {
    while ($true) {
        $a = (Read-Host "$q [y/n]").Trim().ToLowerInvariant()
        if ($a -in @('y', 'yes', 'ㅛ', '예', '네')) { return $true }
        if ($a -in @('n', 'no', 'ㅜ', '아니오', '아니요')) { return $false }
        Say '  y(예) 또는 n(아니오)로 입력해 주세요.' Yellow
    }
}

function Ask-Choice([string]$q, [string[]]$valid, [string]$default) {
    while ($true) {
        $a = (Read-Host $q).Trim()
        if (-not $a -and $default) { return $default }
        if ($valid -contains $a) { return $a }
        Say ('  ' + ($valid -join ', ') + ' 중에서 입력해 주세요.') Yellow
    }
}

function Invoke-Setup([string[]]$extra) {
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $setup, '-Json', '-HomeDir', $HomeDir) + $extra
    if ($TestMode) { $a += '-SkipPath', '-SkipProfile', '-SkipExecutionPolicy' }
    $out = (& $ps5 @a | Out-String)
    try { $r = $out | ConvertFrom-Json } catch { Say '설정 스크립트 출력을 해석하지 못했어요. 원본 출력:' Red; Write-Host $out; throw }
    if ($SimulateNoAgents) { $r.agents = @(); $r.errors = @('No agent CLI found') }
    return $r
}

function Get-Found($r) { return @($r.agents | Where-Object { $_.found }) }

# GitHub 파일 서버 인증서를 이 PC가 신뢰하는지 검사 (HTTP 오류 응답은 TLS 정상으로 본다)
function Test-Tls([string]$url) {
    try { Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 20 | Out-Null; return 'ok' }
    catch {
        if ($_.Exception.Response) { return 'ok' }
        if ($_.Exception.Message -match '트러스트|trust|SSL/TLS|인증서|certificate') { return 'untrusted' }
        return 'other'
    }
}

function Offer-TlsFix {
    Say ''
    Say '이 PC가 GitHub 다운로드 서버의 인증서를 신뢰하지 못하고 있어요.' Yellow
    Say '(원인: Let''s Encrypt 루트 인증서 "ISRG Root X1"이 없고, Windows 루트 자동 갱신이 꺼져 있음)'
    Say 'Microsoft 공식 루트 목록에서 이 인증서 1개만 가져와 지문을 확인한 뒤 설치할 수 있어요.'
    Say '관리자 권한 확인 창(UAC)이 뜨면 "예"를 눌러 주세요.'
    if (-not (Ask-YesNo '지금 해결할까요?')) { Say '건너뛰었어요. 자세한 방법은 docs\TROUBLESHOOTING.md 를 보세요.'; return $false }
    $log = Join-Path $env:TEMP 'wmux-agent-bootstrap-tls-fix.log'
    Remove-Item $log -ErrorAction SilentlyContinue
    try {
        Start-Process -FilePath $ps5 -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$fixTls`"", '-LogPath', "`"$log`""
    } catch { Say '관리자 권한 승인이 취소되었어요.' Yellow; return $false }
    if ((Test-Path $log) -and ((Get-Content $log -Raw) -match 'RESULT=OK')) { Say '인증서 설치 완료!' Green; return $true }
    Say '인증서 설치에 실패했어요. 로그:' Red
    if (Test-Path $log) { Get-Content $log | ForEach-Object { Say "  $_" } }
    return $false
}

function Install-Agents {
    Say ''
    Say '설치된 AI 에이전트(claude / grok / agy)를 찾지 못했어요.' Yellow
    Say '이 도구는 에이전트가 하나 이상 있어야 해요. Claude Code는 여기서 바로 설치할 수 있어요.'
    Say '(Grok, Antigravity는 각 공식 안내대로 설치한 뒤 시작하기.bat을 다시 실행해 주세요.)'
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Say 'winget을 찾을 수 없어요. Microsoft Store의 "앱 설치 관리자"를 업데이트하거나 에이전트를 직접 설치해 주세요.' Red
        return $false
    }
    if (-not (Ask-YesNo 'Claude Code를 지금 설치할까요? (winget install Anthropic.ClaudeCode)')) { return $false }
    & winget install --id Anthropic.ClaudeCode -e --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        Say '설치에 실패했어요. 네트워크 인증서 문제인지 확인할게요...' Yellow
        $t = Test-Tls 'https://release-assets.githubusercontent.com'
        if ($t -eq 'untrusted') {
            if (Offer-TlsFix) {
                Say '다시 설치를 시도합니다...'
                & winget install --id Anthropic.ClaudeCode -e --accept-package-agreements --accept-source-agreements
                if ($LASTEXITCODE -ne 0) { Say '여전히 실패했어요. docs\TROUBLESHOOTING.md 를 확인해 주세요.' Red; return $false }
            } else { return $false }
        } else {
            Say '인증서 문제는 아닌 것 같아요. 인터넷 연결 또는 회사/학교 네트워크 제한을 확인해 주세요.' Red
            return $false
        }
    }
    Say '설치가 끝났어요. 다시 찾아볼게요.' Green
    return $true
}

# ============================================================== 시작
try { Clear-Host } catch { }
Say '==============================================' Cyan
Say '  wmux 에이전트 초기 설정 도우미' Cyan
Say '==============================================' Cyan
Say '이 도우미가 하는 일:'
Say '  1) claude / grok / agy 를 어느 폴더, 어느 탭에서든 실행할 수 있게 설정'
Say '  2) (선택) 모든 에이전트가 항상 한국어로 답하도록 전역 규칙 추가'
Say '바꾸기 전에 항상 내용을 보여드리고 허락을 받아요. 바뀌는 파일은 자동 백업돼요.'
Say ''

Say '[1/4] 설치된 에이전트를 찾는 중...' Cyan
$r = Invoke-Setup @('-SkipVerify')
$found = Get-Found $r
if ($found.Count -eq 0 -or $SimulateNoAgents) {
    $found = @()
    if (Install-Agents) {
        $r = Invoke-Setup @('-SkipVerify')
        $found = Get-Found $r
    }
    if ($found.Count -eq 0) {
        Say ''
        Say '에이전트를 찾지 못해 여기서 마칩니다. 에이전트를 설치한 뒤 시작하기.bat 을 다시 실행해 주세요.' Yellow
        exit 0
    }
}
foreach ($a in $found) { $ver = $(if ($a.version) { $a.version } else { '설치됨' }); Say ("  ✔ {0}  {1}" -f $a.name, $ver) Green }
foreach ($a in @($r.agents | Where-Object { -not $_.found })) { Say ("  - {0}  (설치 안 됨)" -f $a.name) DarkGray }

Say ''
Say '[2/4] 에이전트 기본 응답 언어를 정할까요?' Cyan
Say '  1) 한국어   2) English   3) 건너뛰기(기본)'
$c = Ask-Choice '번호를 입력하세요 (그냥 Enter = 건너뛰기)' @('1', '2', '3') '3'
$lang = @{ '1' = 'ko'; '2' = 'en'; '3' = 'none' }[$c]

Say ''
Say '[3/4] 바뀔 내용을 확인하는 중... (아직 아무것도 바꾸지 않았어요)' Cyan
$r = Invoke-Setup @('-SkipVerify', '-Language', $lang)
if ($r.errors -and @($r.errors).Count -gt 0) { foreach ($e in $r.errors) { Say "  오류: $e" Red }; exit 2 }

$todo = New-Object System.Collections.Generic.List[string]
if ($r.path -and $r.path.status -eq 'would-add') {
    $todo.Add("에이전트 폴더 $(@($r.path.missingDirs).Count)개를 사용자 PATH에 추가 (어느 폴더에서든 실행 가능)")
}
foreach ($p in @($r.profile)) { if ($p.status -like 'would-*') { $todo.Add("새 터미널 탭이 항상 최신 PATH를 쓰도록 PowerShell 프로필에 설정 추가") } }
if ($r.executionPolicy) {
    switch ($r.executionPolicy.status) {
        'would-set-RemoteSigned'            { $todo.Add('PowerShell 스크립트 실행 정책을 RemoteSigned로 변경 (현재 사용자만, 프로필 로드에 필요)') }
        'blocked-by-group-policy'           { Say '  참고: 실행 정책이 조직 정책으로 고정돼 있어 건드리지 않아요.' Yellow }
        'allsigned-needs-human-decision'    { Say '  참고: 실행 정책이 AllSigned라 건드리지 않아요. 필요하면 직접 결정해 주세요.' Yellow }
    }
}
foreach ($x in @($r.rules)) { if ($x.status -like 'would-*') { $todo.Add("[$($x.agent)] 기본 응답 언어 규칙 추가 → $($x.file)") } }

if (-not $r.changesPending -or $todo.Count -eq 0) {
    Say ''
    Say '이미 모두 설정되어 있어요. 할 일이 없습니다. 🎉' Green
    exit 0
}
Say '다음 변경을 적용할 예정이에요:'
foreach ($t in $todo) { Say "  • $t" }
Say ''
Say '※ 기존 내용은 지우지 않고 "추가"만 해요. 바뀌는 파일은 ~\.wmux-agent-bootstrap\backups\ 에 백업돼요.' DarkGray

Say ''
Say '[4/4] 적용' Cyan
if (-not (Ask-YesNo '위 내용을 적용할까요?')) { Say '취소했어요. 아무것도 바뀌지 않았습니다.'; exit 0 }

$r = Invoke-Setup @('-Apply', '-Language', $lang)
Say ''
if ($r.errors -and @($r.errors).Count -gt 0) { foreach ($e in $r.errors) { Say "오류: $e" Red }; exit 2 }
if ($r.verify -and -not $r.verify.allFound) {
    Say '적용은 했지만 새 창에서 일부 에이전트가 확인되지 않았어요:' Red
    foreach ($v in @($r.verify.agents)) { Say ("  {0}: {1}" -f $v.agent, $(if ($v.foundInFreshShell) { '확인됨' } else { '찾지 못함' })) }
    if ($r.verify.shellStderr) { Say "  메시지: $($r.verify.shellStderr)" DarkGray }
    Say 'docs\TROUBLESHOOTING.md 를 확인해 주세요.'
    exit 2
}
Say '✔ 설정이 끝났어요! (다른 폴더에서 새 창을 띄워 에이전트가 실제로 실행되는지까지 확인했어요)' Green
Say ''
Say '마지막으로 이것만 해 주세요:' Cyan
Say '  • 이미 열려 있는 탭: 새 탭을 열거나, 그 탭에서  . $PROFILE.CurrentUserAllHosts  를 한 번 입력'
Say '  • 이미 대화 중인 에이전트: 껐다가 다시 실행해야 새 언어 규칙을 읽어요'
Say '  • 확인: 아무 폴더에서  claude --version  /  grok --version  /  agy --version'
exit 0
