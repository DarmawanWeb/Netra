# Stage the files of the Windows installer: netra.exe, WinSW, PostgreSQL binaries, INSTALL.md.
#   pwsh packaging/windows/stage.ps1 -Netra netra.exe -Out stage
param(
  [Parameter(Mandatory)] [string] $Netra,
  [string] $Out = "stage",
  [string] $PostgresZip = "https://get.enterprisedb.com/postgresql/postgresql-16.4-1-windows-x64-binaries.zip",
  [string] $WinSW = "https://github.com/winsw/winsw/releases/download/v2.12.0/WinSW-x64.exe"
)
$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $Out | Out-Null
Copy-Item $Netra (Join-Path $Out "netra.exe")
Invoke-WebRequest $WinSW -OutFile (Join-Path $Out "netra-service.exe")
$zip = Join-Path $env:RUNNER_TEMP "pgsql.zip"
Invoke-WebRequest $PostgresZip -OutFile $zip
Expand-Archive $zip -DestinationPath $Out -Force
# Only the server and its tools: no pgAdmin, StackBuilder, headers, documentation or symbols.
foreach ($d in "pgAdmin 4", "StackBuilder", "include", "doc", "symbols") {
  $p = Join-Path $Out "pgsql\$d"
  if (Test-Path $p) { Remove-Item -Recurse -Force $p }
}
Copy-Item (Join-Path $PSScriptRoot "..\..\INSTALL.md") (Join-Path $Out "INSTALL.md")
Get-ChildItem $Out | Format-Table Name, Length
