$log = "C:\Users\Rabit\moonbit\s7\build_result.txt"
"Starting..." | Out-File $log -Encoding ASCII
$moon = "C:\Users\Rabit\.moon\bin\moon.exe"

# Check moon
& $moon version | Out-File $log -Append -Encoding ASCII

# Build
Set-Location C:\Users\Rabit\moonbit\s7
& $moon build --target native 2>&1 | Out-File $log -Append -Encoding ASCII
"Build exit: $LASTEXITCODE" | Out-File $log -Append -Encoding ASCII

# Find exe
Get-ChildItem -Path C:\Users\Rabit\moonbit\s7\_build -Recurse -ErrorAction SilentlyContinue | Select-Object FullName, Length | Out-File $log -Append -Encoding ASCII

"Done" | Out-File $log -Append -Encoding ASCII
