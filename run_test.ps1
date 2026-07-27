Set-Location C:\Users\Rabit\moonbit\s7
Write-Output "=== Starting Build ==="
$moon = "$env:USERPROFILE\.moon\bin\moon.exe"
Write-Output "Using moon: $moon"

# Check if moon exists
if (Test-Path $moon) {
    Write-Output "Moon binary exists"
} else {
    Write-Output "Moon binary NOT FOUND"
    exit 1
}

# Run moon build
Write-Output "Building..."
& $moon build --target native 2>&1
Write-Output "Build exit code: $LASTEXITCODE"

# Find built exe
$exe = Get-ChildItem -Path .\_build -Recurse -Filter "*.exe" | Select-Object -First 1
if ($exe) {
    Write-Output "Found binary: $($exe.FullName)"
} else {
    Write-Output "No exe found"
    Get-ChildItem -Path .\_build -Recurse -Depth 3 | Select-Object FullName | Write-Output
}
