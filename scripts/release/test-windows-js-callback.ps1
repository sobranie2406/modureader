$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true') { throw 'Run in isolated Windows CI only' }
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$installation = & $vswhere -latest -products '*' -property installationPath
$devcmd = Join-Path $installation 'Common7\Tools\VsDevCmd.bat'
cmd /c "`"$devcmd`" -arch=x64 -host_arch=x64 && cl /std:c++17 /EHsc /Iwindows\flutter\ephemeral\cpp_client_wrapper\include test\native\WindowsJsHandlerResponseTest.cpp /Fe:build\reader-js-callback-test.exe && build\reader-js-callback-test.exe"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Output 'WINDOWS JS NULL CALLBACK REGRESSION PASS'
