# 1. โหลด Windows Forms เพื่อใช้แสดงหน้าต่างแจ้งเตือน
Add-Type -AssemblyName System.Windows.Forms

# 2. ดึง HWID ของเครื่องปัจจุบัน
$hwid = (Get-CimInstance Win32_ComputerSystemProduct).UUID

# 3. ส่ง HWID ไปตรวจสอบที่ Cloudflare Worker
$body = @{ hwid = $hwid } | ConvertTo-Json
try {
    $response = Invoke-RestMethod -Uri "https://flat-art-959b.rov170652.workers.dev" -Method Post -Body $body -ContentType "application/json"
    
    # ถ้าผ่าน จะดึงสคริปต์มารันต่อทันที
    Invoke-Expression $response
} catch {
    [System.Windows.Forms.MessageBox]::Show("เครื่องนี้ยังไม่ได้ลงทะเบียนสิทธิ์ใช้งาน!", "FlowSkipper Error", 0, 16)
}
