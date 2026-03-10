$hvigorJs = 'D:\develop\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js'
$devecoSdkHome = 'D:\develop\Huawei\DevEco Studio\sdk'

if (-not (Test-Path $hvigorJs)) {
  Write-Error "hvigor wrapper not found: $hvigorJs"
  Write-Error 'Please update hvigorw.ps1 to your local DevEco Studio installation path.'
  exit 1
}

if (-not (Test-Path $devecoSdkHome)) {
  Write-Error "DevEco SDK not found: $devecoSdkHome"
  Write-Error 'Please update DEVECO_SDK_HOME in hvigorw.ps1 to your local DevEco SDK root.'
  exit 1
}

$nodeCommand = Get-Command node -ErrorAction SilentlyContinue
if ($null -eq $nodeCommand) {
  Write-Error 'node.exe not found in PATH. Please install Node.js or add it to PATH.'
  exit 1
}

$env:DEVECO_SDK_HOME = $devecoSdkHome
& $nodeCommand.Source $hvigorJs @args
