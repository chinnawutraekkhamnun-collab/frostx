# โหลด Assembly สำหรับ UI
Add-Type -AssemblyName System.Windows.Forms

# ดึงค่า HWID ของเครื่อง
$hwid = (Get-CimInstance Win32_ComputerSystemProduct).UUID
$body = @{ hwid = $hwid } | ConvertTo-Json

try {
    # ส่ง Request ไปยัง Worker
    $scriptToRun = Invoke-RestMethod -Uri "https://flat-art-959b.rov170652.workers.dev/" -Method Post -Body $body -ContentType "application/json"
    
    # ประมวลผลสคริปต์ที่ได้รับกลับมา
    Invoke-Expression $scriptToRun
} catch {
    [System.Windows.Forms.MessageBox]::Show("เกิดข้อผิดพลาดในการเชื่อมต่อ หรือเครื่องยังไม่ได้ลงทะเบียน", "FlowSkipper Error", 0, 16)
}
