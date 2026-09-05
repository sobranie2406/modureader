# Pinned upstream compiler; only installs on disposable GitHub runners.
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true') { throw 'Run this helper only in GitHub Actions' }
$download = Join-Path $env:RUNNER_TEMP 'modu-innosetup-6.7.3.exe'
$install = Join-Path $env:RUNNER_TEMP 'ModuInnoSetup'
Invoke-WebRequest 'https://github.com/jrsoftware/issrc/releases/download/is-6_7_3/innosetup-6.7.3.exe' -OutFile $download
if ((Get-FileHash $download -Algorithm SHA256).Hash.ToLower() -ne '9c73c3bae7ed48d44112a0f48e66742c00090bdb5bef71d9d3c056c66e97b732') {
    throw 'Inno Setup compiler checksum mismatch'
}
$process = Start-Process -FilePath $download -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', "/DIR=`"$install`"") -Wait -PassThru
if ($process.ExitCode -ne 0) { throw "Compiler installation failed: $($process.ExitCode)" }
if (!(Test-Path (Join-Path $install 'ISCC.exe'))) { throw 'Missing ISCC.exe' }
$install | Out-File -FilePath $env:GITHUB_PATH -Encoding utf8 -Append
