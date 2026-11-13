param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
& node (Join-Path $PSScriptRoot 'visual-review.js') --verify
if ($LASTEXITCODE -ne 0) { throw 'Release blocked: current build requires human visual review in WoW.' }
& node (Join-Path $PSScriptRoot 'check-ui.js')
if ($LASTEXITCODE -ne 0) { throw 'Release blocked: UI code checks failed.' }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repoRoot 'releases' }
$manifest = Get-Content -LiteralPath (Join-Path $repoRoot 'addon\AzerMind_Data\manifest.json') -Raw | ConvertFrom-Json
$package = Get-Content -LiteralPath (Join-Path $repoRoot 'package.json') -Raw | ConvertFrom-Json
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$target = Join-Path $OutputDirectory ('AzerMind-' + $package.version + '-catalog-' + $manifest.version + '.zip')
$outputFull = [IO.Path]::GetFullPath($OutputDirectory)
$stage = Join-Path $outputFull ('stage-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot 'addon\AzerMind') -Destination $stage -Recurse
Get-ChildItem -LiteralPath (Join-Path $repoRoot 'addon') -Directory | Where-Object Name -Match '^AzerMind_Data(?:_[A-Za-z]+)?$' | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $stage -Recurse }
Copy-Item -LiteralPath (Join-Path $repoRoot 'LICENSE') -Destination (Join-Path $stage 'AzerMind\LICENSE.txt')
Copy-Item -LiteralPath (Join-Path $repoRoot 'README.md') -Destination (Join-Path $stage 'AzerMind\README.md')
$sourceTools = Join-Path $stage 'AzerMind_Data\source-tools'
New-Item -ItemType Directory -Path $sourceTools | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'build-catalog.js') -Destination $sourceTools
& node (Join-Path $repoRoot 'bridge\install-slots.js') --addon-dir $stage
if ($LASTEXITCODE -ne 0) { throw 'Could not generate the release transport slots.' }
$folders = @(Get-ChildItem -LiteralPath $stage -Directory | Select-Object -ExpandProperty FullName)
Compress-Archive -LiteralPath $folders -DestinationPath $target -Force
# Delete only this verified, newly-created staging directory inside the output.
$stageFull = [IO.Path]::GetFullPath($stage)
if (-not $stageFull.StartsWith($outputFull.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe staging cleanup path' }
Remove-Item -LiteralPath $stageFull -Recurse -Force
Get-Item -LiteralPath $target | Select-Object FullName, Length
Get-FileHash -LiteralPath $target -Algorithm SHA256 | Select-Object Hash
