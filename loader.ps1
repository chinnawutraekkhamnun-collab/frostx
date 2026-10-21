# โหลด Assembly สำหรับหน้าต่างกรอกข้อความและแจ้งเตือน
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName Microsoft.VisualBasic

# 1. ดึง HWID ของเครื่องลูกค้า
$hwid = (Get-CimInstance Win32_ComputerSystemProduct).UUID

# 2. เด้งหน้าต่างให้ผู้ใช้กรอก License Key
$key = [Microsoft.VisualBasic.Interaction]::InputBox("กรุณากรอก License Key ของคุณ:", "FlowSkipper Login", "")
if ([string]::IsNullOrWhiteSpace($key)) { exit }

# 3. ส่ง Key และ HWID ไปเช็คที่ Cloudflare Worker (เปลี่ยน URL ด้านล่างเป็น Worker ของคุณ)
$body = @{ key = $key; hwid = $hwid } | ConvertTo-Json
try {
    $response = Invoke-RestMethod -Uri "flat-art-959b.rov170652.workers.dev" -Method Post -Body $body -ContentType "application/json"

    # 4. ถ้ายศผ่าน จะได้โค้ดแอปกลับมาและรันขึ้นมาทันที
    Invoke-Expression $response
} catch {
    [System.Windows.Forms.MessageBox]::Show("เกิดข้อผิดพลาด: คีย์ไม่ถูกต้อง หรือหมดอายุ หรือถูกล็อคกับเครื่องอื่นแล้ว!", "FlowSkipper Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
}