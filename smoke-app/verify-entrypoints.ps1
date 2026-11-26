param(
  [Parameter(Mandatory)]
  [string] $Electron
)

$ErrorActionPreference = 'Stop'

function Invoke-SmokeElectron {
  param(
    [string[]] $ElectronArguments,
    [hashtable] $Environment,
    [string] $Case
  )

  $startInfo = [System.Diagnostics.ProcessStartInfo]::new($Electron)
  $startInfo.UseShellExecute = $false
  $startInfo.WorkingDirectory = Split-Path -Parent $Electron
  [void] $startInfo.Environment.Remove('ELECTRON_RUN_AS_NODE')
  foreach ($key in $Environment.Keys) {
    $startInfo.Environment[$key] = $Environment[$key]
  }
  foreach ($argument in $ElectronArguments) {
    $startInfo.ArgumentList.Add($argument)
  }

  $child = [System.Diagnostics.Process]::Start($startInfo)
  try {
    if (-not $child.WaitForExit(45000)) {
      $child.Kill($true)
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
$marker = Join-Path $env:RUNNER_TEMP 'electron-entry-smoke-marker.txt'
$environment = @{ ELECTRON_ENTRY_SMOKE_MARKER = $marker }

$compile = Invoke-SmokeElectron -ElectronArguments @("$PSScriptRoot/compile.cjs", $source, $bytecode) `
  -Environment @{ ELECTRON_RUN_AS_NODE = '1' } -Case 'Compile fixture'
if ($compile -ne 0 -or -not (Test-Path -LiteralPath $bytecode -PathType Leaf)) {
  throw "Electron failed to compile the fixture (exit $compile)."
}

# The positive package has only its manifest and compiled entry.
Copy-Item -LiteralPath "$PSScriptRoot/package.json" -Destination $manifest
$tests = @(
  @{ Name = 'Compiled .jsc'; Exit = 0; RunsEntry = $true },
  @{ Name = 'Plain .js'; Exit = 1; RunsEntry = $false },
  @{ Name = 'Plain source renamed to .jsc'; Exit = 1; RunsEntry = $false }
)

foreach ($test in $tests) {
  Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
  switch ($test.Name) {
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

  $code = Invoke-SmokeElectron -Environment $environment -Case $test.Name
  $didRun = Test-Path -LiteralPath $marker -PathType Leaf
  if ($code -ne $test.Exit -or $didRun -ne $test.RunsEntry) {
    throw "$($test.Name): expected exit $($test.Exit) and marker $($test.RunsEntry), got exit $code and marker $didRun."
  }
  Write-Host "$($test.Name): expected exit $code and marker $didRun."
}
