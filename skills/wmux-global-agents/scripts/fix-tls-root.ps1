<#
.SYNOPSIS
  Adds ONE public root certificate (ISRG Root X1, Let's Encrypt) to LocalMachine\Root.
  Needed on PCs where Windows root auto-update is disabled by policy and GitHub release downloads
  (winget, gh, ...) fail with "untrusted root" / 0x80072f0d.

  Safety: the certificate is taken from Microsoft's own Windows Update root list and is installed
  ONLY if both its SHA-1 and SHA-256 match the well-known values and it is self-signed.
  Must run elevated (guide.ps1 starts it through a UAC prompt). ASCII-only on purpose.
#>
param([string]$LogPath = (Join-Path $env:TEMP 'wmux-agent-bootstrap-tls-fix.log'))
$ErrorActionPreference = 'Stop'
function Log($m) { ("{0} {1}" -f (Get-Date).ToString('s'), $m) | Out-File -FilePath $LogPath -Append -Encoding utf8 }
Remove-Item $LogPath -ErrorAction SilentlyContinue
$work = Join-Path $env:TEMP 'wmux-agent-bootstrap-isrg'
try {
    $wantSha1   = 'CABD2A79A1076A31F21D253635CB039D4329A5E8'
    $wantSha256 = '96BCEC06264976F37460779ACF28C5A7CFE8A3C0AAE11A8FFCEE05C0BDDF08C6'
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) { throw 'not elevated (administrator rights required)' }
    New-Item -ItemType Directory -Force $work | Out-Null

    $sst = Join-Path $work 'roots.sst'
    Remove-Item $sst -ErrorAction SilentlyContinue
    $out = & certutil.exe -generateSSTFromWU $sst 2>&1 | Out-String
    if (-not (Test-Path $sst)) { throw "could not download Windows Update root list: $out" }

    $col = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
    $col.Import($sst)
    $hit = @($col | Where-Object { $_.Thumbprint -eq $wantSha1 })
    if ($hit.Count -ne 1) { throw "ISRG Root X1 not found in Windows Update list (matches=$($hit.Count))" }
    $c = $hit[0]

    $der = Join-Path $work 'isrgrootx1.der'
    [IO.File]::WriteAllBytes($der, $c.Export('Cert'))
    $sha256 = (Get-FileHash $der -Algorithm SHA256).Hash
    if ($sha256 -ne $wantSha256)  { throw 'SHA256 mismatch - refusing to install' }
    if ($c.Subject -ne $c.Issuer) { throw 'not a self-signed root - refusing to install' }

    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store('Root', 'LocalMachine')
    $store.Open('ReadWrite')
    $already = @($store.Certificates | Where-Object { $_.Thumbprint -eq $wantSha1 }).Count
    if ($already -eq 0) { $store.Add($c); Log 'INSTALLED ISRG Root X1 into LocalMachine\Root' } else { Log 'already installed' }
    $store.Close()
    Log 'RESULT=OK'
} catch {
    Log ('RESULT=FAIL ' + $_.Exception.Message)
}
