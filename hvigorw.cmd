@echo off
setlocal

set "HVGOR_JS=D:\develop\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js"
set "DEVECO_SDK_HOME=D:\develop\Huawei\DevEco Studio\sdk"

if not exist "%HVGOR_JS%" (
  echo hvigor wrapper not found: "%HVGOR_JS%"
  echo Please update HVGOR_JS in hvigorw.cmd to your local DevEco Studio installation path.
  exit /b 1
)

if not exist "%DEVECO_SDK_HOME%" (
  echo DevEco SDK not found: "%DEVECO_SDK_HOME%"
  echo Please update DEVECO_SDK_HOME in hvigorw.cmd to your local DevEco SDK root.
  exit /b 1
)

where node >nul 2>nul
if errorlevel 1 (
  echo node.exe not found in PATH.
  echo Please install Node.js or add it to PATH, then retry.
  exit /b 1
)

set "DEVECO_SDK_HOME=%DEVECO_SDK_HOME%"
node "%HVGOR_JS%" %*
