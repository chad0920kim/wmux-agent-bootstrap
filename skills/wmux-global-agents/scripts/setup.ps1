<#
.SYNOPSIS
  Make AI coding-agent CLIs (claude, grok, agy, wmux) callable from any folder and any
  wmux pane, and optionally install a global "reply language" rule for each agent.

.DESCRIPTION
  Default mode is CHECK (read-only). Nothing is changed unless -Apply is given.
  Safe to re-run: every change is idempotent, only ADDS (never removes PATH entries,
  never overwrites user content), and backs up every file it touches.

  What -Apply can do (each can be skipped):
    1. Append missing agent folders to the persistent USER PATH  (-SkipPath)
    2. Add a managed Sync-AgentPath block to the PowerShell profile (-SkipProfile)
    3. Set CurrentUser execution policy to RemoteSigned if it is Restricted (-SkipExecutionPolicy)
    4. Add a managed language-rule block to each detected agent's global rule file (-Language)
    5. Verify from a fresh shell started in another folder with a minimal PATH (-SkipVerify)

  This file is intentionally ASCII-only so Windows PowerShell 5.1 parses it correctly.
  Non-ASCII text (the language rules) lives in ..\templates\*.md (UTF-8).

.PARAMETER Apply     Actually make changes. Without it, only report what WOULD change.
.PARAMETER Language  none | ko | en  - which global language rule to install. Default none.
.PARAMETER RulesFile Path to your own rule text (UTF-8). Overrides -Language templates.
.PARAMETER Json      Print one JSON report (recommended when an LLM runs this script).
.PARAMETER HomeDir   Override home folder (for tests). Default: %USERPROFILE%.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File setup.ps1 -Json -Language ko
  powershell -NoProfile -ExecutionPolicy Bypass -File setup.ps1 -Json -Language ko -Apply
#>
[CmdletBinding()]
param(
    [switch]$Apply,
    [ValidateSet('none', 'ko', 'en')][string]$Language = 'none',
    [string]$RulesFile,
    [string]$HomeDir = $env:USERPROFILE,
    [switch]$SkipPath,
    [switch]$SkipProfile,
    [switch]$SkipExecutionPolicy,
    [switch]$SkipVerify,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$Tool       = 'wmux-agent-bootstrap'
$Stamp      = (Get-Date).ToString('yyyyMMdd-HHmmss')
$BackupRoot = Join-Path $HomeDir ".$Tool\backups\$Stamp"
$TemplateDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'templates'
$Local      = $env:LOCALAPPDATA
$WinGetPkgs = Join-Path $Local 'Microsoft\WinGet\Packages'
$WinGetLinks = Join-Path $Local 'Microsoft\WinGet\Links'

$report = [ordered]@{
    mode            = $(if ($Apply) { 'apply' } else { 'check' })
    agents          = @()
    path            = $null
    profile         = @()
    executionPolicy = $null
    rules           = @()
    verify          = $null
    errors          = @()
    changesPending  = $false
    backupDir       = $null
    nextAction      = ''
}

# ----------------------------------------------------------------- helpers
function Norm([string]$p) {
    if (-not $p) { return '' }
    return [Environment]::ExpandEnvironmentVariables($p.Trim()).TrimEnd('\').ToLowerInvariant()
}

function Invoke-Quick([string]$File, [string[]]$ArgList, [int]$TimeoutSec = 15, [hashtable]$Env, [string]$WorkDir) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $File
    $psi.Arguments = ($ArgList -join ' ')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    if ($WorkDir) { $psi.WorkingDirectory = $WorkDir }
    if ($Env) { foreach ($k in $Env.Keys) { $psi.EnvironmentVariables[$k] = $Env[$k] } }
    $p = [System.Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEndAsync()
    $err = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        try { $p.Kill() } catch {}
        return @{ ok = $false; out = ''; err = 'timeout'; code = -1 }
    }
    return @{ ok = ($p.ExitCode -eq 0); out = $out.Result.Trim(); err = $err.Result.Trim(); code = $p.ExitCode }
}

function Backup-File([string]$path) {
    if (Test-Path -LiteralPath $path) {
        New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
        $dest = Join-Path $BackupRoot (($path -replace '[:\\\/]', '_') + '.bak')
        Copy-Item -LiteralPath $path -Destination $dest -Force
        $report.backupDir = $BackupRoot
    }
}

# Insert or replace a managed block. Never touches text outside the markers.
function Set-ManagedBlock([string]$Path, [string]$Tag, [string]$Body, [string]$Style, [bool]$Bom) {
    if ($Style -eq 'md') { $b = "<!-- >>> $Tool`:$Tag >>> -->"; $e = "<!-- <<< $Tool`:$Tag <<< -->" }
    else                 { $b = "# >>> $Tool`:$Tag >>>";        $e = "# <<< $Tool`:$Tag <<<" }
    $block = $b + "`r`n" + $Body.Trim() + "`r`n" + $e
    $existing = ''
    $existed = Test-Path -LiteralPath $Path
    if ($existed) { $existing = [IO.File]::ReadAllText($Path) }
    $pattern = '(?s)' + [regex]::Escape($b) + '.*?' + [regex]::Escape($e)
    $hasBlock = [regex]::IsMatch($existing, $pattern)
    # Same text already present without our markers (e.g. added by hand earlier): do not duplicate.
    $norm = { param($s) ($s -replace '\s+', ' ').Trim() }
    if (-not $hasBlock -and $existing.Trim().Length -gt 0 -and (& $norm $existing).Contains((& $norm $Body))) { return 'already-present' }
    if ($hasBlock) {
        $new = [regex]::Replace($existing, $pattern, { param($m) $block })
    } elseif ($existing.Trim().Length -gt 0) {
        $new = $existing.TrimEnd() + "`r`n`r`n" + $block + "`r`n"
    } else {
        $new = $block + "`r`n"
    }
    if ($new -ceq $existing) { return 'unchanged' }
    $verb = $(if (-not $existed) { 'create' } elseif ($hasBlock) { 'update' } else { 'append' })
    if ($Apply) {
        Backup-File $Path
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
        [IO.File]::WriteAllText($Path, $new, (New-Object System.Text.UTF8Encoding($Bom)))
        return @{ create = 'created'; update = 'updated'; append = 'appended' }[$verb]
    }
    $report.changesPending = $true
    return 'would-' + $verb
}

# ------------------------------------------------------------ 1. detect agents
$agentDefs = @(
    @{ name = 'claude'; exe = 'claude'; rule = (Join-Path $HomeDir '.claude\CLAUDE.md');
       dirs = @((Join-Path $HomeDir '.local\bin'), (Join-Path $WinGetPkgs 'Anthropic.ClaudeCode*'), $WinGetLinks) },
    @{ name = 'grok';   exe = 'grok';   rule = (Join-Path $HomeDir '.grok\rules\language.md');
       dirs = @((Join-Path $HomeDir '.grok\bin')) },
    @{ name = 'agy';    exe = 'agy';    rule = (Join-Path $HomeDir '.gemini\config\GEMINI.md');
       dirs = @((Join-Path $Local 'agy\bin')) },
    @{ name = 'wmux';   exe = 'wmux';   rule = $null;
       dirs = @((Join-Path $Local 'wmux\bin')) }
)

$detected = @()
foreach ($d in $agentDefs) {
    $dir = $null
    $cmd = Get-Command $d.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { $dir = Split-Path -Parent $cmd.Source }
    else {
        foreach ($cand in $d.dirs) {
            foreach ($c in @(Get-Item -Path $cand -ErrorAction SilentlyContinue)) {
                foreach ($ext in 'exe', 'cmd') {
                    if (Test-Path -LiteralPath (Join-Path $c.FullName "$($d.exe).$ext")) { $dir = $c.FullName; break }
                }
                if ($dir) { break }
            }
            if ($dir) { break }
        }
    }
    $version = $null
    if ($dir -and $d.name -ne 'wmux') {
        $exePath = @('exe', 'cmd' | ForEach-Object { Join-Path $dir "$($d.exe).$_" } | Where-Object { Test-Path -LiteralPath $_ })[0]
        try { $r = Invoke-Quick $exePath @('--version') 15; $version = ($r.out -split "`r?`n")[0] } catch { $version = 'unknown' }
    }
    $entry = [ordered]@{ name = $d.name; found = [bool]$dir; dir = $dir; version = $version; ruleFile = $d.rule }
    $report.agents += [pscustomobject]$entry
    if ($dir) { $detected += [pscustomobject]$entry }
}
if ($detected.Count -eq 0) {
    $report.errors += 'No agent CLI (claude/grok/agy/wmux) found. Install at least one first.'
}

# ------------------------------------------------------------ 2. persistent USER PATH
if (-not $SkipPath -and $detected.Count -gt 0) {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    $raw = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    $have = @{}
    foreach ($e in ($raw -split ';')) { if ($e.Trim()) { $have[(Norm $e)] = $true } }
    # Machine PATH also counts as "already there"
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    foreach ($e in ($machine -split ';')) { if ($e.Trim()) { $have[(Norm $e)] = $true } }
    $missing = @($detected | ForEach-Object { $_.dir } | Sort-Object -Unique | Where-Object { -not $have.ContainsKey((Norm $_)) })
    $status = 'unchanged'
    if ($missing.Count -gt 0) {
        if ($Apply) {
            New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
            Set-Content -LiteralPath (Join-Path $BackupRoot 'user-path.before.txt') -Value $raw -Encoding UTF8
            $report.backupDir = $BackupRoot
            $new = $(if ($raw.Trim()) { $raw.TrimEnd(';') + ';' + ($missing -join ';') } else { $missing -join ';' })
            $key.SetValue('Path', $new, [Microsoft.Win32.RegistryValueKind]::ExpandString)
            # Broadcast WM_SETTINGCHANGE so Explorer / new terminals pick it up
            [Environment]::SetEnvironmentVariable("${Tool}_ping", '1', 'User')
            [Environment]::SetEnvironmentVariable("${Tool}_ping", $null, 'User')
            $status = 'added'
        } else { $status = 'would-add'; $report.changesPending = $true }
    }
    $key.Close()
    $report.path = [ordered]@{ status = $status; missingDirs = $missing }
}

# ------------------------------------------------------------ 3. PowerShell profile
if (-not $SkipProfile -and $detected.Count -gt 0) {
    $docs = [Environment]::GetFolderPath('MyDocuments')   # follows OneDrive folder redirection
    $profiles = @((Join-Path $docs 'WindowsPowerShell\profile.ps1'))
    if (Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue) {
        $profiles += (Join-Path $docs 'PowerShell\profile.ps1')
    }
    $body = @'
function global:Sync-AgentPath {
    # Append any Machine/User PATH entries missing from this session (never reorders or removes).
    $seen = @{}
    $list = New-Object System.Collections.Generic.List[string]
    $sources = @($env:Path,
                 [Environment]::GetEnvironmentVariable('Path', 'Machine'),
                 [Environment]::GetEnvironmentVariable('Path', 'User'))
    foreach ($raw in $sources) {
        if (-not $raw) { continue }
        foreach ($e in ($raw -split ';')) {
            $t = $e.Trim()
            if (-not $t) { continue }
            $k = $t.TrimEnd('\').ToLowerInvariant()
            if (-not $seen.ContainsKey($k)) { $seen[$k] = $true; $list.Add($t) }
        }
    }
    $env:Path = $list -join ';'
}
Sync-AgentPath
'@
    foreach ($pp in $profiles) {
        $st = Set-ManagedBlock -Path $pp -Tag 'path' -Body $body -Style 'ps1' -Bom $true
        $report.profile += [pscustomobject][ordered]@{ file = $pp; status = $st }
    }
}

# ------------------------------------------------------------ 4. execution policy
if (-not $SkipExecutionPolicy) {
    $eff = [string](Get-ExecutionPolicy)
    $gpo = ([string](Get-ExecutionPolicy -Scope MachinePolicy) -ne 'Undefined') -or ([string](Get-ExecutionPolicy -Scope UserPolicy) -ne 'Undefined')
    $cu  = [string](Get-ExecutionPolicy -Scope CurrentUser)
    $status = 'ok'
    # Process-scope Bypass (our own launch flag) must not hide a Restricted persistent policy.
    $persistent = @('CurrentUser', 'LocalMachine' | ForEach-Object { [string](Get-ExecutionPolicy -Scope $_) } | Where-Object { $_ -ne 'Undefined' })
    $needs = ($persistent.Count -eq 0) -or ($persistent -contains 'Restricted')
    if ($gpo)                              { $status = 'blocked-by-group-policy' }
    elseif ($persistent -contains 'AllSigned') { $status = 'allsigned-needs-human-decision' }
    elseif ($needs) {
        if ($Apply) { Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force; $status = 'set-RemoteSigned' }
        else        { $status = 'would-set-RemoteSigned'; $report.changesPending = $true }
    }
    $report.executionPolicy = [ordered]@{ effective = $eff; currentUser = $cu; status = $status }
}

# ------------------------------------------------------------ 5. global language rules
$ruleText = $null
if ($RulesFile) { $ruleText = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $RulesFile).Path) }
elseif ($Language -ne 'none') {
    $tpl = Join-Path $TemplateDir "rules.$Language.md"
    if (Test-Path -LiteralPath $tpl) { $ruleText = [IO.File]::ReadAllText($tpl) }
    else { $report.errors += "Rule template not found: $tpl" }
}
if ($ruleText) {
    foreach ($a in $detected) {
        if (-not $a.ruleFile) { continue }
        $st = Set-ManagedBlock -Path $a.ruleFile -Tag 'language' -Body $ruleText -Style 'md' -Bom $false
        $report.rules += [pscustomobject][ordered]@{ agent = $a.name; file = $a.ruleFile; status = $st }
    }
}

# ------------------------------------------------------------ 6. verify in a FRESH shell
# Fresh powershell.exe, started in another folder, with a deliberately minimal PATH.
# It loads the profile, so this proves new tabs will find the agents.
if (-not $SkipVerify -and $detected.Count -gt 0) {
    $ps5 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $names = ($detected | ForEach-Object { "'" + $_.name + "'" }) -join ','
    $cmd = "foreach(`$n in $names){`$c=Get-Command `$n -CommandType Application -ErrorAction SilentlyContinue|Select-Object -First 1; if(`$c){Write-Output (`$n+'='+`$c.Source)}else{Write-Output (`$n+'=MISSING')}}"
    $minPath = "$env:SystemRoot\System32;$env:SystemRoot;$env:SystemRoot\System32\WindowsPowerShell\v1.0"
    $r = Invoke-Quick $ps5 @('-NoLogo', '-ExecutionPolicy', 'RemoteSigned', '-Command', ('"' + ($cmd -replace '"', '\"') + '"')) 40 @{ Path = $minPath } $env:TEMP
    $res = @{}
    foreach ($line in ($r.out -split "`r?`n")) { if ($line -match '^(\w+)=(.*)$') { $res[$Matches[1]] = $Matches[2] } }
    $per = @()
    foreach ($a in $detected) {
        $ok = $res.ContainsKey($a.name) -and $res[$a.name] -ne 'MISSING'
        $per += [pscustomobject][ordered]@{ agent = $a.name; foundInFreshShell = $ok }
    }
    $report.verify = [ordered]@{
        freshShellCwd = $env:TEMP
        allFound      = (@($per | Where-Object { -not $_.foundInFreshShell }).Count -eq 0)
        agents        = $per
        shellStderr   = $r.err
    }
}

# ------------------------------------------------------------ next action hint (for the LLM)
if ($report.errors.Count -gt 0) {
    $report.nextAction = 'STOP. Show the errors to the user. Do not improvise fixes.'
} elseif (-not $Apply -and $report.changesPending) {
    $report.nextAction = 'Summarize the pending changes to the user, ask for confirmation, then re-run the same command with -Apply.'
} elseif (-not $Apply) {
    $report.nextAction = 'Nothing to change. Tell the user the setup is already complete.'
} elseif ($report.verify -and -not $report.verify.allFound) {
    $report.nextAction = 'Verification failed. Show the report to the user. Do NOT re-run blindly; see Troubleshooting in SKILL.md.'
} else {
    $report.nextAction = 'Done. Tell the user to open a NEW terminal tab (or run: . $PROFILE.CurrentUserAllHosts) in already-open tabs.'
}

# ------------------------------------------------------------ output
if ($Json) {
    $report | ConvertTo-Json -Depth 8
} else {
    Write-Host ("[{0}] mode={1}" -f $Tool, $report.mode)
    foreach ($a in $report.agents) { Write-Host ("  agent {0,-7} {1}  {2}" -f $a.name, $(if ($a.found) { 'FOUND' } else { 'missing' }), $a.dir) }
    if ($report.path)            { Write-Host ("  user PATH: {0} {1}" -f $report.path.status, ($report.path.missingDirs -join '; ')) }
    foreach ($p in $report.profile) { Write-Host ("  profile: {0} -> {1}" -f $p.status, $p.file) }
    if ($report.executionPolicy) { Write-Host ("  execution policy: {0} (effective {1})" -f $report.executionPolicy.status, $report.executionPolicy.effective) }
    foreach ($r in $report.rules) { Write-Host ("  rule[{0}]: {1} -> {2}" -f $r.agent, $r.status, $r.file) }
    if ($report.verify)          { Write-Host ("  fresh-shell verify: allFound={0}" -f $report.verify.allFound) }
    foreach ($e in $report.errors) { Write-Host "  ERROR: $e" }
    Write-Host ("  next: {0}" -f $report.nextAction)
}
if ($report.errors.Count -gt 0 -or ($report.verify -and -not $report.verify.allFound -and $Apply)) { exit 2 }
exit 0
