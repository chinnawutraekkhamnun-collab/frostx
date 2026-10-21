# 1. ดึง HWID ของเครื่องลูกค้าอัตโนมัติ
$hwid = (Get-CimInstance Win32_ComputerSystemProduct).UUID

# 2. ส่ง HWID ไปเช็คที่ Cloudflare Worker ทันทีโดยไม่ต้องกรอกคีย์
$body = @{ hwid = $hwid } | ConvertTo-Json
try {
    $response = Invoke-RestMethod -Uri "https://flat-art-959b.rov170652.workers.dev" -Method Post -Body $body -ContentType "application/json"
    
    # 3. ถือว่าผ่าน จะดึงตัวแอปมารันขึ้นมาทันที
    Invoke-Expression $response
} catch {
    [System.Windows.Forms.MessageBox]::Show("เครื่องนี้ยังไม่ได้ลงทะเบียนสิทธิ์ใช้งาน!", "FlowSkipper Error", 0, 16)
}