$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')
make test

