param(
  [Parameter(Mandatory)]
  [string] $Electron,
  [Parameter(Mandatory)]
  [string] $StockElectron
)

$ErrorActionPreference = 'Stop'

function Invoke-SmokeElectron {
  param(
    [string] $Executable,
    [string[]] $ElectronArguments,
    [hashtable] $Environment,
    [string] $Case
  )

  $startInfo = [System.Diagnostics.ProcessStartInfo]::new($Executable)
  $startInfo.UseShellExecute = $false
  $startInfo.WorkingDirectory = Split-Path -Parent $Executable
  $startInfo.EnvironmentVariables.Remove('ELECTRON_RUN_AS_NODE')
  foreach ($key in $Environment.Keys) {
    $startInfo.EnvironmentVariables[$key] = $Environment[$key]
  }
  $startInfo.Arguments = ($ElectronArguments | ForEach-Object { '"{0}"' -f $_ }) -join ' '

  $child = [System.Diagnostics.Process]::Start($startInfo)
  try {
    if (-not $child.WaitForExit(45000)) {
      & taskkill.exe /PID $child.Id /T /F *> $null
      throw "${Case}: Electron did not exit within 45 seconds."
    }
    return $child.ExitCode
  } finally {
    $child.Dispose()
  }
}

$appDir = Join-Path (Split-Path -Parent $Electron) 'resources/app'
New-Item -ItemType Directory -Path $appDir | Out-Null
$source = Join-Path $PSScriptRoot 'main.js'
$manifest = Join-Path $appDir 'package.json'
$bytecode = Join-Path $appDir 'main-x64.jsc'
$temp = Join-Path ([System.IO.Path]::GetTempPath()) ('electron-entry-smoke-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
$stockBytecode = Join-Path $temp 'stock.jsc'
$marker = Join-Path $temp 'entry-marker.txt'
$environment = @{ ELECTRON_ENTRY_SMOKE_MARKER = $marker }
$nodeMode = @{ ELECTRON_RUN_AS_NODE = '1' }

$compile = Invoke-SmokeElectron -Executable $Electron -ElectronArguments @("$PSScriptRoot/compile.cjs", $source, $bytecode) `
  -Environment $nodeMode -Case 'Compile with modified Electron'
if ($compile -ne 0 -or -not (Test-Path -LiteralPath $bytecode -PathType Leaf)) {
  throw "Modified Electron failed to compile the fixture (exit $compile)."
}
$compileStock = Invoke-SmokeElectron -Executable $StockElectron -ElectronArguments @("$PSScriptRoot/compile.cjs", $source, $stockBytecode) `
  -Environment $nodeMode -Case 'Compile with stock Electron'
if ($compileStock -ne 0 -or -not (Test-Path -LiteralPath $stockBytecode -PathType Leaf)) {
  throw "Stock Electron failed to compile the fixture (exit $compileStock)."
}
$stockControl = Invoke-SmokeElectron -Executable $StockElectron -ElectronArguments @("$PSScriptRoot/check-cache.cjs", $source, $stockBytecode) `
  -Environment $nodeMode -Case 'Validate stock cache on stock Electron'
if ($stockControl -ne 0) { throw "Stock Electron rejected its own cache (exit $stockControl)." }

$stockVersion = [BitConverter]::ToUInt32([IO.File]::ReadAllBytes($stockBytecode), 4)
$modifiedVersion = [BitConverter]::ToUInt32([IO.File]::ReadAllBytes($bytecode), 4)
if ($modifiedVersion -ne ($stockVersion -bxor 0x4a534301)) {
  throw ('Unexpected code-cache versions. Modified: {0:X8}. Stock: {1:X8}.' -f $modifiedVersion, $stockVersion)
}
Write-Host ('V8 code-cache versions. Modified: {0:X8}. Stock: {1:X8}.' -f $modifiedVersion, $stockVersion)

# The positive package has only its manifest and compiled entry.
Copy-Item -LiteralPath "$PSScriptRoot/package.json" -Destination $manifest
$tests = @(
  @{ Name = 'Modified Electron .jsc'; Exit = 0; RunsEntry = $true },
  @{ Name = 'Stock Electron .jsc'; Exit = 1; RunsEntry = $false },
  @{ Name = 'Plain .js'; Exit = 1; RunsEntry = $false },
  @{ Name = 'Plain source renamed to .jsc'; Exit = 1; RunsEntry = $false }
)

foreach ($test in $tests) {
  Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
  switch ($test.Name) {
    'Stock Electron .jsc' {
      Copy-Item -LiteralPath $stockBytecode -Destination $bytecode -Force
    }
    'Plain .js' {
      Copy-Item -LiteralPath $source -Destination (Join-Path $appDir 'main.js')
      @{ name = 'electron-entry-smoke-test'; version = '1.0.0'; main = './main.js' } |
        ConvertTo-Json | Set-Content -LiteralPath $manifest -Encoding utf8
    }
    'Plain source renamed to .jsc' {
      Copy-Item -LiteralPath "$PSScriptRoot/package.json" -Destination $manifest -Force
      Copy-Item -LiteralPath $source -Destination $bytecode -Force
    }
  }

  $code = Invoke-SmokeElectron -Executable $Electron -Environment $environment -Case $test.Name
  $didRun = Test-Path -LiteralPath $marker -PathType Leaf
  if ($code -ne $test.Exit -or $didRun -ne $test.RunsEntry) {
    throw "$($test.Name): expected exit $($test.Exit) and marker $($test.RunsEntry), got exit $code and marker $didRun."
  }
  Write-Host "$($test.Name): expected exit $code and marker $didRun."
}
