#Requires -Version 5.1

Set-StrictMode -Version Latest

$publicPath = Join-Path -Path $PSScriptRoot -ChildPath 'Public'
$privatePath = Join-Path -Path $PSScriptRoot -ChildPath 'Private'

$private = @(Get-ChildItem -Path (Join-Path $privatePath '*.ps1') -ErrorAction SilentlyContinue)
$public = @(Get-ChildItem -Path (Join-Path $publicPath '*.ps1') -ErrorAction SilentlyContinue)

foreach ($file in @($private + $public)) {
    try {
        . $file.FullName
    }
    catch {
        throw "Failed to load $($file.FullName): $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function $public.BaseName
