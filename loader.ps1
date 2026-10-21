# บังคับโหลด Assembly สำหรับ Windows Forms ไว้บรรทัดแรกสุด
Add-Type -AssemblyName System.Windows.Forms

# ดึง HWID ของเครื่อง
$hwid = (Get-CimInstance Win32_ComputerSystemProduct).UUID

# ส่ง HWID ไปตรวจสอบที่ Cloudflare Worker
$body = @{ hwid = $hwid } | ConvertTo-Json
try {
    $response = Invoke-RestMethod -Uri "https://flat-art-959b.rov170652.workers.dev" -Method Post -Body $body -ContentType "application/json"
    
    # ถ้ายืนยันสิทธิ์ผ่าน จะรันสคริปต์ FRONTX.ps1 ต่อทันที
    Invoke-Expression $response
} catch {
    [System.Windows.Forms.MessageBox]::Show("เครื่องนี้ยังไม่ได้ลงทะเบียนสิทธิ์ใช้งาน!", "FlowSkipper Error", 0, 16)
}
