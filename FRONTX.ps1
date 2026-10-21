@echo off
REM FlowSkipper.bat - double-click to run. No install needed (uses built-in Windows PowerShell).
setlocal
fltmc >nul 2>&1
if errorlevel 1 goto needadmin
set "PS1=%TEMP%\flow_skipper.ps1"
set "BATDIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t=[IO.File]::ReadAllText('%~f0',[Text.Encoding]::UTF8); $p=$t -split '\r?\n#PSSTART\r?\n',2; $nl=[Environment]::NewLine; $w='Add-Type -AssemblyName System.Windows.Forms'+$nl+'try {'+$nl+$p[1]+$nl+'} catch { [Windows.Forms.MessageBox]::Show(($_ | Out-String),''Fam Bypass error'') | Out-Null }'; [IO.File]::WriteAllText('%PS1%',$w,(New-Object Text.UTF8Encoding $true))"
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File "%PS1%"
exit /b
:needadmin
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b
#PSSTART
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------- คอนโทรลสวย ๆ (วาดเองด้วย C#) ----------
$cs = @'
using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public static class Gfx
{
    [DllImport("user32.dll")] static extern bool ReleaseCapture();
    [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);
    [DllImport("shell32.dll")] public static extern int SetCurrentProcessExplicitAppUserModelID(string AppID);

    public static void Drag(IntPtr h)
    {
        ReleaseCapture();
        SendMessage(h, 0xA1, (IntPtr)2, IntPtr.Zero);
    }

    // ลบพื้นหลังสีดำ/เข้มของรูปโลโก้ให้โปร่งใส (ไล่ความโปร่งใสตามความสว่าง เพื่อให้ขอบเรืองแสงยังสวย)
        // โหลดโลโก้: ถ้ามีช่องโปร่งใสอยู่แล้วใช้ตามเดิม / ถ้าพื้นขาวจะลบพื้นขาว / ถ้าพื้นดำใช้วิธีเดิม
    public static Bitmap LoadLogo(string path)
    {
        Bitmap src = new Bitmap(path);
        double sc = Math.Min(1.0, 512.0 / Math.Max(src.Width, src.Height));
        int w = Math.Max(1, (int)(src.Width * sc));
        int h = Math.Max(1, (int)(src.Height * sc));
        Bitmap bmp = new Bitmap(w, h, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        using (Graphics g = Graphics.FromImage(bmp))
        {
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.DrawImage(src, 0, 0, w, h);
        }
        src.Dispose();

        Color c0 = bmp.GetPixel(0, 0);
        if (c0.A < 250) return bmp;                                          // โปร่งใสอยู่แล้ว
        if (Math.Min(c0.R, Math.Min(c0.G, c0.B)) > 225) return RemoveLight(bmp);   // พื้นขาว
        bmp.Dispose();
        return RemoveBg(path);                                               // พื้นเข้ม
    }

    // ลบพื้นขาวเฉพาะส่วนที่ติดขอบรูป (ไฮไลต์สีขาวข้างในตัวโลโก้จะไม่โดนลบ)
    static Bitmap RemoveLight(Bitmap bmp)
    {
        int w = bmp.Width, h = bmp.Height;
        System.Drawing.Imaging.BitmapData d = bmp.LockBits(new Rectangle(0, 0, w, h),
            System.Drawing.Imaging.ImageLockMode.ReadWrite, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        int stride = d.Stride;
        int n = Math.Abs(stride) * h;
        byte[] px = new byte[n];
        Marshal.Copy(d.Scan0, px, 0, n);
        bool[] seen = new bool[w * h];
        System.Collections.Generic.Stack<int> st = new System.Collections.Generic.Stack<int>();
        for (int x = 0; x < w; x++) { st.Push(x); st.Push((h - 1) * w + x); }
        for (int y = 0; y < h; y++) { st.Push(y * w); st.Push(y * w + w - 1); }
        while (st.Count > 0)
        {
            int p = st.Pop();
            if (seen[p]) continue;
            int x = p % w, y = p / w;
            int i = y * stride + x * 4;
            int mn = Math.Min(px[i], Math.Min(px[i + 1], px[i + 2]));
            if (mn < 215) continue;
            seen[p] = true;
            px[i + 3] = (byte)(mn >= 245 ? 0 : (245 - mn) * 255 / 30);
            if (x > 0 && !seen[p - 1]) st.Push(p - 1);
            if (x < w - 1 && !seen[p + 1]) st.Push(p + 1);
            if (y > 0 && !seen[p - w]) st.Push(p - w);
            if (y < h - 1 && !seen[p + w]) st.Push(p + w);
        }
        Marshal.Copy(px, 0, d.Scan0, n);
        bmp.UnlockBits(d);
        return bmp;
    }
    public static Bitmap RemoveBg(string path)
    {
        Bitmap src = new Bitmap(path);
        Bitmap bmp = new Bitmap(src.Width, src.Height, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        using (Graphics g = Graphics.FromImage(bmp)) g.DrawImage(src, 0, 0, src.Width, src.Height);
        src.Dispose();
        System.Drawing.Imaging.BitmapData d = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height),
            System.Drawing.Imaging.ImageLockMode.ReadWrite, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        int n = Math.Abs(d.Stride) * bmp.Height;
        byte[] px = new byte[n];
        Marshal.Copy(d.Scan0, px, 0, n);
        for (int y = 0; y < bmp.Height; y++)
        {
            for (int x = 0; x < bmp.Width; x++)
            {
                int i = y * d.Stride + x * 4;
                int b = px[i], gg = px[i + 1], r = px[i + 2];
                int m = Math.Max(r, Math.Max(gg, b));
                int a = (m - 22) * 5;
                if (a < 0) a = 0;
                if (a > 255) a = 255;
                if (a > 0 && a < 255)
                {
                    px[i] = (byte)Math.Min(255, b * 255 / a);
                    px[i + 1] = (byte)Math.Min(255, gg * 255 / a);
                    px[i + 2] = (byte)Math.Min(255, r * 255 / a);
                }
                px[i + 3] = (byte)a;
            }
        }
        Marshal.Copy(px, 0, d.Scan0, n);
        bmp.UnlockBits(d);
        return bmp;
    }

    public static GraphicsPath Round(Rectangle r, int rad)
    {
        int d = Math.Min(rad * 2, Math.Min(r.Width, r.Height));
        if (d < 1) d = 1;
        GraphicsPath p = new GraphicsPath();
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }
}

// ฟอร์มพื้นหลังไล่สี  -  วาดพื้นหลังครั้งเดียวลง Bitmap แล้วใช้ซ้ำ (ไม่คำนวณ gradient/glow ใหม่ทุกครั้งที่รีเพนต์)
public class GradForm : Form
{
    public Color BgA = Color.FromArgb(20, 10, 46);
    public Color BgB = Color.FromArgb(88, 32, 176);
    public bool Glows = true;
    public bool Stars = false;
    int radius = 22;
    Bitmap cache;
    [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int val, int size);
    bool dwmRound;

    public GradForm()
    {
        FormBorderStyle = FormBorderStyle.None;
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer, true);
        DoubleBuffered = true;
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        try
        {
            int pref = 2;
            dwmRound = (DwmSetWindowAttribute(Handle, 33, ref pref, 4) == 0);
            if (dwmRound)
            {
                int bc = 70 | (50 << 8) | (110 << 16);
                DwmSetWindowAttribute(Handle, 34, ref bc, 4);
                Region = null;
            }
        }
        catch { dwmRound = false; }
        UpdateRegion();
        DropCache();
        Invalidate();
    }
     public void ToggleMax()
{
    if (WindowState == FormWindowState.Maximized) WindowState = FormWindowState.Normal;
    else { MaximizedBounds = Screen.FromControl(this).WorkingArea; WindowState = FormWindowState.Maximized; }
}

protected override void WndProc(ref Message m)
{
    if (m.Msg == 0x84 && WindowState == FormWindowState.Normal)   // WM_NCHITTEST: ลากขอบ/มุมเพื่อย่อขยาย
    {
        int lp = (int)(long)m.LParam;
        Point p = PointToClient(new Point((short)(lp & 0xFFFF), (short)((lp >> 16) & 0xFFFF)));
        int b = 8;
        bool l = p.X < b, r = p.X >= Width - b, t = p.Y < b, d = p.Y >= Height - b;
        int h = 0;
        if (t && l) h = 13; else if (t && r) h = 14; else if (d && l) h = 16; else if (d && r) h = 17;
        else if (l) h = 10; else if (r) h = 11; else if (t) h = 12; else if (d) h = 15;
        if (h != 0) { m.Result = (IntPtr)h; return; }
    }
    base.WndProc(ref m);
}

    public int Radius
    {
        get { return radius; }
        set { radius = value; UpdateRegion(); DropCache(); Invalidate(); }
    }

    void DropCache()
    {
        if (cache != null) { cache.Dispose(); cache = null; }
    }

    void UpdateRegion()
    {   
        if (WindowState == FormWindowState.Maximized) { Region = null; return; }
        if (dwmRound) return;
        if (Width > 0 && Height > 0)
        {
            using (GraphicsPath p = Gfx.Round(new Rectangle(0, 0, Width, Height), radius))
                Region = new Region(p);
        }
    }

    static void Glow(Graphics g, int cx, int cy, int rad, Color c)
    {
        using (GraphicsPath gp = new GraphicsPath())
        {
            gp.AddEllipse(cx - rad, cy - rad, rad * 2, rad * 2);
            using (PathGradientBrush pb = new PathGradientBrush(gp))
            {
                pb.CenterColor = c;
                pb.SurroundColors = new Color[] { Color.FromArgb(0, c.R, c.G, c.B) };
                g.FillPath(pb, gp);
            }
        }
    }

            void BuildCache()
    {
        DropCache();
        if (Width < 2 || Height < 2) return;
        cache = new Bitmap(Width, Height, System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
        using (Graphics g = Graphics.FromImage(cache))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            Rectangle r = new Rectangle(0, 0, Width, Height);
            using (LinearGradientBrush b = new LinearGradientBrush(r, BgA, BgB, 60f))
                g.FillRectangle(b, r);
            if (Glows)
            {
                Glow(g, Width - 40, 40, 300, Color.FromArgb(120, 139, 70, 235));
                Glow(g, Width - 60, Height - 40, 340, Color.FromArgb(70, 34, 197, 94));
                Glow(g, 30, Height - 30, 260, Color.FromArgb(60, 120, 50, 220));
            }
            if (Stars)
            {
                Glow(g, Width - 150, 170, 400, Color.FromArgb(75, 120, 60, 225));
                Glow(g, 90, Height - 140, 380, Color.FromArgb(55, 70, 50, 200));
                Glow(g, Width - 90, Height - 70, 330, Color.FromArgb(38, 34, 197, 94));
                Glow(g, Width / 2, 30, 280, Color.FromArgb(28, 150, 70, 230));
                Random rnd = new Random(11);
                for (int i = 0; i < 260; i++)
                {
                    float sx = (float)(rnd.NextDouble() * Width);
                    float sy = (float)(rnd.NextDouble() * Height);
                    int a = rnd.Next(40, 210);
                    float sz = rnd.Next(12) == 0 ? 2.2f : 1.2f;
                    int t = rnd.Next(10);
                    Color sc = t < 7 ? Color.FromArgb(a, 255, 255, 255) : (t < 9 ? Color.FromArgb(a, 196, 181, 253) : Color.FromArgb(a, 134, 239, 172));
                    using (SolidBrush sbr = new SolidBrush(sc))
                        g.FillEllipse(sbr, sx, sy, sz, sz);
                }
            }
            if (!dwmRound)
            {
                using (Pen pen = new Pen(Color.FromArgb(80, 255, 255, 255), 1f))
                using (GraphicsPath p = Gfx.Round(new Rectangle(0, 0, Width - 1, Height - 1), radius))
                    g.DrawPath(pen, p);
            }
        }
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        if (cache == null || cache.Width != Width || cache.Height != Height) BuildCache();
        if (cache != null) e.Graphics.DrawImageUnscaled(cache, 0, 0);
    }

    protected override void OnMouseDown(MouseEventArgs e)
    {
        if (e.Button == MouseButtons.Left) Gfx.Drag(Handle);
        base.OnMouseDown(e);
    }

    protected override void OnResize(EventArgs e)
    {
        base.OnResize(e);
        UpdateRegion();
        DropCache();
        Invalidate();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) DropCache();
        base.Dispose(disposing);
    }
}

public class Card : Control
{
    public Color Fill = Color.FromArgb(24, 13, 50);

    public Card()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer
            | ControlStyles.SupportsTransparentBackColor | ControlStyles.ResizeRedraw, true);
        BackColor = Color.Transparent;
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        if (Width < 4 || Height < 4) return;
        Rectangle br = new Rectangle(0, 0, Width - 1, Height - 1);
        using (GraphicsPath p = Gfx.Round(br, 14))
        {
            using (SolidBrush fb = new SolidBrush(Fill))
                g.FillPath(fb, p);
            using (LinearGradientBrush gb = new LinearGradientBrush(br, Color.FromArgb(200, 168, 85, 247), Color.FromArgb(200, 74, 222, 128), 35f))
            using (Pen pen = new Pen(gb, 1.4f))
                g.DrawPath(pen, p);
        }
    }
}

public class GradBar : Control
{
    int val;
    public Color C1 = Color.FromArgb(139, 92, 246);
    public Color C2 = Color.FromArgb(74, 222, 128);
    public Color Track = Color.FromArgb(38, 26, 74);

    public GradBar()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        Height = 10;
    }

    public int Value
    {
        get { return val; }
        set { val = Math.Max(0, Math.Min(100, value)); Invalidate(); }
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.Clear(BackColor);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        int rad = Math.Max(1, (Height - 1) / 2);
        Rectangle r = new Rectangle(0, 0, Width - 1, Height - 1);
        using (GraphicsPath p = Gfx.Round(r, rad))
        using (SolidBrush b = new SolidBrush(Track))
            g.FillPath(b, p);
        int w = (int)((Width - 1) * val / 100.0);
        if (w > 0)
        {
            if (w < Height) w = Height;
            if (w > Width - 1) w = Width - 1;
            Rectangle fr = new Rectangle(0, 0, w, Height - 1);
            using (GraphicsPath p2 = Gfx.Round(fr, rad))
            using (LinearGradientBrush lb = new LinearGradientBrush(new Rectangle(0, 0, Math.Max(w, 2), Height), C1, C2, LinearGradientMode.Horizontal))
                g.FillPath(lb, p2);
        }
    }
}

public class GradButton : Control
{
    public Color C1 = Color.FromArgb(124, 58, 237);
    public Color C2 = Color.FromArgb(217, 70, 239);
    public string RightText = "";
    bool hover;
    bool down;

    public GradButton()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer
            | ControlStyles.SupportsTransparentBackColor | ControlStyles.ResizeRedraw | ControlStyles.StandardClick, true);
        BackColor = Color.Transparent;
        Cursor = Cursors.Hand;
        ForeColor = Color.White;
        Font = new Font("ไอติม", 11f);
    }

    protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { hover = false; down = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnMouseDown(MouseEventArgs e) { down = true; Invalidate(); base.OnMouseDown(e); }
    protected override void OnMouseUp(MouseEventArgs e) { down = false; Invalidate(); base.OnMouseUp(e); }
    protected override void OnEnabledChanged(EventArgs e) { base.OnEnabledChanged(e); Invalidate(); }
    protected override void OnTextChanged(EventArgs e) { base.OnTextChanged(e); Invalidate(); }

    static Color Lite(Color c, int n)
    {
        return Color.FromArgb(c.A, Math.Min(255, c.R + n), Math.Min(255, c.G + n), Math.Min(255, c.B + n));
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        int inset = down ? 2 : 0;
        Rectangle r = new Rectangle(inset, inset, Width - 1 - inset * 2, Height - 1 - inset * 2);
        if (r.Width < 4 || r.Height < 4) return;

        Color a = C1, b = C2;
        if (!Enabled) { a = Color.FromArgb(62, 52, 94); b = Color.FromArgb(52, 44, 82); }
        else if (hover) { a = Lite(a, 28); b = Lite(b, 28); }

        using (GraphicsPath path = Gfx.Round(r, 14))
        {
            using (LinearGradientBrush br = new LinearGradientBrush(r, a, b, LinearGradientMode.Horizontal))
                g.FillPath(br, path);

            Rectangle hl = new Rectangle(r.X, r.Y, r.Width, Math.Max(2, r.Height / 2));
            Rectangle hb2 = new Rectangle(hl.X, hl.Y - 1, hl.Width, hl.Height + 2);
            using (LinearGradientBrush hb = new LinearGradientBrush(hb2, Color.FromArgb(Enabled ? 60 : 15, 255, 255, 255), Color.FromArgb(0, 255, 255, 255), LinearGradientMode.Vertical))
            {
                hb.WrapMode = WrapMode.TileFlipXY;
                g.SetClip(path);
                g.FillRectangle(hb, hl);
                g.ResetClip();
            }

            using (Pen pen = new Pen(Color.FromArgb(Enabled ? 100 : 30, 255, 255, 255), 1f))
                g.DrawPath(pen, path);
        }

        Color tc = Enabled ? ForeColor : Color.FromArgb(140, 130, 170);
        TextRenderer.DrawText(g, Text, Font, new Rectangle(0, 0, Width, Height), tc,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix);
        if (RightText.Length > 0)
        {
            TextRenderer.DrawText(g, RightText, Font, new Rectangle(0, 0, Width - 18, Height), tc,
                TextFormatFlags.Right | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine | TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix);
        }
    }
}

public class Logo : Control
{
    public Image Img;

    public Logo()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer
            | ControlStyles.SupportsTransparentBackColor | ControlStyles.ResizeRedraw, true);
        BackColor = Color.Transparent;
        Text = "F";
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
        if (Width < 20 || Height < 20) return;

        if (Img != null)
        {
            g.DrawImage(Img, new Rectangle(0, 0, Width, Height));
            return;
        }

        Rectangle full = new Rectangle(0, 0, Width, Height);
        Rectangle r = new Rectangle(6, 6, Width - 13, Height - 13);
        using (LinearGradientBrush lb = new LinearGradientBrush(full, Color.FromArgb(232, 121, 249), Color.FromArgb(99, 102, 241), 45f))
        {
            using (SolidBrush ib = new SolidBrush(Color.FromArgb(50, 168, 85, 247)))
                g.FillEllipse(ib, r);
            using (Pen ring = new Pen(lb, 5f))
                g.DrawEllipse(ring, r);
            using (StringFormat sf = new StringFormat())
            {
                sf.Alignment = StringAlignment.Center;
                sf.LineAlignment = StringAlignment.Center;
                using (Font f = new Font("ไอติม", Height * 0.42f, FontStyle.Bold, GraphicsUnit.Pixel))
                    g.DrawString(Text, f, lb, new RectangleF(0, 0, Width, Height), sf);
            }
        }
    }
}

public class InputBox : Control
{
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr SendMessage(IntPtr h, int m, IntPtr w, string l);

    public TextBox Box = new TextBox();
    public bool Error;
    public bool Reveal;
    public string Placeholder = "";
    bool focused;
    static Color Fill = Color.FromArgb(22, 17, 38);

    public InputBox()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer
            | ControlStyles.SupportsTransparentBackColor | ControlStyles.ResizeRedraw, true);
        BackColor = Color.Transparent;
        Box.BorderStyle = BorderStyle.None;
        Box.BackColor = Fill;
        Box.ForeColor = Color.White;
        Box.Font = new Font("Segoe UI", 11f);
        Box.GotFocus += delegate { focused = true; Invalidate(); };
        Box.LostFocus += delegate { focused = false; Invalidate(); };
        Box.HandleCreated += delegate
        {
            if (Placeholder.Length > 0) SendMessage(Box.Handle, 0x1501, IntPtr.Zero, Placeholder);
        };
        Controls.Add(Box);
    }

    void LayoutBox()
    {
        Box.Left = 48;
        Box.Width = Math.Max(20, Width - 48 - 52);   // เว้นที่ด้านขวาให้ปุ่มตา
        Box.Top = Math.Max(0, (Height - Box.Height) / 2);
    }

    bool OnEye(int x) { return x >= Width - 46; }

    protected override void OnResize(EventArgs e) { base.OnResize(e); LayoutBox(); }
    protected override void OnHandleCreated(EventArgs e) { base.OnHandleCreated(e); LayoutBox(); }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        Cursor = OnEye(e.X) ? Cursors.Hand : Cursors.Default;
        base.OnMouseMove(e);
    }

    protected override void OnMouseClick(MouseEventArgs e)
    {
        if (OnEye(e.X))
        {
            Reveal = !Reveal;
            Box.PasswordChar = Reveal ? '\0' : '*';
            Invalidate();
            Box.Focus();
        }
        base.OnMouseClick(e);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        Rectangle r = new Rectangle(0, 0, Width - 1, Height - 1);
        if (r.Width < 10 || r.Height < 10) return;

        Color border = Error ? Color.FromArgb(239, 68, 68)
                     : focused ? Color.FromArgb(139, 92, 246)
                     : Color.FromArgb(64, 54, 94);

        using (GraphicsPath p = Gfx.Round(r, 12))
        {
            using (SolidBrush b = new SolidBrush(Fill)) g.FillPath(b, p);
            using (Pen pen = new Pen(border, 1.2f)) g.DrawPath(pen, p);
        }

        int cy = Height / 2;
        using (Pen kp = new Pen(Color.FromArgb(165, 155, 195), 1.6f))
        {
            // ไอคอนกุญแจ
            g.DrawEllipse(kp, 17, cy - 4, 9, 9);
            g.DrawLine(kp, 25, cy + 4, 34, cy + 11);
            g.DrawLine(kp, 30, cy + 8, 33, cy + 5);
            g.DrawLine(kp, 33, cy + 10, 36, cy + 7);
        }

        // ไอคอนตา (เปิดตา = แสดงคีย์ / ขีดฆ่า = ซ่อนคีย์)
        int ex = Width - 28;
        Color ec = Reveal ? Color.FromArgb(196, 181, 253) : Color.FromArgb(165, 155, 195);
        using (Pen ep = new Pen(ec, 1.6f))
        {
            g.DrawBezier(ep, ex - 11, cy, ex - 5, cy - 9, ex + 5, cy - 9, ex + 11, cy);
            g.DrawBezier(ep, ex - 11, cy, ex - 5, cy + 9, ex + 5, cy + 9, ex + 11, cy);
            g.DrawEllipse(ep, ex - 3, cy - 3, 6, 6);
            if (!Reveal) g.DrawLine(ep, ex - 9, cy + 9, ex + 9, cy - 9);
        }
    }
}

public class ToggleSwitch : Control
{
    bool on;
    float pos;              // 0 = ปิด (ปุ่มอยู่ขวา), 1 = เปิด (ปุ่มปัดไปซ้าย)
    Timer anim = new Timer();
    public Color OnColor = Color.FromArgb(34, 197, 94);
    public Color OffColor = Color.FromArgb(96, 96, 108);
    public event EventHandler CheckedChanged;

    public ToggleSwitch()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        Size = new Size(60, 30);
        Cursor = Cursors.Hand;
        anim.Interval = 15;
        anim.Tick += delegate
        {
            float target = on ? 1f : 0f;
            float d = target - pos;
            if (Math.Abs(d) <= 0.1f) { pos = target; anim.Stop(); }
            else pos += d > 0 ? 0.1f : -0.1f;
            Invalidate();
        };
    }

    public bool Checked
    {
        get { return on; }
        set
        {
            if (on == value) return;
            on = value;
            anim.Start();
            if (CheckedChanged != null) CheckedChanged(this, EventArgs.Empty);
        }
    }

    protected override void OnClick(EventArgs e) { Checked = !Checked; base.OnClick(e); }

    static int Mix(int a, int b, float t) { return (int)(a + (b - a) * t); }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.Clear(BackColor);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        Rectangle r = new Rectangle(0, 0, Width - 1, Height - 1);
        if (r.Width < 10 || r.Height < 10) return;

        Color c = Color.FromArgb(Mix(OffColor.R, OnColor.R, pos), Mix(OffColor.G, OnColor.G, pos), Mix(OffColor.B, OnColor.B, pos));
        using (GraphicsPath path = Gfx.Round(r, r.Height / 2))
        using (SolidBrush b = new SolidBrush(c))
            g.FillPath(b, path);

        int d = Height - 7;
        float xLeft = 3f;
        float xRight = Width - 4f - d;
        float x = xRight + (xLeft - xRight) * pos;
        using (SolidBrush sh = new SolidBrush(Color.FromArgb(50, 0, 0, 0)))
            g.FillEllipse(sh, x, 4f, d, d);
        using (SolidBrush kb = new SolidBrush(Color.White))
            g.FillEllipse(kb, x, 3f, d, d);
    }
}

public class MiniGraph : Control
{
    public System.Collections.Generic.List<float> Data = new System.Collections.Generic.List<float>();
    public Color Line = Color.FromArgb(168, 85, 247);
    public float MaxV = 100;   // 0 = ปรับสเกลอัตโนมัติ (ใช้กับ Ping)
    public int Cap = 60;

    public MiniGraph()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
    }

    public void Push(float v)
    {
        Data.Add(v);
        while (Data.Count > Cap) Data.RemoveAt(0);
        Invalidate();
    }

    protected override void OnResize(EventArgs e)
    {
        base.OnResize(e);
        if (Width > 0 && Height > 0)
            using (GraphicsPath p = Gfx.Round(new Rectangle(0, 0, Width, Height), 8))
                Region = new Region(p);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.Clear(Color.FromArgb(22, 17, 38));
        g.SmoothingMode = SmoothingMode.AntiAlias;
        using (Pen gp = new Pen(Color.FromArgb(40, 255, 255, 255), 1f))
            for (int i = 1; i < 4; i++) g.DrawLine(gp, 0, Height * i / 4, Width, Height * i / 4);
        if (Data.Count < 2) return;

        float mx = MaxV;
        if (mx <= 0) { mx = 100; foreach (float v in Data) if (v * 1.2f > mx) mx = v * 1.2f; }
        float step = (float)Width / (Cap - 1);
        PointF[] pts = new PointF[Data.Count];
        for (int i = 0; i < Data.Count; i++)
        {
            float x = Width - (Data.Count - 1 - i) * step;
            float v = Math.Max(0f, Math.Min(Data[i], mx));
            pts[i] = new PointF(x, Height - 1 - (v / mx) * (Height - 3));
        }
        PointF[] poly = new PointF[pts.Length + 2];
        poly[0] = new PointF(pts[0].X, Height);
        Array.Copy(pts, 0, poly, 1, pts.Length);
        poly[poly.Length - 1] = new PointF(Width, Height);
        using (SolidBrush fb = new SolidBrush(Color.FromArgb(60, Line)))
            g.FillPolygon(fb, poly);
        using (Pen lp = new Pen(Line, 1.8f))
            g.DrawLines(lp, pts);
    }
}

// ล้างแรมแบบเบา: ทำงานใน thread แยก (ไม่ค้าง UI) และ "ไม่ย่อ working set ของแอป/เกมที่กำลังใช้งานอยู่หน้าจอ"
public static class MemCleaner
{
    [DllImport("psapi.dll")] static extern bool EmptyWorkingSet(IntPtr h);
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);

    static volatile bool busy;

    public static void RunAsync()
    {
        if (busy) return;
        busy = true;
        System.Threading.Thread t = new System.Threading.Thread(delegate()
        {
            try { Trim(); } catch { }
            busy = false;
        });
        t.IsBackground = true;
        t.Priority = System.Threading.ThreadPriority.BelowNormal;
        t.Start();
    }

    static void Trim()
    {
        uint fg = 0;
        GetWindowThreadProcessId(GetForegroundWindow(), out fg);
        int me = Process.GetCurrentProcess().Id;
        foreach (Process p in Process.GetProcesses())
        {
            try
            {
                int id = p.Id;
                if (id <= 4 || id == me || id == (int)fg) continue;
                string n = p.ProcessName.ToLowerInvariant();
                if (n == "csrss" || n == "dwm" || n == "winlogon" || n == "wininit" || n == "smss" || n == "services"
                    || n == "lsass" || n == "audiodg" || n == "registry" || n == "memory compression") continue;
                IntPtr h = OpenProcess(0x500, false, id);   // SET_QUOTA | QUERY_INFORMATION
                if (h != IntPtr.Zero) { EmptyWorkingSet(h); CloseHandle(h); }
                System.Threading.Thread.Sleep(3);
            }
            catch { }
            finally { p.Dispose(); }
        }
    }
}

// อ่านค่า CPU / RAM / Ping / GPU / WiFi ใน thread เบื้องหลัง  -  UI แค่อ่านค่าที่เตรียมไว้ (ไม่ค้างตอนรอ nvidia-smi / netsh / WMI)
public class SysMon
{
    [StructLayout(LayoutKind.Sequential)]
    struct MEMSTAT
    {
        public uint dwLength;
        public uint dwMemoryLoad;
        public ulong ullTotalPhys;
        public ulong ullAvailPhys;
        public ulong ullTotalPageFile;
        public ulong ullAvailPageFile;
        public ulong ullTotalVirtual;
        public ulong ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;
    }

    [DllImport("kernel32.dll")] static extern bool GlobalMemoryStatusEx(ref MEMSTAT m);
    [DllImport("kernel32.dll")] static extern bool GetSystemTimes(out long idle, out long kernel, out long user);

    public volatile int Cpu;
    public volatile int RamPct;
    public double RamUsed, RamTotal;
    public double GpuV;
    public volatile string GpuText = "";
    public volatile string GpuSub = "";
    public volatile bool GpuOk = true;
    public volatile int Wifi = -1;
    public volatile string Ssid = "";
    public long PingMs;
    public volatile bool PingSeen;
    public volatile bool PingOk;
    volatile bool stop;

    public void Start()
    {
        Spawn(FastLoop);
        Spawn(GpuLoop);
        Spawn(WifiLoop);
    }

    public void Stop() { stop = true; }

    static void Spawn(System.Threading.ThreadStart f)
    {
        System.Threading.Thread t = new System.Threading.Thread(f);
        t.IsBackground = true;
        t.Priority = System.Threading.ThreadPriority.BelowNormal;
        t.Start();
    }

    void FastLoop()
    {
        PerformanceCounter pc = null;
        try { pc = new PerformanceCounter("Processor Information", "% Processor Utility", "_Total"); pc.NextValue(); }
        catch
        {
            pc = null;
            try { pc = new PerformanceCounter("Processor", "% Processor Time", "_Total"); pc.NextValue(); } catch { pc = null; }
        }
        long i0 = 0, k0 = 0, u0 = 0;
        GetSystemTimes(out i0, out k0, out u0);
        System.Net.NetworkInformation.Ping ping = new System.Net.NetworkInformation.Ping();
        Stopwatch sw = new Stopwatch();

        while (!stop)
        {
            sw.Restart();
            try
            {
                if (pc != null) Cpu = (int)Math.Min(100, Math.Round(pc.NextValue()));
                else
                {
                    long i1, k1, u1;
                    GetSystemTimes(out i1, out k1, out u1);
                    long idle = i1 - i0, tot = (k1 - k0) + (u1 - u0);
                    if (tot > 0) Cpu = (int)Math.Max(0, Math.Min(100, 100 - idle * 100 / tot));
                    i0 = i1; k0 = k1; u0 = u1;
                }
            }
            catch { }

            try
            {
                MEMSTAT ms = new MEMSTAT();
                ms.dwLength = (uint)Marshal.SizeOf(typeof(MEMSTAT));
                if (GlobalMemoryStatusEx(ref ms) && ms.ullTotalPhys > 0)
                {
                    double tot = ms.ullTotalPhys / 1073741824.0;
                    double used = (ms.ullTotalPhys - ms.ullAvailPhys) / 1073741824.0;
                    RamTotal = tot;
                    RamUsed = used;
                    RamPct = (int)Math.Round(used / tot * 100.0);
                }
            }
            catch { }

            try
            {
                System.Net.NetworkInformation.PingReply r = ping.Send("8.8.8.8", 900);
                PingOk = (r.Status == System.Net.NetworkInformation.IPStatus.Success);
                PingMs = r.RoundtripTime;
            }
            catch { PingOk = false; PingMs = 0; }
            PingSeen = true;

            int rest = 1000 - (int)sw.ElapsedMilliseconds;
            if (rest > 0) System.Threading.Thread.Sleep(rest);
        }
    }

    void GpuLoop()
    {
        string exe = "nvidia-smi";
        try
        {
            string sys = System.IO.Path.Combine(Environment.SystemDirectory, "nvidia-smi.exe");
            string alt = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), @"NVIDIA Corporation\NVSMI\nvidia-smi.exe");
            if (System.IO.File.Exists(sys)) exe = sys;
            else if (System.IO.File.Exists(alt)) exe = alt;
        }
        catch { }

        int fail = 0;
        while (!stop)
        {
            try
            {
                ProcessStartInfo si = new ProcessStartInfo(exe, "--query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total --format=csv,noheader,nounits");
                si.UseShellExecute = false;
                si.CreateNoWindow = true;
                si.RedirectStandardOutput = true;
                si.RedirectStandardError = true;
                using (Process p = Process.Start(si))
                {
                    if (!p.WaitForExit(3000)) { try { p.Kill(); } catch { } throw new Exception("timeout"); }
                    string o = p.StandardOutput.ReadToEnd();
                    string[] a = o.Split('\n')[0].Split(',');
                    double v;
                    if (a.Length < 4 || !double.TryParse(a[0].Trim(), System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out v))
                        throw new Exception("fmt");
                    GpuV = v;
                    GpuText = a[0].Trim() + "%";
                    GpuSub = a[1].Trim() + " \u00b0C | VRAM " + a[2].Trim() + "/" + a[3].Trim() + " MB";
                    GpuOk = true;
                    fail = 0;
                }
            }
            catch
            {
                fail++;
                if (fail >= 3) { GpuOk = false; return; }
            }
            for (int i = 0; i < 30 && !stop; i++) System.Threading.Thread.Sleep(100);
        }
    }

    void WifiLoop()
    {
        while (!stop)
        {
            try
            {
                ProcessStartInfo si = new ProcessStartInfo("netsh", "wlan show interfaces");
                si.UseShellExecute = false;
                si.CreateNoWindow = true;
                si.RedirectStandardOutput = true;
                si.RedirectStandardError = true;
                using (Process p = Process.Start(si))
                {
                    string o = p.StandardOutput.ReadToEnd();
                    p.WaitForExit(2000);
                    int sig = -1;
                    string ssid = "";
                    foreach (string ln in o.Split('\n'))
                    {
                        System.Text.RegularExpressions.Match m = System.Text.RegularExpressions.Regex.Match(ln, @"^\s*SSID\s*:\s*(.+?)\s*$");
                        if (m.Success) { ssid = m.Groups[1].Value; continue; }
                        if (sig < 0)
                        {
                            System.Text.RegularExpressions.Match m2 = System.Text.RegularExpressions.Regex.Match(ln, @":\s*(\d+)\s*%\s*$");
                            if (m2.Success) sig = int.Parse(m2.Groups[1].Value);
                        }
                    }
                    Ssid = ssid;
                    Wifi = sig;
                }
            }
            catch { Wifi = -1; Ssid = ""; }
            for (int i = 0; i < 40 && !stop; i++) System.Threading.Thread.Sleep(100);
        }
    }
}

// =====================================================================
//  ORION UI  -  คลาสวาดเองสำหรับดีไซน์อวกาศ (การ์ดกระจก / คลื่นขยับ / ไอคอน)
// =====================================================================
public static class Txt
{
    public static float Width(Graphics g, string t, Font f, float sp)
    {
        float w = 0;
        using (StringFormat sf = new StringFormat(StringFormat.GenericTypographic))
        {
            sf.FormatFlags |= StringFormatFlags.MeasureTrailingSpaces;
            foreach (char ch in t) w += g.MeasureString(ch.ToString(), f, 1000, sf).Width + sp;
        }
        return w - sp;
    }

    public static void Spaced(Graphics g, string t, Font f, Color c, float x, float y, float sp)
    {
        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
        using (SolidBrush b = new SolidBrush(c))
        using (StringFormat sf = new StringFormat(StringFormat.GenericTypographic))
        {
            sf.FormatFlags |= StringFormatFlags.MeasureTrailingSpaces;
            foreach (char ch in t)
            {
                string s = ch.ToString();
                g.DrawString(s, f, b, x, y, sf);
                x += g.MeasureString(s, f, 1000, sf).Width + sp;
            }
        }
    }

    public static void SpacedCenter(Graphics g, string t, Font f, Color c, Rectangle r, float sp)
    {
        float w = Width(g, t, f, sp);
        Spaced(g, t, f, c, r.X + (r.Width - w) / 2f, r.Y, sp);
    }
}

public static class Ico
{
    // 0 globe  1 browser  2 gamepad  3 document  4 download  5 bolt  6 cpu  7 signal  8 monitor  9 gauge
    public static void Draw(Graphics g, int k, Rectangle b, Color c)
    {
        float x = b.X, y = b.Y, w = b.Width, h = b.Height;
        using (Pen p = new Pen(c, 1.7f))
        using (SolidBrush sb = new SolidBrush(c))
        {
            p.LineJoin = LineJoin.Round;
            p.StartCap = LineCap.Round;
            p.EndCap = LineCap.Round;
            if (k == 0)
            {
                g.DrawEllipse(p, x, y, w, h);
                g.DrawEllipse(p, x + w * 0.3f, y, w * 0.4f, h);
                g.DrawLine(p, x, y + h / 2, x + w, y + h / 2);
            }
            else if (k == 1)
            {
                using (GraphicsPath gp = Gfx.Round(new Rectangle(b.X, b.Y + 2, b.Width, b.Height - 4), 4))
                    g.DrawPath(p, gp);
                g.DrawLine(p, x, y + h * 0.36f, x + w, y + h * 0.36f);
                g.FillEllipse(sb, x + 3.5f, y + h * 0.22f, 2.2f, 2.2f);
                g.FillEllipse(sb, x + 8f, y + h * 0.22f, 2.2f, 2.2f);
            }
            else if (k == 2)
            {
                using (GraphicsPath gp = Gfx.Round(new Rectangle(b.X, b.Y + (int)(h * 0.22f), b.Width, (int)(h * 0.56f)), 6))
                    g.DrawPath(p, gp);
                g.DrawLine(p, x + w * 0.25f, y + h * 0.42f, x + w * 0.25f, y + h * 0.60f);
                g.DrawLine(p, x + w * 0.16f, y + h * 0.51f, x + w * 0.34f, y + h * 0.51f);
                g.FillEllipse(sb, x + w * 0.62f, y + h * 0.40f, 2.6f, 2.6f);
                g.FillEllipse(sb, x + w * 0.74f, y + h * 0.52f, 2.6f, 2.6f);
            }
                        else if (k == 3)   // RAM
            {
                using (GraphicsPath gp = Gfx.Round(new Rectangle((int)(x + w * 0.1f), (int)(y + h * 0.26f), (int)(w * 0.8f), (int)(h * 0.48f)), 3))
                    g.DrawPath(p, gp);
                for (int i = 0; i < 4; i++)
                {
                    float o = x + w * (0.22f + i * 0.2f);
                    g.DrawLine(p, o, y + h * 0.74f, o, y + h * 0.9f);
                }
                g.DrawLine(p, x + w * 0.2f, y + h * 0.4f, x + w * 0.2f, y + h * 0.6f);
                g.DrawLine(p, x + w * 0.4f, y + h * 0.4f, x + w * 0.4f, y + h * 0.6f);
            }
            else if (k == 4)   // Shield (Firewall)
            {
                PointF[] sh = {
                    new PointF(x + w * 0.5f, y),
                    new PointF(x + w * 0.9f, y + h * 0.18f),
                    new PointF(x + w * 0.9f, y + h * 0.5f),
                    new PointF(x + w * 0.5f, y + h),
                    new PointF(x + w * 0.1f, y + h * 0.5f),
                    new PointF(x + w * 0.1f, y + h * 0.18f)
                };
                g.DrawPolygon(p, sh);
            }
            else if (k == 5)
            {
                PointF[] bolt = {
                    new PointF(x + w * 0.58f, y),
                    new PointF(x + w * 0.18f, y + h * 0.56f),
                    new PointF(x + w * 0.48f, y + h * 0.56f),
                    new PointF(x + w * 0.40f, y + h),
                    new PointF(x + w * 0.82f, y + h * 0.40f),
                    new PointF(x + w * 0.52f, y + h * 0.40f)
                };
                g.DrawPolygon(p, bolt);
            }
            else if (k == 6)
            {
                g.DrawRectangle(p, x + w * 0.22f, y + h * 0.22f, w * 0.56f, h * 0.56f);
                g.DrawRectangle(p, x + w * 0.38f, y + h * 0.38f, w * 0.24f, h * 0.24f);
                for (int i = 0; i < 3; i++)
                {
                    float o = 0.32f + i * 0.18f;
                    g.DrawLine(p, x + w * o, y, x + w * o, y + h * 0.22f);
                    g.DrawLine(p, x + w * o, y + h * 0.78f, x + w * o, y + h);
                    g.DrawLine(p, x, y + h * o, x + w * 0.22f, y + h * o);
                    g.DrawLine(p, x + w * 0.78f, y + h * o, x + w, y + h * o);
                }
            }
            else if (k == 7)
            {
                for (int i = 0; i < 4; i++)
                {
                    float bh = h * (0.28f + i * 0.24f);
                    g.FillRectangle(sb, x + i * (w / 4f) + 1f, y + h - bh, w / 4f - 3f, bh);
                }
            }
            else if (k == 8)
            {
                using (GraphicsPath gp = Gfx.Round(new Rectangle(b.X, b.Y + 1, b.Width, (int)(h * 0.66f)), 3))
                    g.DrawPath(p, gp);
                g.DrawLine(p, x + w * 0.5f, y + h * 0.7f, x + w * 0.5f, y + h * 0.92f);
                g.DrawLine(p, x + w * 0.28f, y + h * 0.94f, x + w * 0.72f, y + h * 0.94f);
            }
            else
            {
                g.DrawArc(p, x, y + 1, w, h, 180f, 180f);
                g.DrawLine(p, x + w * 0.5f, y + h * 0.55f, x + w * 0.76f, y + h * 0.26f);
                g.FillEllipse(sb, x + w * 0.5f - 2f, y + h * 0.55f - 2f, 4f, 4f);
            }
        }
    }
}

// การ์ดกระจกสีม่วง (มีขอบไล่สี) - ใช้เป็นฐานของการ์ดทุกใบ
public class Glass : Control
{
    public Color F1 = Color.FromArgb(225, 54, 30, 104);
    public Color F2 = Color.FromArgb(225, 30, 16, 64);
    public Color B1 = Color.FromArgb(200, 150, 110, 235);
    public Color B2 = Color.FromArgb(150, 86, 160, 140);
    public int Radius = 18;
    public string Cap = "";
    public int CapX = 18;
    public int CapY = 13;
    public bool Art;

    public Glass()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer
            | ControlStyles.SupportsTransparentBackColor | ControlStyles.ResizeRedraw, true);
        BackColor = Color.Transparent;
    }

    protected virtual void PaintInner(Graphics g, GraphicsPath clip) { }

    void DrawArt(Graphics g)
    {
        Random rnd = new Random(5);
        for (int i = 0; i < 70; i++)
        {
            float sx = (float)(rnd.NextDouble() * Width);
            float sy = (float)(rnd.NextDouble() * Height);
            int a = rnd.Next(40, 200);
            using (SolidBrush sbr = new SolidBrush(Color.FromArgb(a, 220, 210, 255)))
                g.FillEllipse(sbr, sx, sy, 1.5f, 1.5f);
        }
        float rad = Height * 1.25f;
        float cx = Width - 36;
        float cy = Height + rad * 0.55f;
        using (GraphicsPath gp = new GraphicsPath())
        {
            gp.AddEllipse(cx - rad * 1.35f, cy - rad * 1.35f, rad * 2.7f, rad * 2.7f);
            using (PathGradientBrush pb = new PathGradientBrush(gp))
            {
                pb.CenterColor = Color.FromArgb(150, 120, 70, 240);
                pb.SurroundColors = new Color[] { Color.FromArgb(0, 120, 70, 240) };
                g.FillPath(pb, gp);
            }
        }
        using (SolidBrush body = new SolidBrush(Color.FromArgb(240, 12, 7, 26)))
            g.FillEllipse(body, cx - rad, cy - rad, rad * 2, rad * 2);
        using (Pen rim = new Pen(Color.FromArgb(220, 168, 120, 255), 2.4f))
            g.DrawEllipse(rim, cx - rad, cy - rad, rad * 2, rad * 2);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        if (Width < 8 || Height < 8) return;
        Rectangle r = new Rectangle(0, 0, Width - 1, Height - 1);
        using (GraphicsPath p = Gfx.Round(r, Radius))
        {
            using (LinearGradientBrush lb = new LinearGradientBrush(r, F1, F2, 35f))
                g.FillPath(lb, p);
            g.SetClip(p);
            if (Art) DrawArt(g);
            PaintInner(g, p);
            g.ResetClip();
            using (LinearGradientBrush bb = new LinearGradientBrush(r, B1, B2, 35f))
            using (Pen pen = new Pen(bb, 1.3f))
                g.DrawPath(pen, p);
        }
        if (Cap.Length > 0)
        {
            using (Font f = new Font("Segoe UI", 7.5f, FontStyle.Bold))
                Txt.Spaced(g, Cap, f, Color.FromArgb(140, 130, 185), CapX, CapY, 1.6f);
        }
    }
}

// การ์ดที่มีคลื่นขยับเหมือนอวกาศอยู่ด้านหลัง
public class WaveCard : Glass
{
    public float Energy = 0.3f;
    float phase;
    Timer tm = new Timer();

    public WaveCard()
    {
        tm.Interval = 40;
        tm.Tick += delegate
        {
            phase += 0.07f;
            if (Visible && IsHandleCreated) Invalidate();
        };
        tm.Start();
    }

    protected override CreateParams CreateParams
    {
        get
        {
            CreateParams cp = base.CreateParams;
            cp.ExStyle |= 0x02000000;     // WS_EX_COMPOSITED: ลดการกระพริบตอนอนิเมชัน
            return cp;
        }
    }

    static LinearGradientBrush Fade(float w, Color c, int a)
    {
        LinearGradientBrush b = new LinearGradientBrush(new PointF(0, 0), new PointF(w, 0), Color.FromArgb(0, c), Color.FromArgb(0, c));
        ColorBlend cb = new ColorBlend(4);
        cb.Positions = new float[] { 0f, 0.14f, 0.86f, 1f };
        cb.Colors = new Color[] { Color.FromArgb(0, c), Color.FromArgb(a, c), Color.FromArgb(a, c), Color.FromArgb(0, c) };
        b.InterpolationColors = cb;
        return b;
    }

    PointF[] Wave(float w, float baseY, float amp, float k1, float sp1, float k2, float sp2)
    {
        int n = (int)(w / 5f) + 2;
        PointF[] pts = new PointF[n];
        for (int i = 0; i < n; i++)
        {
            float x = i * 5f;
            float y = baseY + (float)Math.Sin(x * k1 + phase * sp1) * amp + (float)Math.Sin(x * k2 - phase * sp2) * amp * 0.5f;
            pts[i] = new PointF(x, y);
        }
        return pts;
    }

    protected override void PaintInner(Graphics g, GraphicsPath clip)
    {
        float w = Width, h = Height;
        if (w < 40 || h < 40) return;

        // ฝุ่นดาวลอย
        for (int i = 0; i < 30; i++)
        {
            float px = (i * 53.7f + phase * (10f + (i % 4) * 6f)) % w;
            float py = (i * 37.3f) % h;
            int a = (int)(70 + 60 * Math.Sin(phase * 1.4f + i));
            if (a < 0) a = 0;
            using (SolidBrush sb = new SolidBrush(Color.FromArgb(a, 200, 190, 255)))
                g.FillEllipse(sb, px, py, 1.8f, 1.8f);
        }

        float amp = 6f + 10f * Energy;
        float baseY = h * 0.74f;

        // คลื่นม่วงหลัก + แสงเรือง
        PointF[] a1 = Wave(w, baseY, amp, 0.018f, 1f, 0.007f, 0.6f);
        PointF[] poly = new PointF[a1.Length + 2];
        Array.Copy(a1, 0, poly, 0, a1.Length);
        poly[a1.Length] = new PointF(w, h);
        poly[a1.Length + 1] = new PointF(0, h);
        using (LinearGradientBrush fb = new LinearGradientBrush(new PointF(0, baseY - amp * 2), new PointF(0, h), Color.FromArgb(80, 168, 85, 247), Color.FromArgb(0, 168, 85, 247)))
            g.FillPolygon(fb, poly);
        using (LinearGradientBrush gl = Fade(w, Color.FromArgb(168, 85, 247), 60))
        using (Pen pg = new Pen(gl, 7f))
            g.DrawLines(pg, a1);
        using (LinearGradientBrush ln = Fade(w, Color.FromArgb(192, 132, 252), 255))
        using (Pen pl = new Pen(ln, 2f))
            g.DrawLines(pl, a1);

        // คลื่นเขียวบาง ๆ
        PointF[] a2 = Wave(w, baseY + 7f, amp * 0.6f, 0.026f, -1.4f, 0.011f, 0.9f);
        using (LinearGradientBrush ln2 = Fade(w, Color.FromArgb(74, 222, 128), 150))
        using (Pen pl2 = new Pen(ln2, 1.4f))
            g.DrawLines(pl2, a2);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) { tm.Stop(); tm.Dispose(); }
        base.Dispose(disposing);
    }
}

// การ์ดฟีเจอร์ (ไอคอน + ชื่อ + คำอธิบาย + ป้ายมุมล่าง + ริบบิ้น ACTIVE)
public class FeatureCard : Control
{
    public string Title = "";
    public string Badge = "";
    public int IconKind;
    string sub = "";
    bool active, busy, hover;
    static Font fT = new Font("ไอติม", 12.5f);
    static Font fS = new Font("Segoe UI", 8.5f);
    static Font fB = new Font("Segoe UI", 6.8f, FontStyle.Bold);
    static Font fR = new Font("Segoe UI", 6.2f, FontStyle.Bold);

    public FeatureCard()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer
            | ControlStyles.SupportsTransparentBackColor | ControlStyles.ResizeRedraw | ControlStyles.StandardClick, true);
        BackColor = Color.Transparent;
        Cursor = Cursors.Hand;
    }

    public void SetState(bool a, bool b, string s)
    {
        if (a != active || b != busy || s != sub)
        {
            active = a; busy = b; sub = s;
            Invalidate();
        }
    }

    protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { hover = false; Invalidate(); base.OnMouseLeave(e); }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        Rectangle r = new Rectangle(0, 0, Width - 1, Height - 1);
        if (r.Width < 60 || r.Height < 30) return;
        Color green = Color.FromArgb(74, 222, 128);

        using (GraphicsPath p = Gfx.Round(r, 18))
        {
            Color a1, a2, b1, b2;
            if (active)
            {
                a1 = Color.FromArgb(235, 72, 44, 140); a2 = Color.FromArgb(235, 36, 128, 88);
                b1 = Color.FromArgb(230, 178, 130, 250); b2 = Color.FromArgb(230, 110, 235, 170);
            }
            else
            {
                int al = hover ? 238 : 218;
                a1 = Color.FromArgb(al, 58, 34, 108); a2 = Color.FromArgb(al, 34, 19, 68);
                b1 = Color.FromArgb(hover ? 235 : 175, 150, 110, 235); b2 = Color.FromArgb(hover ? 210 : 115, 96, 150, 150);
            }
            using (LinearGradientBrush lb = new LinearGradientBrush(r, a1, a2, active ? 0f : 35f))
                g.FillPath(lb, p);

            if (active)
            {
                g.SetClip(p);
                float w = Width;
                PointF[] band = { new PointF(w - 64, 0), new PointF(w - 36, 0), new PointF(w, 36), new PointF(w, 64) };
                using (LinearGradientBrush rb = new LinearGradientBrush(new PointF(w - 64, 0), new PointF(w, 64), Color.FromArgb(34, 197, 94), Color.FromArgb(110, 231, 160)))
                    g.FillPolygon(rb, band);
                g.TranslateTransform(w - 25f, 25f);
                g.RotateTransform(45f);
                using (StringFormat sf = new StringFormat())
                {
                    sf.Alignment = StringAlignment.Center;
                    sf.LineAlignment = StringAlignment.Center;
                    g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
                    using (SolidBrush tb = new SolidBrush(Color.FromArgb(10, 44, 24)))
                        g.DrawString("ACTIVE", fR, tb, 0f, 0f, sf);
                }
                g.ResetTransform();
                g.ResetClip();
            }

            using (LinearGradientBrush bb = new LinearGradientBrush(r, b1, b2, 0f))
            using (Pen pen = new Pen(bb, active ? 1.6f : 1.2f))
                g.DrawPath(pen, p);
        }

        // ช่องไอคอน
        Rectangle tile = new Rectangle(16, (Height - 46) / 2, 46, 46);
        Color ic = active ? green : Color.FromArgb(176, 142, 246);
        using (GraphicsPath tp = Gfx.Round(tile, 12))
        {
            using (SolidBrush tf = new SolidBrush(active ? Color.FromArgb(215, 18, 62, 46) : Color.FromArgb(200, 70, 44, 130)))
                g.FillPath(tf, tp);
            using (Pen tb = new Pen(active ? Color.FromArgb(170, 74, 222, 128) : Color.FromArgb(150, 130, 96, 220), 1.2f))
                g.DrawPath(tb, tp);
        }
        Ico.Draw(g, IconKind, new Rectangle(tile.X + 12, tile.Y + 12, 22, 22), ic);

        TextFormatFlags fl = TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix | TextFormatFlags.Left;
        TextRenderer.DrawText(g, Title, fT, new Rectangle(74, 10, Width - 74 - 60, 26), active ? green : Color.White,
            fl | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
        Color sc = busy ? Color.FromArgb(196, 181, 253) : (active ? Color.FromArgb(190, 236, 212) : Color.FromArgb(150, 140, 190));
        TextRenderer.DrawText(g, sub, fS, new Rectangle(74, 38, Width - 74 - 74, 34), sc,
            fl | TextFormatFlags.WordBreak | TextFormatFlags.EndEllipsis);

        // ป้ายมุมล่างขวา
        if (Badge.Length > 0)
        {
            Size bs = TextRenderer.MeasureText(g, Badge, fB, new Size(200, 20), TextFormatFlags.NoPadding);
            int bw = bs.Width + 16;
            Rectangle br = new Rectangle(Width - 16 - bw, Height - 14 - 18, bw, 18);
            using (GraphicsPath bp = Gfx.Round(br, 7))
            {
                using (SolidBrush bf = new SolidBrush(active ? Color.FromArgb(120, 16, 60, 40) : Color.FromArgb(150, 28, 16, 56)))
                    g.FillPath(bf, bp);
                using (Pen bpn = new Pen(active ? Color.FromArgb(160, 74, 222, 128) : Color.FromArgb(130, 140, 100, 230), 1f))
                    g.DrawPath(bpn, bp);
            }
            TextRenderer.DrawText(g, Badge, fB, br, active ? green : Color.FromArgb(196, 181, 253),
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding | TextFormatFlags.SingleLine);
        }
    }
}

// ช่องตัวเลขใน Live Statistics (ไอคอน + ตัวเลขสีเขียว + ป้ายเล็ก)
public class StatTile : Control
{
    public int IconKind;
    public string Caption = "";
    public Color Accent = Color.FromArgb(74, 222, 128);
    string val = "-";
    static Font fV = new Font("ไอติม", 20f, FontStyle.Bold);
    static Font fC = new Font("Segoe UI", 6.8f, FontStyle.Bold);

    public StatTile()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer
            | ControlStyles.SupportsTransparentBackColor | ControlStyles.ResizeRedraw, true);
        BackColor = Color.Transparent;
    }

    public string Value
    {
        get { return val; }
        set { if (val != value) { val = value; Invalidate(); } }
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        Rectangle tile = new Rectangle(0, 3, 38, 38);
        using (GraphicsPath tp = Gfx.Round(tile, 10))
        {
            using (SolidBrush tf = new SolidBrush(Color.FromArgb(200, Accent.R / 6 + 12, Accent.G / 6 + 10, Accent.B / 6 + 24)))
                g.FillPath(tf, tp);
            using (Pen tb = new Pen(Color.FromArgb(150, Accent), 1.2f))
                g.DrawPath(tb, tp);
        }
        Ico.Draw(g, IconKind, new Rectangle(tile.X + 9, tile.Y + 9, 20, 20), Accent);
        TextRenderer.DrawText(g, val, fV, new Rectangle(50, -2, Width - 50, 34), Accent,
            TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding | TextFormatFlags.SingleLine);
        Txt.Spaced(g, Caption, fC, Color.FromArgb(120, 110, 165), 51, 33, 1.4f);
    }
}

// กล่องมืด ๆ ข้างใน (เหมือนช่อง TRIGGER / PICKUP / DELAY)
public class StatBox : Control
{
    public string Caption = "";
    string val = "-", sub = "";
    Color vc = Color.FromArgb(74, 222, 128);
    static Font fV = new Font("ไอติม", 17f, FontStyle.Bold);
    static Font fC = new Font("Segoe UI", 6.8f, FontStyle.Bold);
    static Font fS = new Font("Segoe UI", 8f);

    public StatBox()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer
            | ControlStyles.SupportsTransparentBackColor | ControlStyles.ResizeRedraw, true);
        BackColor = Color.Transparent;
    }

    public string Value { get { return val; } set { if (val != value) { val = value; Invalidate(); } } }
    public string Sub { get { return sub; } set { if (sub != value) { sub = value; Invalidate(); } } }
    public Color ValColor { get { return vc; } set { vc = value; Invalidate(); } }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        Rectangle r = new Rectangle(0, 0, Width - 1, Height - 1);
        if (r.Width < 20 || r.Height < 20) return;
        using (GraphicsPath p = Gfx.Round(r, 12))
        {
            using (SolidBrush b = new SolidBrush(Color.FromArgb(15, 9, 33)))
                g.FillPath(b, p);
            using (Pen pen = new Pen(Color.FromArgb(58, 44, 100), 1.1f))
                g.DrawPath(pen, p);
        }
        Txt.SpacedCenter(g, Caption, fC, Color.FromArgb(120, 110, 165), new Rectangle(0, 8, Width, 12), 1.4f);
        TextRenderer.DrawText(g, val, fV, new Rectangle(0, 20, Width, 28), vc,
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding | TextFormatFlags.SingleLine);
        TextRenderer.DrawText(g, sub, fS, new Rectangle(6, 47, Width - 12, 16), Color.FromArgb(130, 120, 170),
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis);
    }
}

// ป้าย ● ACTIVE มุมขวาบน
public class Pill : Control
{
    string text = "ACTIVE";
    bool on = true;
    static Font fP = new Font("Segoe UI", 7.8f, FontStyle.Bold);

    public Pill()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer
            | ControlStyles.SupportsTransparentBackColor | ControlStyles.ResizeRedraw, true);
        BackColor = Color.Transparent;
    }

    public string Label { get { return text; } set { if (text != value) { text = value; Invalidate(); } } }
    public bool On { get { return on; } set { if (on != value) { on = value; Invalidate(); } } }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        Rectangle r = new Rectangle(0, 0, Width - 1, Height - 1);
        if (r.Width < 30 || r.Height < 12) return;
        Color c = on ? Color.FromArgb(74, 222, 128) : Color.FromArgb(176, 150, 240);
        using (GraphicsPath p = Gfx.Round(r, r.Height / 2))
        {
            using (SolidBrush b = new SolidBrush(on ? Color.FromArgb(200, 14, 52, 36) : Color.FromArgb(200, 40, 26, 78)))
                g.FillPath(b, p);
            using (Pen pen = new Pen(Color.FromArgb(170, c), 1.2f))
                g.DrawPath(pen, p);
        }
        using (SolidBrush db = new SolidBrush(c))
            g.FillEllipse(db, 14, Height / 2 - 3, 6, 6);
        Txt.Spaced(g, text, fP, c, 28, Height / 2 - 7, 1.3f);
    }
}

// เส้นกราฟ Live (เส้นประ + จุดเรืองแสงปลายเส้น)
public class LiveLine : Control
{
    public System.Collections.Generic.List<float> Data = new System.Collections.Generic.List<float>();
    public int Cap = 40;
    public Color Line = Color.FromArgb(192, 132, 252);

    public LiveLine()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer
            | ControlStyles.SupportsTransparentBackColor | ControlStyles.ResizeRedraw, true);
        BackColor = Color.Transparent;
    }

    public void Push(float v)
    {
        Data.Add(v);
        while (Data.Count > Cap) Data.RemoveAt(0);
        Invalidate();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        if (Width < 30 || Height < 20) return;
        float baseY = Height - 10f;
        using (Pen dp = new Pen(Color.FromArgb(120, 130, 100, 210), 1.2f))
        {
            dp.DashStyle = DashStyle.Dot;
            g.DrawLine(dp, 0, baseY, Width, baseY);
        }
        float ex = Width - 8f, ey = baseY;
        if (Data.Count >= 2)
        {
            float mx = 50f;
            foreach (float v in Data) if (v * 1.3f > mx) mx = v * 1.3f;
            float step = (float)(Width - 16) / (Cap - 1);
            PointF[] pts = new PointF[Data.Count];
            for (int i = 0; i < Data.Count; i++)
            {
                float x = (Width - 8f) - (Data.Count - 1 - i) * step;
                float v = Math.Max(0f, Math.Min(Data[i], mx));
                pts[i] = new PointF(x, baseY - (v / mx) * (Height - 22f));
            }
            using (Pen lp = new Pen(Color.FromArgb(220, Line), 1.8f))
            {
                lp.LineJoin = LineJoin.Round;
                g.DrawLines(lp, pts);
            }
            ex = pts[pts.Length - 1].X;
            ey = pts[pts.Length - 1].Y;
        }
        using (SolidBrush hb = new SolidBrush(Color.FromArgb(70, Line)))
            g.FillEllipse(hb, ex - 7, ey - 7, 14, 14);
        using (SolidBrush db = new SolidBrush(Line))
            g.FillEllipse(db, ex - 3.5f, ey - 3.5f, 7, 7);
    }
}
public static class FontKit
{
    static System.Drawing.Text.PrivateFontCollection pfc = new System.Drawing.Text.PrivateFontCollection();
    static string famName;

    public static void LoadDir(string dir)
    {
        if (string.IsNullOrEmpty(dir) || !System.IO.Directory.Exists(dir)) return;
        foreach (string f in System.IO.Directory.GetFiles(dir))
        {
            string ext = System.IO.Path.GetExtension(f).ToLowerInvariant();
            if (ext == ".ttf" || ext == ".otf")
            {
                try { pfc.AddFontFile(f); } catch { }
            }
        }
        if (pfc.Families.Length > 0) famName = pfc.Families[0].Name;
    }

    public static Font Make(float size, bool bold)
    {
        FontStyle st = bold ? FontStyle.Bold : FontStyle.Regular;
        if (famName != null)
        {
            try
            {
                FontFamily ff = pfc.Families[0];
                if (bold && !ff.IsStyleAvailable(FontStyle.Bold)) st = FontStyle.Regular; // กันพังถ้าไม่มี bold weight
                return new Font(ff, size, st);
            }
            catch { }
        }
        return new Font("Segoe UI", size, st); // fallback ถ้าไม่มีฟอนต์ไทย
    }

    public static Font MakePixel(float sizePx, bool bold)
    {
        FontStyle st = bold ? FontStyle.Bold : FontStyle.Regular;
        if (famName != null)
        {
            try { return new Font(pfc.Families[0], sizePx, st, GraphicsUnit.Pixel); }
            catch { }
        }
        return new Font("Segoe UI", sizePx, st, GraphicsUnit.Pixel);
    }
}
'@
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition $cs -Language CSharp -ErrorAction Stop

# =====================================================================
#  หน้า Login (ใส่คีย์)  -  คีย์ที่ใส่ได้มีคีย์เดียว แก้ได้ที่บรรทัดข้างล่าง
# =====================================================================
$secret = 'MySuperSecret_xK92mQ7pL4'

function Get-HwId {
    $a = (Get-CimInstance Win32_ComputerSystemProduct).UUID
    $b = (Get-CimInstance Win32_BaseBoard).SerialNumber
    $c = (Get-CimInstance Win32_Processor | Select-Object -First 1).ProcessorId
    $raw = "$a|$b|$c"
    $sha = [Security.Cryptography.SHA256]::Create()
    $h = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($raw))
    return ([BitConverter]::ToString($h).Replace('-', '').Substring(0, 16))
}

function Get-KeyFor([string]$hw) {
    $hm = New-Object Security.Cryptography.HMACSHA256
    $hm.Key = [Text.Encoding]::UTF8.GetBytes($secret)
    $h = $hm.ComputeHash([Text.Encoding]::UTF8.GetBytes($hw))
    $hex = [BitConverter]::ToString($h).Replace('-', '').Substring(0, 20)
    return ($hex -replace '(.{5})(?!$)', '$1-')
}

$myHw = Get-HwId
$validKey = Get-KeyFor $myHw

# ---------- ระบบจำคีย์ + จำการตั้งค่า (แยกตาม Machine ID) ----------
$script:cfgDir  = Join-Path $env:APPDATA 'FlowSkipper'
$script:cfgFile = Join-Path $script:cfgDir 'config.json'
$script:cfgReady = $false

function Load-Cfg {
    $c = @{ remember = $true; licenses = @{}; settings = @{} }
    try {
        if (Test-Path -LiteralPath $script:cfgFile) {
            $j = Get-Content -LiteralPath $script:cfgFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($null -ne $j.remember) { $c.remember = [bool]$j.remember }
            if ($j.licenses) {
                foreach ($p in $j.licenses.PSObject.Properties) { $c.licenses[$p.Name] = [string]$p.Value }
            }
            if ($j.settings) {
                foreach ($p in $j.settings.PSObject.Properties) {
                    $h = @{}
                    foreach ($q in $p.Value.PSObject.Properties) { $h[$q.Name] = [bool]$q.Value }
                    $c.settings[$p.Name] = $h
                }
            }
        }
    } catch { }
    return $c
}

function Save-Cfg {
    try {
        if (-not (Test-Path -LiteralPath $script:cfgDir)) { [void](New-Item -ItemType Directory -Path $script:cfgDir -Force) }
        $o = [ordered]@{ remember = [bool]$script:cfg.remember; licenses = $script:cfg.licenses; settings = $script:cfg.settings }
        ($o | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $script:cfgFile -Encoding UTF8
    } catch {
        try { [IO.File]::WriteAllText((Join-Path $env:TEMP 'flow_cfg_error.txt'), ($_ | Out-String)) } catch { }
    }
}

function Protect-Str([string]$s) {
    return (ConvertTo-SecureString $s -AsPlainText -Force | ConvertFrom-SecureString)
}

function Unprotect-Str([string]$s) {
    $ss = ConvertTo-SecureString $s
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}

function Save-Settings {
    if (-not $script:cfgReady) { return }
    if (-not $script:cfg.remember) { return }
    $h = @{}
    foreach ($k in @('net', 'web', 'game', 'mem', 'fw')) { $h[$k] = [bool]$state[$k] }
    $script:cfg.settings[$myHw] = $h
    Save-Cfg
}

$script:cfg = Load-Cfg

function Get-LicPaths {
    $p = New-Object System.Collections.ArrayList
    [void]$p.Add((Join-Path $script:cfgDir 'license.key'))
    if ($env:BATDIR) { [void]$p.Add((Join-Path $env:BATDIR 'license.key')) }
    return @($p)
}

function Test-SavedLicense {
    foreach ($f in (Get-LicPaths)) {
        try {
            if (Test-Path -LiteralPath $f) {
                $line = Get-Content -LiteralPath $f -Raw -Encoding UTF8
                if ($line) {
                    $parts = $line.Trim().Split('|')
                    if ($parts.Count -ge 2 -and $parts[0] -ceq $myHw -and $parts[1] -ceq $validKey) { return $true }
                }
            }
        } catch { }
    }
    return $false
}

function Save-License {
    $err = New-Object System.Collections.ArrayList
    foreach ($f in (Get-LicPaths)) {
        try {
            $d = Split-Path -Parent $f
            if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }
            [IO.File]::WriteAllText($f, ($myHw + '|' + $validKey), (New-Object Text.UTF8Encoding $false))
        } catch { [void]$err.Add($f + ' : ' + $_.Exception.Message) }
    }
    if ($err.Count -gt 0) {
        try { [IO.File]::WriteAllLines((Join-Path $env:TEMP 'flow_lic_error.txt'), [string[]]@($err)) } catch { }
    }
}

$script:isAdmin = $false
$script:adminHw = '8DF5000FB89F610F'
$script:adminFile = Join-Path $script:cfgDir 'admin.key'
 
function Get-AdminToken {
    $hm = New-Object Security.Cryptography.HMACSHA256
    $hm.Key = [Text.Encoding]::UTF8.GetBytes($secret)
    $h = $hm.ComputeHash([Text.Encoding]::UTF8.GetBytes('ADMIN|' + $myHw))
    return ([BitConverter]::ToString($h).Replace('-', ''))
}
 
function Test-AdminToken {
    if ($myHw -cne $script:adminHw) { return $false }
    try {
        if (Test-Path -LiteralPath $script:adminFile) {
            $t = (Get-Content -LiteralPath $script:adminFile -Raw -Encoding UTF8).Trim()
            return ($t -ceq (Get-AdminToken))
        }
    } catch { }
    return $false
}
 
function Save-AdminToken {
    try {
        if (-not (Test-Path -LiteralPath $script:cfgDir)) { [void](New-Item -ItemType Directory -Path $script:cfgDir -Force) }
        [IO.File]::WriteAllText($script:adminFile, (Get-AdminToken), (New-Object Text.UTF8Encoding $false))
    } catch { }
}

# ถ้าเคยใส่คีย์ถูกต้องบนเครื่องนี้แล้ว ให้ข้ามหน้า Login
# ถ้าเคยใส่คีย์ถูกต้องบนเครื่องนี้แล้ว ให้ข้ามหน้า Login
$autoOk = $false
try { $autoOk = Test-SavedLicense } catch { }

if (-not $autoOk) {
    try {
        $enc = $script:cfg.licenses[$myHw]
        if ($enc) { if ((Unprotect-Str $enc) -ceq $validKey) { $autoOk = $true } }
    } catch { }
}
if ($autoOk) { try { Save-License } catch { } }
if ($autoOk -and (Test-AdminToken)) { $script:isAdmin = $true }
# ---------- โหลดฟอนต์ (หาใน fonts\ และโฟลเดอร์เดียวกับไฟล์ .bat) ----------
$fontSig = '[DllImport("gdi32.dll", CharSet = CharSet.Unicode)] public static extern int AddFontResourceEx(string f, uint fl, IntPtr r);' + "`n" +
           '[DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(IntPtr h, uint m, IntPtr w, IntPtr l, uint f, uint t, out IntPtr res);'
Add-Type -Namespace Win -Name Fnt -MemberDefinition $fontSig
$fontLog = New-Object System.Collections.ArrayList
try {
    [void]$fontLog.Add('BATDIR=' + $env:BATDIR)
    $dirs = @()
    if ($env:BATDIR) { $dirs += (Join-Path $env:BATDIR 'fonts'); $dirs += $env:BATDIR }
    $loaded = 0
    foreach ($fd in $dirs) {
        if (-not (Test-Path -LiteralPath $fd)) { continue }
        foreach ($ff in (Get-ChildItem -LiteralPath $fd -File | Where-Object { $_.Extension -match '^\.(ttf|otf)$' })) {
            $r = [Win.Fnt]::AddFontResourceEx($ff.FullName, 0, [IntPtr]::Zero)
            [void]$fontLog.Add($ff.FullName + ' -> ' + $r)
            $loaded += $r
        }
    }
    if ($loaded -gt 0) {
        $res = [IntPtr]::Zero
        [void][Win.Fnt]::SendMessageTimeout([IntPtr]0xFFFF, 0x1D, [IntPtr]::Zero, [IntPtr]::Zero, 2, 1000, [ref]$res)
    }
    foreach ($nm in @('ไอติม', 'ไอติม Bold')) {
        try { [void](New-Object Drawing.FontFamily($nm)); [void]$fontLog.Add('OK family: ' + $nm) }
        catch { [void]$fontLog.Add('NOT FOUND family: ' + $nm) }
    }
} catch { [void]$fontLog.Add('ERR ' + $_.Exception.Message) }
try { [IO.File]::WriteAllLines((Join-Path $env:TEMP 'fam_font.txt'), [string[]]$fontLog) } catch { }

$cWhite = [Drawing.Color]::White
$cLav   = [Drawing.Color]::FromArgb(196, 181, 253)
$cMute  = [Drawing.Color]::FromArgb(128, 120, 160)
$cErr   = [Drawing.Color]::FromArgb(248, 113, 113)

$login = New-Object GradForm
$login.Radius = 14
$login.BgA = [Drawing.Color]::FromArgb(9, 5, 20)
$login.BgB = [Drawing.Color]::FromArgb(30, 12, 60)
$login.Glows = $false
$login.Text = 'License'
$login.ClientSize = New-Object Drawing.Size(448, 356)
$login.StartPosition = 'CenterScreen'
$login.KeyPreview = $true
$login.Font = New-Object Drawing.Font('Segoe UI', 10)

# โลโก้ (ถ้ามีไฟล์ logo.png วางข้าง ๆ ไฟล์ .bat จะใช้รูปนั้นแทน)

$logoB64 = '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'
 
$lLogo = New-Object Windows.Forms.PictureBox
$lLogo.Size = New-Object Drawing.Size(88, 88)
$lLogo.Location = New-Object Drawing.Point(180, 18)
$lLogo.SizeMode = 'Zoom'
$lLogo.BackColor = [Drawing.Color]::Transparent
try {
    $bytes = [Convert]::FromBase64String($logoB64)
    $ms = New-Object IO.MemoryStream(,$bytes)
    $lLogo.Image = [Drawing.Image]::FromStream($ms)
} catch { }
try {
    if ($lLogo.Image) { $script:logoBmp = New-Object Drawing.Bitmap($lLogo.Image) }
} catch { }
if ($script:logoBmp) {
    $lLogo.Image = $script:logoBmp
    try { $login.Icon = [Drawing.Icon]::FromHandle($script:logoBmp.GetHicon()) } catch { }
}

$lTitle = New-Object Windows.Forms.Label
$lTitle.Text = 'FROSTX'
$lTitle.Font = New-Object Drawing.Font('ไอติม', 22, [Drawing.FontStyle]::Bold)
$lTitle.ForeColor = $cWhite
$lTitle.BackColor = [Drawing.Color]::Transparent
$lTitle.TextAlign = 'MiddleCenter'
$lTitle.Size = New-Object Drawing.Size(448, 44)
$lTitle.Location = New-Object Drawing.Point(0, 110)
$lTitle.Add_MouseDown({ [Gfx]::Drag($login.Handle) })

$lSub = New-Object Windows.Forms.Label
$lSub.Text = 'FROSTX unlock by.Fam .'
$lSub.Font = New-Object Drawing.Font('Segoe UI', 9.5)
$lSub.ForeColor = $cMute
$lSub.BackColor = [Drawing.Color]::Transparent
$lSub.TextAlign = 'MiddleCenter'
$lSub.Size = New-Object Drawing.Size(448, 24)
$lSub.Location = New-Object Drawing.Point(0, 154)
$lSub.Add_MouseDown({ [Gfx]::Drag($login.Handle) })

$lClose = New-Object Windows.Forms.Label
$lClose.Text = [string][char]0x2715
$lClose.Font = New-Object Drawing.Font('Segoe UI Symbol', 11)
$lClose.ForeColor = $cMute
$lClose.BackColor = [Drawing.Color]::Transparent
$lClose.Cursor = [Windows.Forms.Cursors]::Hand
$lClose.Size = New-Object Drawing.Size(32, 32)
$lClose.TextAlign = 'MiddleCenter'
$lClose.Location = New-Object Drawing.Point(404, 10)
$lClose.Add_MouseEnter({ $lClose.ForeColor = $cWhite })
$lClose.Add_MouseLeave({ $lClose.ForeColor = $cMute })
$lClose.Add_Click({ $login.DialogResult = [Windows.Forms.DialogResult]::Cancel })

$keyBox = New-Object InputBox
$keyBox.Placeholder = 'Enter license key'
$keyBox.Size = New-Object Drawing.Size(368, 46)
$keyBox.Location = New-Object Drawing.Point(40, 196)
$keyBox.Box.PasswordChar = '*'

$ctx = New-Object Windows.Forms.ContextMenuStrip
$miPaste = $ctx.Items.Add('Paste')
$miPaste.Add_Click({ try { $keyBox.Box.Paste() } catch { } })
$miCopy = $ctx.Items.Add('Copy')
$miCopy.Add_Click({ try { if ($keyBox.Box.SelectionLength -gt 0) { $keyBox.Box.Copy() } } catch { } })
$miAll = $ctx.Items.Add('Select All')
$miAll.Add_Click({ $keyBox.Box.SelectAll() })
$keyBox.Box.ContextMenuStrip = $ctx

$loginBtn = New-Object GradButton
$loginBtn.Text = 'Login'
$loginBtn.RightText = [string][char]0x2192
$loginBtn.C1 = [Drawing.Color]::FromArgb(109, 40, 217)
$loginBtn.C2 = [Drawing.Color]::FromArgb(34, 170, 110)
$loginBtn.Size = New-Object Drawing.Size(368, 46)
$loginBtn.Location = New-Object Drawing.Point(40, 254)

$errLbl = New-Object Windows.Forms.Label
$errLbl.Text = 'Invalid license key'
$errLbl.Font = New-Object Drawing.Font('Segoe UI', 9.5)
$errLbl.ForeColor = $cErr
$errLbl.BackColor = [Drawing.Color]::Transparent
$errLbl.TextAlign = 'MiddleCenter'
$errLbl.Size = New-Object Drawing.Size(448, 22)
$errLbl.Location = New-Object Drawing.Point(0, 306)
$errLbl.Visible = $false

$tagLbl = New-Object Windows.Forms.Label
$tagLbl.Font = New-Object Drawing.Font('Segoe UI', 9)
$tagLbl.ForeColor = $cMute
$tagLbl.BackColor = [Drawing.Color]::Transparent
$tagLbl.Text = 'Machine ID: ' + $myHw
$tagLbl.TextAlign = 'MiddleCenter'
$tagLbl.Size = New-Object Drawing.Size(448, 22)
$tagLbl.Location = New-Object Drawing.Point(0, 324)
$tagLbl.Cursor = [Windows.Forms.Cursors]::Hand

$script:tagLbl = $tagLbl
$script:myHw = $myHw
$script:cMute = $cMute

$script:hwTm = New-Object Windows.Forms.Timer
$script:hwTm.Interval = 1500
$script:hwTm.Add_Tick({
    $script:hwTm.Stop()
    $script:tagLbl.Text = 'Machine ID: ' + $script:myHw
    $script:tagLbl.ForeColor = $script:cMute
})

$tagLbl.Add_Click({
    try {
        [Windows.Forms.Clipboard]::SetText($script:myHw)
        $script:tagLbl.Text = 'Copied! ' + $script:myHw
        $script:tagLbl.ForeColor = [Drawing.Color]::FromArgb(74, 222, 128)
        $script:hwTm.Stop()
        $script:hwTm.Start()
    } catch { }
})

$hwMenu = New-Object Windows.Forms.ContextMenuStrip
$miHw = $hwMenu.Items.Add('Copy Machine ID')
$miHw.Add_Click({ try { [Windows.Forms.Clipboard]::SetText($script:myHw) } catch { } })
$tagLbl.ContextMenuStrip = $hwMenu
$miHw.Add_Click({ try { [Windows.Forms.Clipboard]::SetText($script:myHw) } catch { } })

$hwMenu = New-Object Windows.Forms.ContextMenuStrip
$miHw = $hwMenu.Items.Add('Copy Machine ID')
$miHw.Add_Click({ try { [Windows.Forms.Clipboard]::SetText($myHw) } catch { } })
$tagLbl.ContextMenu = $null
$tagLbl.ContextMenuStrip = $hwMenu

$login.Controls.AddRange(@($lLogo, $lTitle, $lSub, $lClose, $keyBox, $loginBtn, $errLbl, $tagLbl))
$keyBox.Box.Add_KeyDown({ if ($script:soundOn) { $script:sndKey.Play() } })

# เอฟเฟกต์สั่นเมื่อใส่คีย์ผิด
$offs = @(12, -12, 9, -9, 6, -6, 3, -3, 0)
$script:shakeI = 0
$script:baseLeft = 0
$shake = New-Object Windows.Forms.Timer
$shake.Interval = 28
$shake.Add_Tick({
    if ($script:shakeI -ge $offs.Count) { $shake.Stop(); return }
    $login.Left = $script:baseLeft + $offs[$script:shakeI]
    $script:shakeI++
})

function DoLogin {
    $t = $keyBox.Box.Text.Trim()
    $adminLogin = ($t -ceq 'adminbypass') -and ($myHw -ceq $script:adminHw)
    if ($t -ceq $validKey -or $adminLogin) {
        if ($adminLogin) { $script:isAdmin = $true }
        $login.DialogResult = [Windows.Forms.DialogResult]::OK
    } else {
        $keyBox.Error = $true
        $keyBox.Invalidate()
        $errLbl.Visible = $true
        if (-not $shake.Enabled) { $script:baseLeft = $login.Left }
        $script:shakeI = 0
        $shake.Start()
        $keyBox.Box.SelectAll()
        $keyBox.Box.Focus()
    }
}

$keyBox.Box.Add_TextChanged({
    if ($keyBox.Error) {
        $keyBox.Error = $false
        $keyBox.Invalidate()
        $errLbl.Visible = $false
    }
})
$keyBox.Box.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq 'Enter') { $e.SuppressKeyPress = $true; DoLogin; return }
    if ($e.Control -and $e.KeyCode -eq 'V') {
        $e.SuppressKeyPress = $true
        try { $keyBox.Box.Paste() } catch { }
    }
    elseif ($e.Control -and $e.KeyCode -eq 'A') {
        $e.SuppressKeyPress = $true
        $keyBox.Box.SelectAll()
    }
    elseif ($e.Control -and $e.KeyCode -eq 'C') {
        $e.SuppressKeyPress = $true
        try { if ($keyBox.Box.SelectionLength -gt 0) { $keyBox.Box.Copy() } } catch { }
    }
})
$loginBtn.Add_Click({ DoLogin })
$login.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq 'Escape') { $login.DialogResult = [Windows.Forms.DialogResult]::Cancel }
})
$login.Add_Shown({ $keyBox.Box.Focus() })

if (-not $autoOk) {
    $loginResult = $login.ShowDialog()
    if ($loginResult -ne [Windows.Forms.DialogResult]::OK) { exit }
    try { Save-License } catch { }
    if ($script:isAdmin) { Save-AdminToken }
}
$login.Dispose()

# =====================================================================
#  หน้าหลัก (แสดงหลังใส่คีย์ถูกต้อง)
#  - แถว 1: กราฟเรียลไทม์ CPU / RAM / GPU / Ping / WiFi   (อ่านค่าใน thread เบื้องหลัง)
#  - แถว 2: Speed Test (Ping / Jitter / Download / Upload + ISP)
#  - แถว 3: ปุ่มเปิด/ปิด 4 หัวข้อ                           (งานหนักทำเบื้องหลัง ไม่ค้าง)
#  - แถว 4: ปุ่มดูรหัส WiFi
# =====================================================================
$script:loading = $false

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    [Windows.Forms.MessageBox]::Show('ต้องเปิดแบบ Run as administrator เพื่อสั่ง Windows Firewall ได้', 'Fam Bypass') | Out-Null
    exit
}

# ---------------------------------------------------------------------
#  ฟังก์ชัน Firewall  (เก็บเป็นข้อความ เพื่อใช้ทั้งในหน้าต่างหลัก และใน runspace เบื้องหลัง)
# ---------------------------------------------------------------------
$fwFuncs = @'
$Grp = @{ net = 'FlowSkipper-Net'; web = 'FlowSkipper-Web'; game = 'FlowSkipper-Game' }

function Get-FwPolicy { return (New-Object -ComObject HNetCfg.FwPolicy2) }

function Get-GroupRuleNames([string]$group) {
    $names = New-Object System.Collections.ArrayList
    foreach ($r in (Get-FwPolicy).Rules) {
        if ($r.Grouping -eq $group) { [void]$names.Add($r.Name) }
    }
    return ,$names
}

function Clear-Group([string]$group) {
    $pol = Get-FwPolicy
    $names = Get-GroupRuleNames $group
    foreach ($n in $names) { try { $pol.Rules.Remove($n) } catch { } }
}

function Add-BlockRule($pol, [string]$group, [string]$name, [string]$exe) {
    $r = New-Object -ComObject HNetCfg.FWRule
    $r.Name = $name
    $r.Grouping = $group
    $r.Description = 'Created by Fam Bypass'
    if ($exe) { $r.ApplicationName = $exe }
    $r.Direction = 2
    $r.Action = 0
    $r.Profiles = 2147483647
    $r.Enabled = $true
    [void]$pol.Rules.Add($r)
}

function Find-Exes($roots, [int]$depth) {
    $nameSkip = '(?i)(unins|crash|redist|vc_?redist|dxsetup|dxwebsetup|dotnet|installer|setup|oalinst|notification_helper|7z)'
    $dirSkip  = '(?i)(\\_?commonredist|\\redist|\\directx|\\vcredist|\\steamworks shared)'
    $out = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($r in $roots) {
        if (-not $r) { continue }
        if ($r -like '*.exe') {
            if (Test-Path -LiteralPath $r) { [void]$out.Add($r) }
            continue
        }
        if (-not (Test-Path -LiteralPath $r)) { continue }
        Get-ChildItem -LiteralPath $r -Filter *.exe -File -Recurse -Depth $depth -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch $nameSkip -and $_.DirectoryName -notmatch $dirSkip } |
            ForEach-Object { [void]$out.Add($_.FullName) }
    }
    return @($out)
}

function Get-GameRoots {
    $r = New-Object System.Collections.ArrayList
    $drives = @(Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Za-z]:\\$' } | ForEach-Object { $_.Root })
    $rel = @(
        'Steam', 'SteamLibrary', 'Epic Games', 'Riot Games', 'Garena', 'Games', 'Game', 'XboxGames',
        'Program Files\Steam', 'Program Files (x86)\Steam', 'Program Files\Epic Games', 'Program Files (x86)\Epic Games',
        'Program Files\Riot Games', 'Program Files (x86)\Garena', 'Program Files\Garena',
        'Program Files (x86)\Battle.net', 'Program Files (x86)\Blizzard Entertainment',
        'Program Files\Ubisoft', 'Program Files (x86)\Ubisoft', 'Program Files\EA Games', 'Program Files (x86)\Origin Games',
        'Program Files\Electronic Arts', 'Program Files (x86)\Origin', 'Program Files\Rockstar Games',
        'Program Files (x86)\GOG Galaxy', 'GOG Games', 'Program Files\HoYoPlay', 'HoYoPlay', 'Genshin Impact', 'Wuthering Waves',
        'Program Files (x86)\Minecraft Launcher', 'Program Files\Roblox', 'Program Files (x86)\Roblox',
        'Program Files\BlueStacks_nxt', 'Program Files\BlueStacks', 'LDPlayer', 'LDPlayer9', 'Program Files\TxGameAssistant'
    )
    foreach ($d in $drives) { foreach ($n in $rel) { [void]$r.Add((Join-Path $d $n)) } }

    foreach ($x in @(
        (Join-Path $env:LOCALAPPDATA 'Roblox'), (Join-Path $env:APPDATA '.minecraft'),
        (Join-Path $env:LOCALAPPDATA 'Riot Games'), (Join-Path $env:LOCALAPPDATA 'Programs\Garena'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Epic Games')
    )) { [void]$r.Add($x) }

    try {
        $sp = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath
        if ($sp) {
            $sp = $sp -replace '/', '\'
            [void]$r.Add($sp)
            $vdf = Join-Path $sp 'steamapps\libraryfolders.vdf'
            if (Test-Path -LiteralPath $vdf) {
                foreach ($m in (Select-String -LiteralPath $vdf -Pattern '"path"\s+"([^"]+)"')) {
                    $lib = $m.Matches[0].Groups[1].Value -replace '\\\\', '\'
                    [void]$r.Add((Join-Path $lib 'steamapps\common'))
                }
            }
        }
    } catch { }

    if ($env:BATDIR) {
        $f = Join-Path $env:BATDIR 'games.txt'
        if (Test-Path -LiteralPath $f) {
            foreach ($l in (Get-Content -LiteralPath $f -Encoding UTF8)) {
                $q = $l.Trim().Trim('"')
                if ($q -and -not $q.StartsWith('#')) { [void]$r.Add($q) }
            }
        }
    }
    return @($r | Select-Object -Unique)
}

function Get-GameExes { return (Find-Exes (Get-GameRoots) 6) }

function Get-BrowserExes {
    $pf = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }
    $la = $env:LOCALAPPDATA
    $c = New-Object System.Collections.ArrayList
    foreach ($b in $pf) {
        foreach ($x in @('Google\Chrome\Application\chrome.exe', 'Microsoft\Edge\Application\msedge.exe', 'Mozilla Firefox\firefox.exe',
                         'BraveSoftware\Brave-Browser\Application\brave.exe', 'Opera\opera.exe', 'Opera GX\opera.exe', 'Vivaldi\Application\vivaldi.exe')) {
            [void]$c.Add((Join-Path $b $x))
        }
    }
    foreach ($x in @('Google\Chrome\Application\chrome.exe', 'Programs\Opera\opera.exe', 'Programs\Opera GX\opera.exe', 'Vivaldi\Application\vivaldi.exe')) {
        [void]$c.Add((Join-Path $la $x))
    }
    return @($c | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -Unique)
}

function Enable-Block([string]$k) {
    $group = $Grp[$k]
    Clear-Group $group
    $pol = Get-FwPolicy
    if ($k -eq 'net') {
        Add-BlockRule $pol $group 'Fam Bypass [net] block all outbound' $null
        return 1
    }
    if ($k -eq 'web') { $exes = Get-BrowserExes } else { $exes = Get-GameExes }
    $n = 0
    foreach ($e in $exes) {
        Add-BlockRule $pol $group ('Fam Bypass [' + $k + '] ' + $e) $e
        $n++
    }
    return $n
}
'@
Invoke-Expression $fwFuncs
function Test-FwAllOff {
    try {
        $p = Get-FwPolicy
        foreach ($pr in 1, 2, 4) { if ($p.FirewallEnabled($pr)) { return $false } }
        return $true
    } catch { return $false }
}

function Set-FwState([bool]$on) {
    $s = 'off'
    if ($on) { $s = 'on' }
    $null = & netsh advfirewall set allprofiles state $s 2>&1
    return ($LASTEXITCODE -eq 0)
}

# งานที่รันใน runspace เบื้องหลัง (ตัวแปร $mode / $k ถูกส่งเข้ามาจากหน้าต่างหลัก)
$fwWorker = @'
[Threading.Thread]::CurrentThread.Priority = 'BelowNormal'
try {
    if ($mode -eq 'on') { $c = @(Enable-Block $k)[-1]; 'OK:' + $c }
    else { Clear-Group $Grp[$k]; 'OK:0' }
} catch { 'ERR:' + $_.Exception.Message }
'@
$fwCode = $fwFuncs + "`r`n" + $fwWorker

# ---------------------------------------------------------------------
#  อ่านรหัส WiFi  (ใช้ netsh export -> อ่านจาก XML  เร็วกว่าและไม่ขึ้นกับภาษา Windows)
# ---------------------------------------------------------------------
$wifiFuncs = @'
function Get-WifiPasswords {
    $tmp = Join-Path $env:TEMP ('fs_wifi_' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $tmp -Force)
    $rows = New-Object System.Collections.Generic.List[string]
    try {
        $null = netsh wlan export profile key=clear folder="$tmp" 2>$null
        foreach ($f in (Get-ChildItem -LiteralPath $tmp -Filter *.xml -ErrorAction SilentlyContinue)) {
            try {
                [xml]$x = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
                $n = $x.WLANProfile.name
                $p = $x.WLANProfile.MSM.security.sharedKey.keyMaterial
                if (-not $p) { $p = '(ไม่มีรหัส / เครือข่ายเปิด / แบบองค์กร)' }
                [void]$rows.Add($n + '   ->   ' + $p)
            } catch { }
        }
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
    return $rows
}
'@
$wifiCode = $wifiFuncs + "`r`nGet-WifiPasswords"

# ---------------------------------------------------------------------
#  ตัวรันงานเบื้องหลัง (runspace)  -  UI ไม่ค้างระหว่างรอ
# ---------------------------------------------------------------------
$script:bgJobs = New-Object System.Collections.ArrayList
$bgTm = New-Object Windows.Forms.Timer
$bgTm.Interval = 150
$bgTm.Add_Tick({
    foreach ($j in @($script:bgJobs)) {
        if (-not $j.H.IsCompleted) { continue }
        $out = @()
        try { $out = @($j.Ps.EndInvoke($j.H)) } catch { $out = @('ERR:' + $_.Exception.Message) }
        try { $j.Ps.Dispose(); $j.Rs.Dispose() } catch { }
        [void]$script:bgJobs.Remove($j)
        try { & $j.Done $out $j.Ctx } catch { }
    }
    if ($script:bgJobs.Count -eq 0) { $bgTm.Stop() }
})

function Start-Bg([string]$code, [hashtable]$vars, [scriptblock]$done, $ctx) {
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = [Threading.ApartmentState]::STA
    $rs.Open()
    foreach ($key in $vars.Keys) { $rs.SessionStateProxy.SetVariable($key, $vars[$key]) }
    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($code)
    $h = $ps.BeginInvoke()
    [void]$script:bgJobs.Add(@{ Ps = $ps; Rs = $rs; H = $h; Done = $done; Ctx = $ctx })
    $bgTm.Start()
}
function Show-WifiPasswords {
    $wf = New-Object GradForm
    $wf.Radius = 14
    $wf.BgA = [Drawing.Color]::FromArgb(15, 12, 24)
    $wf.BgB = [Drawing.Color]::FromArgb(36, 24, 64)
    $wf.Glows = $false
    $wf.Text = 'Saved WiFi'
    $wf.ClientSize = New-Object Drawing.Size(460, 420)
    $wf.StartPosition = 'CenterScreen'
    $wf.KeyPreview = $true
    $wf.Font = New-Object Drawing.Font('Segoe UI', 10)

    $wTitle = New-Object Windows.Forms.Label
    $wTitle.Text = 'รหัส WiFi ที่บันทึกไว้'
    $wTitle.Font = New-Object Drawing.Font('ไอติม', 16, [Drawing.FontStyle]::Bold)
    $wTitle.ForeColor = $cWhite
    $wTitle.BackColor = [Drawing.Color]::Transparent
    $wTitle.AutoSize = $true
    $wTitle.Location = New-Object Drawing.Point(24, 20)
    $wTitle.Add_MouseDown({ [Gfx]::Drag($wf.Handle) })

    $wClose = New-Object Windows.Forms.Label
    $wClose.Text = [string][char]0x2715
    $wClose.Font = New-Object Drawing.Font('Segoe UI Symbol', 12)
    $wClose.ForeColor = $cLav
    $wClose.BackColor = [Drawing.Color]::Transparent
    $wClose.Cursor = [Windows.Forms.Cursors]::Hand
    $wClose.Size = New-Object Drawing.Size(32, 32)
    $wClose.TextAlign = 'MiddleCenter'
    $wClose.Location = New-Object Drawing.Point(412, 16)
    $wClose.Add_MouseEnter({ $wClose.ForeColor = $cWhite })
    $wClose.Add_MouseLeave({ $wClose.ForeColor = $cLav })
    $wClose.Add_Click({ $wf.Close() })

    $txt = New-Object Windows.Forms.TextBox
    $txt.Multiline = $true
    $txt.ReadOnly = $true
    $txt.ScrollBars = 'Vertical'
    $txt.BorderStyle = 'None'
    $txt.BackColor = [Drawing.Color]::FromArgb(22, 17, 38)
    $txt.ForeColor = $cWhite
    $txt.Font = New-Object Drawing.Font('Consolas', 10)
    $txt.Size = New-Object Drawing.Size(412, 280)
    $txt.Location = New-Object Drawing.Point(24, 64)
    $txt.Text = 'กำลังโหลด...'

    $copyBtn = New-Object GradButton
    $copyBtn.Text = 'คัดลอกทั้งหมด'
    $copyBtn.C1 = [Drawing.Color]::FromArgb(14, 165, 233)
    $copyBtn.C2 = [Drawing.Color]::FromArgb(59, 130, 246)
    $copyBtn.Size = New-Object Drawing.Size(412, 44)
    $copyBtn.Location = New-Object Drawing.Point(24, 356)
    $copyBtn.Add_Click({ try { [Windows.Forms.Clipboard]::SetText($txt.Text) } catch { } })

    $wf.Controls.AddRange(@($wTitle, $wClose, $txt, $copyBtn))
    $wf.Add_KeyDown({
        param($sender, $e)
        if ($e.KeyCode -eq 'Escape') { $wf.Close() }
    })

    Start-Bg $wifiCode @{} {
        param($out, $ctx)
        if ($ctx.Form.IsDisposed) { return }
        $rows = @($out | Where-Object { $_ })
        if ($rows.Count -eq 0) { $ctx.Txt.Text = 'ไม่พบ WiFi ที่บันทึกไว้ในเครื่องนี้'; return }
        $ctx.Txt.Text = ($rows -join [Environment]::NewLine)
    } @{ Form = $wf; Txt = $txt }

    [void]$wf.ShowDialog()
}

# ---------------------------------------------------------------------
#  รายการสวิตช์
# ---------------------------------------------------------------------
$items = @(
    @{ Key = 'net';  Name = 'Bypass Net'  },
    @{ Key = 'web';  Name = 'Bypass Web'  },
    @{ Key = 'game'; Name = 'Bypass Game' },
    @{ Key = 'mem';  Name = 'Clean RAM'   },
    @{ Key = 'fw';   Name = 'Bypass Firewall'}
)
$memSec = 60   # ล้างแรมทุกกี่วินาที (แก้ตัวเลขได้)
$descs = @{
    net  = 'ตัดอินเทอร์เน็ตทั้งเครื่อง'
    web  = 'บล็อกเบราว์เซอร์'
    game = 'บล็อกเน็ตเกม + ตัวเปิดเกม'
    mem  = ('ล้างแรมเบื้องหลังทุก ' + $memSec + ' วิ')
    fw   = 'ปิด Windows Firewall ทุกโปรไฟล์'
}

$state = @{}
$initCount = @{}
foreach ($it in $items) {
    if ($it.Key -eq 'mem') {
        $initCount[$it.Key] = 0
        $state[$it.Key] = $false
        continue
    }
    if ($it.Key -eq 'fw') {
        $initCount[$it.Key] = 0
        $state[$it.Key] = (Test-FwAllOff)
        continue
    }
    $nm = Get-GroupRuleNames $Grp[$it.Key]
    $initCount[$it.Key] = $nm.Count
    $state[$it.Key] = ($nm.Count -gt 0)
}
$script:memTm = New-Object Windows.Forms.Timer
$script:memTm.Interval = $memSec * 1000
$script:memTm.Add_Tick({ [MemCleaner]::RunAsync() })

$cCard  = [Drawing.Color]::FromArgb(24, 13, 50)
$cOff   = [Drawing.Color]::FromArgb(148, 140, 170)
$cOn    = [Drawing.Color]::FromArgb(74, 222, 128)

# ---------- ขนาดหน้าต่าง ----------
# หัว 80 | กราฟ 196 | Speed Test 140 | สวิตช์ 84 | ปุ่ม WiFi 46 | สรุป  (เว้นช่อง 14)
$W = 1040
$H = 630

$form = New-Object GradForm
$form.Text = 'Fam Bypass'
$form.ClientSize = New-Object Drawing.Size($W, $H)
$form.StartPosition = 'CenterScreen'
$form.KeyPreview = $true
$form.Font = New-Object Drawing.Font('Segoe UI', 10)
try { [Gfx]::SetCurrentProcessExplicitAppUserModelID('FamBypass.App') | Out-Null } catch { }
if ($script:logoBmp) { try { $form.Icon = [Drawing.Icon]::FromHandle($script:logoBmp.GetHicon()) } catch { } }


$title = New-Object Windows.Forms.Label
$title.Text = 'Fam Bypass'
$title.Font = New-Object Drawing.Font('ไอติม', 20)
$title.ForeColor = $cWhite
$title.BackColor = [Drawing.Color]::Transparent
$title.AutoSize = $true
$title.Location = New-Object Drawing.Point(86, 12)
$title.Add_MouseDown({ [Gfx]::Drag($form.Handle) })

$sub = New-Object Windows.Forms.Label
$sub.Text = 'เปิด/ปิดได้ในคลิกเดียว  |  มอนิเตอร์เครื่องแบบเรียลไทม์  |  วัดความเร็วเน็ตในตัว'
$sub.Font = New-Object Drawing.Font('Segoe UI', 9.5)
$sub.ForeColor = $cLav
$sub.BackColor = [Drawing.Color]::Transparent
$sub.AutoSize = $true
$sub.Location = New-Object Drawing.Point(89, 50)
$sub.Add_MouseDown({ [Gfx]::Drag($form.Handle) })

$closeLbl = New-Object Windows.Forms.Label
$closeLbl.Text = [string][char]0x2715
$closeLbl.Font = New-Object Drawing.Font('Segoe UI Symbol', 12)
$closeLbl.ForeColor = $cLav
$closeLbl.BackColor = [Drawing.Color]::Transparent
$closeLbl.Cursor = [Windows.Forms.Cursors]::Hand
$closeLbl.Size = New-Object Drawing.Size(32, 32)
$closeLbl.TextAlign = 'MiddleCenter'
$closeLbl.Location = New-Object Drawing.Point(($W - 48), 14)
$closeLbl.Add_MouseEnter({ $closeLbl.ForeColor = $cWhite })
$closeLbl.Add_MouseLeave({ $closeLbl.ForeColor = $cLav })
$closeLbl.Add_Click({ $form.Close() })

$hdrLogo = New-Object Logo
$hdrLogo.Size = New-Object Drawing.Size(58, 58)
$hdrLogo.Location = New-Object Drawing.Point(20, 10)
if ($script:logoBmp) { $hdrLogo.Img = $script:logoBmp }
$hdrLogo.Add_MouseDown({ [Gfx]::Drag($form.Handle) })

$form.Controls.AddRange(@($title, $sub, $closeLbl, $hdrLogo))

# =====================================================================
#  แถวที่ 1: การ์ดกราฟ 5 ใบ (CPU / RAM / GPU / Ping / WiFi)
# =====================================================================
$defs = @(
    @{ K = 'cpu';  N = 'CPU';          C = [Drawing.Color]::FromArgb(56, 189, 248); M = 100 },
    @{ K = 'ram';  N = 'Memory';       C = [Drawing.Color]::FromArgb(168, 85, 247); M = 100 },
    @{ K = 'gpu';  N = 'GPU (NVIDIA)'; C = [Drawing.Color]::FromArgb(251, 146, 60); M = 100 },
    @{ K = 'ping'; N = 'Ping';         C = [Drawing.Color]::FromArgb(74, 222, 128); M = 0 },
    @{ K = 'wifi'; N = 'Wi-Fi Signal'; C = [Drawing.Color]::FromArgb(244, 114, 182); M = 100 }
)
$script:ui = @{}
$gw = 188
$gh = 196
$gx = 24
$gy = 80
foreach ($d in $defs) {
    $gcard = New-Object Card
    $gcard.BackColor = [Drawing.Color]::Transparent
    $gcard.Size = New-Object Drawing.Size($gw, $gh)
    $gcard.Location = New-Object Drawing.Point($gx, $gy)

    $gn = New-Object Windows.Forms.Label
    $gn.Text = $d.N
    $gn.Font = New-Object Drawing.Font('ไอติม', 11)
    $gn.ForeColor = $cLav
    $gn.BackColor = $cCard
    $gn.AutoSize = $true
    $gn.Location = New-Object Drawing.Point(12, 8)

    $gv = New-Object Windows.Forms.Label
    $gv.Text = '-'
    $gv.Font = New-Object Drawing.Font('ไอติม', 15)
    $gv.ForeColor = $d.C
    $gv.BackColor = $cCard
    $gv.AutoSize = $false
    $gv.TextAlign = 'MiddleLeft'
    $gv.Size = New-Object Drawing.Size(166, 32)
    $gv.Location = New-Object Drawing.Point(12, 32)

    $gs = New-Object Windows.Forms.Label
    $gs.Text = ''
    $gs.Font = New-Object Drawing.Font('Segoe UI', 8.5)
    $gs.ForeColor = $cOff
    $gs.BackColor = $cCard
    $gs.AutoSize = $false
    $gs.Size = New-Object Drawing.Size(166, 32)
    $gs.Location = New-Object Drawing.Point(12, 64)

    $gg = New-Object MiniGraph
    $gg.Line = $d.C
    $gg.MaxV = $d.M
    $gg.Size = New-Object Drawing.Size(166, 86)
    $gg.Location = New-Object Drawing.Point(11, 100)

    $gcard.Controls.AddRange(@($gn, $gv, $gs, $gg))
    $form.Controls.Add($gcard)
    $script:ui[$d.K] = @{ Val = $gv; Sub = $gs; G = $gg }
    $gx += $gw + 13
}

function Set-Row($k, $val, $text, $subtext) {
    $script:ui[$k].Val.Text = $text
    $script:ui[$k].Sub.Text = $subtext
    $script:ui[$k].G.Push([single]$val)
}

# =====================================================================
#  แถวที่ 2: SPEED TEST
#  - เลือกเซิร์ฟเวอร์ Speedtest.net (Ookla) ที่ ping ต่ำสุดใกล้คุณโดยอัตโนมัติ  = เซิร์ฟเวอร์เดียวกับเว็บ speedtest.net
#  - ถ้าติดต่อ Ookla ไม่ได้ จะสลับไปใช้ Cloudflare (speed.cloudflare.com) ให้เอง
#  - วัด Ping / Jitter / Download / Upload  + แสดง ISP, IP, Server
# =====================================================================
$cs2 = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Globalization;
using System.IO;
using System.Net;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

public class SpeedJob
{
    public volatile bool Stop;
    public long Total;
    public int Errors;
    public List<HttpWebRequest> Reqs = new List<HttpWebRequest>();
}

public class SrvCand
{
    public string Base = "";
    public string Name = "";
    public string Sponsor = "";
    public double Lat = 1e9;
}

public class SpeedEngine
{
    // Phase: 0 = ว่าง, 1 = เลือกเซิร์ฟเวอร์/ping, 2 = download, 3 = upload, 4 = เสร็จ, 5 = error
    public volatile int Phase;
    public volatile int Progress;
    public double Cur, Ping, Jitter, Down, Up;
    public string Ip = "", Isp = "", Colo = "", Error = "", Detail = "";
    public volatile string SrvName = "";
    public volatile string SrvSub = "";
    public volatile bool InfoReady;
    public volatile bool InfoFailed;
    public volatile bool SrvReady;
    public int DownSec = 12;
    public int UpSec = 10;
    public int DownThreads = 8;
    public int UpThreads = 6;
    public bool PreferOokla = true;

    const string Host = "https://speed.cloudflare.com";
    volatile bool cancel;
    volatile bool infoBusy;
    Thread th;
    bool ookla;
    string baseUrl = "";
    long seq;

    public bool Running { get { return Phase >= 1 && Phase <= 3; } }

    static SpeedEngine()
    {
        try { ServicePointManager.SecurityProtocol |= (SecurityProtocolType)3072; } catch { }
        ServicePointManager.DefaultConnectionLimit = 64;
        ServicePointManager.Expect100Continue = false;
        ServicePointManager.UseNagleAlgorithm = false;
    }

    static HttpWebRequest Make(string url, int timeout)
    {
        HttpWebRequest r = (HttpWebRequest)WebRequest.Create(url);
        r.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36";
        r.Referer = url.StartsWith(Host) ? Host + "/" : "https://www.speedtest.net/";
        r.Proxy = null;                 // ไม่เสียเวลาหา proxy อัตโนมัติ (WPAD)
        r.KeepAlive = true;
        r.Timeout = timeout;
        r.ReadWriteTimeout = timeout;
        return r;
    }

    static string GetText(string url, int timeout)
    {
        HttpWebRequest r = Make(url, timeout);
        using (WebResponse resp = r.GetResponse())
        using (StreamReader sr = new StreamReader(resp.GetResponseStream()))
            return sr.ReadToEnd();
    }

    static string Pick(string j, string key)
    {
        Match m = Regex.Match(j, "\"" + key + "\"\\s*:\\s*\"([^\"]*)\"");
        return m.Success ? m.Groups[1].Value : "";
    }

    static string Unesc(string s)
    {
        try { return Regex.Unescape(s); } catch { return s; }
    }

    void LoadInfoSync()
    {
        try
        {
            string j = GetText(Host + "/meta", 6000);
            Ip = Pick(j, "clientIp");
            Isp = Pick(j, "asOrganization");
            Colo = Pick(j, "colo");
            if (Colo.Length == 0) Colo = Pick(j, "iata");
            if (Ip.Length > 0) InfoReady = true;
        }
        catch { }
        if (!InfoReady)
        {
            try
            {
                string txt = GetText("https://www.cloudflare.com/cdn-cgi/trace", 6000);
                Match m1 = Regex.Match(txt, "ip=(\\S+)");
                Match m2 = Regex.Match(txt, "colo=(\\S+)");
                if (m1.Success) { Ip = m1.Groups[1].Value; InfoReady = true; }
                if (m2.Success) Colo = m2.Groups[1].Value;
            }
            catch { }
        }
        if (!InfoReady) InfoFailed = true;
    }

    public void LoadInfo()
    {
        if (infoBusy || InfoReady) return;
        infoBusy = true;
        Thread t = new Thread(delegate() { LoadInfoSync(); infoBusy = false; });
        t.IsBackground = true;
        t.Start();
    }

    public void Start()
    {
        if (Running) return;
        cancel = false;
        Error = "";
        Detail = "";
        Cur = 0; Ping = 0; Jitter = 0; Down = 0; Up = 0;
        Progress = 0;
        SrvReady = false;
        Phase = 1;
        th = new Thread(RunAll);
        th.IsBackground = true;
        th.Start();
    }

    public void Cancel() { cancel = true; }

    // ---------- เลือกเซิร์ฟเวอร์ ----------
    void UseCloudflare()
    {
        ookla = false;
        SrvName = "Cloudflare";
        SrvSub = Colo.Length > 0 ? "Edge: " + Colo : "";
        SrvReady = true;
    }

    static double Probe(string b)
    {
        double best = 1e9;
        for (int i = 0; i < 4; i++)
        {
            try
            {
                Stopwatch sw = Stopwatch.StartNew();
                HttpWebRequest r = Make(b + "latency.txt?x=" + Stopwatch.GetTimestamp(), 2500);
                using (WebResponse resp = r.GetResponse())
                using (Stream s = resp.GetResponseStream())
                {
                    byte[] buf = new byte[512];
                    while (s.Read(buf, 0, buf.Length) > 0) { }
                }
                sw.Stop();
                if (i > 0 && sw.Elapsed.TotalMilliseconds < best) best = sw.Elapsed.TotalMilliseconds;   // ครั้งแรกรวม handshake จึงไม่นับ
            }
            catch { return 1e9; }
        }
        return best;
    }

    bool SelectOokla()
    {
        string j = GetText("https://www.speedtest.net/api/js/servers?engine=js&limit=8", 6000);
        List<SrvCand> list = new List<SrvCand>();
        foreach (Match m in Regex.Matches(j, "\\{[^{}]*\"url\"[^{}]*\\}"))
        {
            string o = m.Value;
            string url = Pick(o, "url").Replace("\\/", "/");
            if (!url.StartsWith("http")) continue;
            int p = url.LastIndexOf('/');
            if (p < 8) continue;
            SrvCand c = new SrvCand();
            c.Base = url.Substring(0, p + 1);
            c.Name = Unesc(Pick(o, "name"));
            c.Sponsor = Unesc(Pick(o, "sponsor"));
            list.Add(c);
            if (list.Count >= 6) break;
        }
        if (list.Count == 0) return false;

        List<Thread> ts = new List<Thread>();
        foreach (SrvCand c0 in list)
        {
            SrvCand c = c0;
            Thread t = new Thread(delegate() { c.Lat = Probe(c.Base); });
            t.IsBackground = true;
            t.Start();
            ts.Add(t);
        }
        DateTime end = DateTime.Now.AddSeconds(5);
        foreach (Thread t in ts)
        {
            int ms = (int)(end - DateTime.Now).TotalMilliseconds;
            if (ms < 1) ms = 1;
            t.Join(ms);
        }

        SrvCand best = null;
        foreach (SrvCand c in list)
            if (c.Lat < 1e8 && (best == null || c.Lat < best.Lat)) best = c;
        if (best == null) return false;

        baseUrl = best.Base;
        SrvName = best.Sponsor.Length > 0 ? best.Sponsor : best.Name;
        SrvSub = "Ookla - " + best.Name;
        SrvReady = true;
        return true;
    }

    void SelectServer()
    {
        ookla = false;
        if (PreferOokla)
        {
            try { ookla = SelectOokla(); } catch { ookla = false; }
        }
        if (!ookla) UseCloudflare();
    }

    string DownUrl()
    {
        long n = Interlocked.Increment(ref seq);
        if (ookla) return baseUrl + "random4000x4000.jpg?x=" + Stopwatch.GetTimestamp() + "&y=" + n;
        return Host + "/__down?bytes=25000000&x=" + n;
    }

    string UpUrl()
    {
        if (ookla) return baseUrl + "upload.php?x=" + Interlocked.Increment(ref seq);
        return Host + "/__up";
    }

    // ---------- ลำดับการทดสอบ ----------
    void RunAll()
    {
        try
        {
            if (!InfoReady) LoadInfoSync();
            SelectServer();
            if (cancel) { Phase = 0; return; }

            for (int attempt = 0; attempt < 2; attempt++)
            {
                try
                {
                    RunTests();
                    return;
                }
                catch (ApplicationException)
                {
                    // ถ้าเซิร์ฟเวอร์ Ookla ใช้ไม่ได้ ให้ลองซ้ำด้วย Cloudflare
                    if (ookla && !cancel) { UseCloudflare(); Cur = 0; Down = 0; Up = 0; continue; }
                    throw;
                }
            }
        }
        catch (ApplicationException ae) { Error = ae.Message; Phase = 5; }
        catch (Exception ex) { Error = "ERR"; Detail = ex.Message; Phase = 5; }
    }

    void RunTests()
    {
        Phase = 1; Progress = 0;
        DoPing();
        if (cancel) { Phase = 0; return; }

        Phase = 2; Cur = 0;
        Down = Measure(DownSec, DownThreads, DownWorker, 10, 55, "NODOWN");
        if (cancel) { Phase = 0; return; }

        Phase = 3; Cur = 0;
        Up = Measure(UpSec, UpThreads, UpWorker, 55, 100, "NOUP");
        if (cancel) { Phase = 0; return; }

        Cur = 0;
        Progress = 100;
        Phase = 4;
    }

    void DoPing()
    {
        List<double> list = new List<double>();
        string pu = ookla ? baseUrl + "latency.txt?x=" : Host + "/__down?bytes=0&x=";
        for (int i = 0; i < 12 && !cancel; i++)
        {
            Progress = i * 10 / 12;
            try
            {
                Stopwatch sw = Stopwatch.StartNew();
                HttpWebRequest r = Make(pu + Stopwatch.GetTimestamp(), 5000);
                double srv = 0;
                using (WebResponse resp = r.GetResponse())
                {
                    string st = resp.Headers["Server-Timing"];
                    if (st != null)
                    {
                        Match m = Regex.Match(st, "cfRequestDuration;dur=([0-9.]+)");
                        if (m.Success) double.TryParse(m.Groups[1].Value, NumberStyles.Any, CultureInfo.InvariantCulture, out srv);
                    }
                    using (Stream s = resp.GetResponseStream())
                    {
                        byte[] b = new byte[512];
                        while (s.Read(b, 0, b.Length) > 0) { }
                    }
                }
                sw.Stop();
                double ms = sw.Elapsed.TotalMilliseconds - srv;     // หักเวลาประมวลผลฝั่งเซิร์ฟเวอร์ออก
                if (ms < 0.5) ms = 0.5;
                if (i > 0) list.Add(ms);                           // ครั้งแรกรวมเวลา handshake จึงไม่นับ
            }
            catch { }
            Thread.Sleep(50);
        }
        if (cancel) return;
        if (list.Count == 0) throw new ApplicationException("NOCONN");

        double jd = 0;
        for (int k = 1; k < list.Count; k++) jd += Math.Abs(list[k] - list[k - 1]);
        Jitter = list.Count > 1 ? jd / (list.Count - 1) : 0;
        list.Sort();
        Ping = list[0];     // Speedtest.net แสดงค่า latency ต่ำสุด
    }

    double Measure(int seconds, int threads, ParameterizedThreadStart worker, int p0, int p1, string failCode)
    {
        SpeedJob job = new SpeedJob();
        for (int i = 0; i < threads; i++)
        {
            Thread w = new Thread(worker);
            w.IsBackground = true;
            w.Start(job);
        }

        Stopwatch sw = Stopwatch.StartNew();
        long lastB = 0;
        double lastT = 0, warmT = -1, smooth = 0;
        long warmB = 0;

        while (!cancel)
        {
            Thread.Sleep(200);
            double now = sw.Elapsed.TotalSeconds;
            long b = Interlocked.Read(ref job.Total);
            double dt = now - lastT;
            if (dt > 0)
            {
                double inst = (b - lastB) * 8.0 / 1000000.0 / dt;
                smooth = (smooth <= 0) ? inst : smooth * 0.65 + inst * 0.35;
                Cur = smooth;
            }
            if (warmT < 0 && now >= 2.0) { warmT = now; warmB = b; }   // ตัดช่วง slow-start ออก
            lastB = b;
            lastT = now;
            Progress = p0 + (int)((p1 - p0) * Math.Min(1.0, now / seconds));
            if (b == 0 && now > 5) { Finish(job); throw new ApplicationException(failCode); }
            if (now >= seconds) break;
        }

        double tEnd = sw.Elapsed.TotalSeconds;
        long bEnd = Interlocked.Read(ref job.Total);
        Finish(job);
        if (cancel) return 0;
        if (bEnd <= 0) throw new ApplicationException(failCode);
        if (warmT > 0 && tEnd - warmT > 0.5)
            return (bEnd - warmB) * 8.0 / 1000000.0 / (tEnd - warmT);
        return bEnd * 8.0 / 1000000.0 / tEnd;
    }

    static void Finish(SpeedJob job)
    {
        job.Stop = true;
        lock (job.Reqs)
        {
            foreach (HttpWebRequest r in job.Reqs)
            {
                try { r.Abort(); } catch { }
            }
        }
    }

    void DownWorker(object o)
    {
        SpeedJob j = (SpeedJob)o;
        byte[] buf = new byte[65536];
        while (!j.Stop)
        {
            HttpWebRequest r = null;
            try
            {
                r = Make(DownUrl(), 8000);
                lock (j.Reqs) j.Reqs.Add(r);
                using (WebResponse resp = r.GetResponse())
                using (Stream s = resp.GetResponseStream())
                {
                    int n;
                    while (!j.Stop && (n = s.Read(buf, 0, buf.Length)) > 0)
                        Interlocked.Add(ref j.Total, n);
                }
            }
            catch { if (!j.Stop) { j.Errors++; Thread.Sleep(300); } }
            finally { if (r != null) { try { r.Abort(); } catch { } } }
        }
    }

    void UpWorker(object o)
    {
        SpeedJob j = (SpeedJob)o;
        byte[] buf = new byte[65536];
        new Random(Environment.TickCount + Thread.CurrentThread.ManagedThreadId).NextBytes(buf);
        const int chunk = 4000000;
        while (!j.Stop)
        {
            HttpWebRequest r = null;
            try
            {
                r = Make(UpUrl(), 8000);
                r.Method = "POST";
                r.ContentType = "application/octet-stream";
                r.ContentLength = chunk;
                r.AllowWriteStreamBuffering = false;
                lock (j.Reqs) j.Reqs.Add(r);
                using (Stream s = r.GetRequestStream())
                {
                    int sent = 0;
                    while (sent < chunk && !j.Stop)
                    {
                        int n = Math.Min(buf.Length, chunk - sent);
                        s.Write(buf, 0, n);
                        sent += n;
                        Interlocked.Add(ref j.Total, n);
                    }
                    if (j.Stop && sent < chunk) r.Abort();
                }
                if (!j.Stop)
                {
                    using (WebResponse resp = r.GetResponse()) { }
                }
            }
            catch { if (!j.Stop) { j.Errors++; Thread.Sleep(300); } }
            finally { if (r != null) { try { r.Abort(); } catch { } } }
        }
    }
}

// ปุ่มวงกลม GO (ตอนกำลังวัดจะกลายเป็นวงแหวนโปรเกรส + ตัวเลขความเร็ว)
public class SpeedGo : Control
{
    public int Mode;          // 0 = พร้อม, 1 = กำลังวัด
    public int Progress;
    public string Big = "GO";
    public string Small = "";
    public Color C1 = Color.FromArgb(217, 70, 239);
    public Color C2 = Color.FromArgb(99, 102, 241);
    bool hover;

    public SpeedGo()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer
            | ControlStyles.SupportsTransparentBackColor | ControlStyles.ResizeRedraw | ControlStyles.StandardClick, true);
        Cursor = Cursors.Hand;
        ForeColor = Color.White;
        Size = new Size(116, 116);
    }

    protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { hover = false; Invalidate(); base.OnMouseLeave(e); }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        if (BackColor.A == 255) g.Clear(BackColor);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        Rectangle r = new Rectangle(6, 6, Width - 13, Height - 13);
        if (r.Width < 20 || r.Height < 20) return;

        if (hover && Mode == 0)
        {
            using (SolidBrush hb = new SolidBrush(Color.FromArgb(45, 168, 85, 247)))
                g.FillEllipse(hb, r);
        }
        using (Pen tp = new Pen(Color.FromArgb(62, 44, 118), 4f))
            g.DrawEllipse(tp, r);

        using (LinearGradientBrush lb = new LinearGradientBrush(new Rectangle(0, 0, Width, Height), C1, C2, 45f))
        using (Pen pen = new Pen(lb, (hover && Mode == 0) ? 5f : 4f))
        {
            if (Mode == 0) g.DrawEllipse(pen, r);
            else
            {
                float sweep = 360f * Progress / 100f;
                if (sweep < 4f) sweep = 4f;
                g.DrawArc(pen, r, -90f, sweep);
            }
        }

        TextFormatFlags fl = TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter
            | TextFormatFlags.SingleLine | TextFormatFlags.NoPadding;
        if (Mode == 0)
        {
            using (Font f = new Font("ไอติม", 26f, FontStyle.Bold))
                TextRenderer.DrawText(g, Big, f, new Rectangle(0, 0, Width, Height), ForeColor, fl);
        }
        else
        {
            using (Font f = new Font("ไอติม", 19f, FontStyle.Bold))
                TextRenderer.DrawText(g, Big, f, new Rectangle(0, Height / 2 - 30, Width, 40), ForeColor, fl);
            using (Font f2 = new Font("ไอติม", 8f))
                TextRenderer.DrawText(g, Small, f2, new Rectangle(0, Height / 2 + 10, Width, 18), Color.FromArgb(196, 181, 253), fl);
        }
    }
}
'@
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition $cs2 -Language CSharp -ErrorAction Stop

$spH = 140
$script:eng = New-Object SpeedEngine
$script:spPrev = 0
$script:spInfoShown = $false

$cDown = [Drawing.Color]::FromArgb(56, 189, 248)
$cUp   = [Drawing.Color]::FromArgb(244, 114, 182)
$cPing = [Drawing.Color]::FromArgb(74, 222, 128)

$fN = New-Object Drawing.Font('ไอติม', 10)
$fV = New-Object Drawing.Font('ไอติม', 20)
$fS = New-Object Drawing.Font('ไอติม', 9)
$fI = New-Object Drawing.Font('ไอติม', 10.5)

function New-SpLabel($text, $font, $color, $x, $y, $w, $h) {
    $l = New-Object Windows.Forms.Label
    $l.Text = $text
    $l.Font = $font
    $l.ForeColor = $color
    $l.BackColor = $cCard
    $l.AutoSize = $false
    $l.Size = New-Object Drawing.Size($w, $h)
    $l.Location = New-Object Drawing.Point($x, $y)
    return $l
}

function Format-Spd($v) {
    if ($v -ge 100) { return ('{0:N0}' -f $v) }
    return ('{0:N1}' -f $v)
}

$spCard = New-Object Card
$spCard.BackColor = [Drawing.Color]::Transparent
$spCard.Size = New-Object Drawing.Size(($W - 48), $spH)
$spCard.Location = New-Object Drawing.Point(24, ($gy + $gh + 14))

$spGo = New-Object SpeedGo
$spGo.BackColor = $cCard
$spGo.Location = New-Object Drawing.Point(22, 12)

# ค่าที่วัดได้ 3 ช่อง
$lPingN = New-SpLabel 'PING'     $fN $cLav  170 14 125 20
$vPing  = New-SpLabel '-'        $fV $cPing 170 34 125 36
$sPing  = New-SpLabel 'ms | Jitter -' $fS $cOff 170 70 125 18

$lDownN = New-SpLabel 'DOWNLOAD' $fN $cLav  300 14 125 20
$vDown  = New-SpLabel '-'        $fV $cDown 300 34 125 36
$sDown  = New-SpLabel 'Mbps'     $fS $cOff  300 70 125 18

$lUpN   = New-SpLabel 'UPLOAD'   $fN $cLav  430 14 125 20
$vUp    = New-SpLabel '-'        $fV $cUp   430 34 125 36
$sUp    = New-SpLabel 'Mbps'     $fS $cOff  430 70 125 18

# ข้อมูล ISP / IP / Server (เหมือนใน Speedtest.net)
$lIsp  = New-SpLabel 'กำลังตรวจสอบ...' $fI $cWhite 170 96 205 20
$lIsp.AutoEllipsis = $true
$lIp   = New-SpLabel '' $fS $cOff 170 116 205 18
$lSrv  = New-SpLabel 'เลือกเซิร์ฟเวอร์อัตโนมัติ' $fI $cWhite 385 96 175 20
$lSrv.AutoEllipsis = $true
$lSrvS = New-SpLabel '' $fS $cOff 385 116 175 18
$lSrvS.AutoEllipsis = $true

# กราฟความเร็วสด
$spG = New-Object MiniGraph
$spG.Line = $cDown
$spG.MaxV = 0
$spG.Cap = 60
$spG.Size = New-Object Drawing.Size((($W - 48) - 570 - 16), 116)
$spG.Location = New-Object Drawing.Point(570, 12)

$spCard.Controls.AddRange(@($spGo, $lPingN, $vPing, $sPing, $lDownN, $vDown, $sDown, $lUpN, $vUp, $sUp, $lIsp, $lIp, $lSrv, $lSrvS, $spG))
$form.Controls.Add($spCard)

# กด GO = เริ่มวัด / กดระหว่างวัด = ยกเลิก
$spGo.Add_Click({
    if ($script:eng.Running) { $script:eng.Cancel(); return }
    $vPing.Text = '-'
    $vDown.Text = '-'
    $vUp.Text = '-'
    $sPing.Text = 'ms | Jitter -'
    $spG.Data.Clear()
    $spG.Line = $cDown
    $spG.Invalidate()
    $script:eng.Start()
})

$spTm = New-Object Windows.Forms.Timer
$spTm.Interval = 200
$spTm.Add_Tick({
    $e = $script:eng

    if (-not $script:spInfoShown) {
        if ($e.InfoReady) {
            if ($e.Isp) { $lIsp.Text = $e.Isp } else { $lIsp.Text = 'ไม่ทราบ ISP' }
            $lIp.Text = $e.Ip
            $script:spInfoShown = $true
        } elseif ($e.InfoFailed) {
            $lIsp.Text = 'ไม่พบข้อมูล ISP'
        }
    }
    if ($e.SrvReady) {
        $lSrv.Text = $e.SrvName
        $lSrvS.Text = $e.SrvSub
    }

    $ph = $e.Phase
    $changed = ($ph -ne $script:spPrev)
    $script:spPrev = $ph

    if ($ph -ge 1 -and $ph -le 3) {
        if ($changed) {
            if ($ph -eq 2) {
                $vPing.Text = ('{0:N0}' -f $e.Ping)
                $sPing.Text = ('ms | Jitter {0:N0}' -f $e.Jitter)
                $spG.Data.Clear()
                $spG.Line = $cDown
            }
            if ($ph -eq 3) {
                $vDown.Text = (Format-Spd $e.Down)
                $spG.Data.Clear()
                $spG.Line = $cUp
            }
        }
        $spGo.Mode = 1
        $spGo.Progress = $e.Progress
        if ($ph -eq 1) {
            $spGo.Big = '...'
            $spGo.Small = 'PING'
        } elseif ($ph -eq 2) {
            $spGo.Big = (Format-Spd $e.Cur)
            $spGo.Small = 'DOWNLOAD'
            $vDown.Text = $spGo.Big
            $spG.Push([single]$e.Cur)
        } else {
            $spGo.Big = (Format-Spd $e.Cur)
            $spGo.Small = 'UPLOAD'
            $vUp.Text = $spGo.Big
            $spG.Push([single]$e.Cur)
        }
        $spGo.Invalidate()
    }
    elseif ($changed) {
        $spGo.Mode = 0
        $spGo.Big = 'GO'
        $spGo.Small = ''
        $spGo.Progress = 0
        $spGo.Invalidate()
        if ($ph -eq 4) {
            $vPing.Text = ('{0:N0}' -f $e.Ping)
            $sPing.Text = ('ms | Jitter {0:N0}' -f $e.Jitter)
            $vDown.Text = (Format-Spd $e.Down)
            $vUp.Text = (Format-Spd $e.Up)
        }
        elseif ($ph -eq 5) {
            $msg = switch ($e.Error) {
                'NOCONN' {
                    $m = 'เชื่อมต่อเซิร์ฟเวอร์ทดสอบไม่ได้ ตรวจสอบอินเทอร์เน็ตของคุณ'
                    if ($state['net']) { $m += ("`n`n" + 'ตอนนี้เปิด Bypass Net อยู่ (เน็ตถูกตัด) ให้ปิดก่อนแล้วลองใหม่') }
                    $m
                }
                'NODOWN' { 'ทดสอบดาวน์โหลดไม่สำเร็จ (เน็ตอาจหลุดหรือถูกบล็อก)' }
                'NOUP'   { 'ทดสอบอัปโหลดไม่สำเร็จ (เน็ตอาจหลุดหรือถูกบล็อก)' }
                default  { 'เกิดข้อผิดพลาด: ' + $e.Detail }
            }
            [Windows.Forms.MessageBox]::Show(($msg + "`n`n" + $e.Detail), 'Speed Test') | Out-Null
        }
    }
})

# =====================================================================
#  แถวที่ 3: การ์ดปุ่มเปิด/ปิด 4 ใบ  (อยู่ใต้การ์ด Speed Test)
# =====================================================================
$summary = New-Object Windows.Forms.Label
$summary.ForeColor = $cLav
$summary.BackColor = [Drawing.Color]::Transparent
$summary.Font = New-Object Drawing.Font('Segoe UI', 9.5)
$summary.TextAlign = 'MiddleCenter'
$summary.Size = New-Object Drawing.Size($W, 28)
$summary.Location = New-Object Drawing.Point(0, ($H - 40))
$summary.Add_MouseDown({ [Gfx]::Drag($form.Handle) })

$statusLabels = @{}

function UpdateSummary {
    $n = @($state.Values | Where-Object { $_ }).Count
    $summary.Text = 'เปิดอยู่ ' + $n + ' / ' + $items.Count
}

function Set-ToggleUi([string]$k, [bool]$now, [int]$cnt) {
    $state[$k] = $now
    if ($now) {
        $t = 'เปิด · ' + $descs[$k]
        if ($k -ne 'net' -and $k -ne 'mem' -and $k -ne 'fw' -and $cnt -gt 0) { $t += ' (' + $cnt + ' โปรแกรม)' }
        $statusLabels[$k].Text = $t
        $statusLabels[$k].ForeColor = $cOn
    } else {
        $statusLabels[$k].Text = 'ปิด · ' + $descs[$k]
        $statusLabels[$k].ForeColor = $cOff
    }
    UpdateSummary
    Save-Settings
}

# เมื่องานเบื้องหลัง (สร้าง/ลบกฎ Firewall) เสร็จ
$fwDone = {
    param($out, $ctx)
    $tg = $ctx.Tg
    $k = $ctx.K
    $want = $ctx.Want
    $res = [string](@($out)[-1])
    $cnt = 0
    $fail = $null
    if ($res -like 'OK:*') {
        $cnt = [int]$res.Substring(3)
        if ($want -and $cnt -lt 1) { $fail = 'ไม่พบโปรแกรมที่จะบล็อก (' + $descs[$k] + ')' }
    } else {
        $fail = $res
        if (-not $fail) { $fail = 'ทำงานไม่สำเร็จ' }
    }
    if ($fail) {
        try { if ($want) { Clear-Group $Grp[$k] } } catch { }
        [Windows.Forms.MessageBox]::Show($fail, 'Fam Bypass') | Out-Null
        $script:loading = $true
        $tg.Checked = -not $want
        $script:loading = $false
        Set-ToggleUi $k $tg.Checked 0
    } else {
        Set-ToggleUi $k $want $cnt
    }
    $tg.Enabled = $true
}

$tw = 238                                   # ความกว้างการ์ดไดรฟ์ (คงเดิม)
$ttw = [int](($W - 48 - 13 * 4) / 5)        # ความกว้างการ์ดสวิตช์ (5 ใบ)
$th = 92
$script:tgMap = @{}
$tx = 24
$ty = $gy + $gh + 14 + $spH + 14
foreach ($it in $items) {
    $card = New-Object Card
    $card.BackColor = [Drawing.Color]::Transparent
    $card.Size = New-Object Drawing.Size($ttw, $th)
    $card.Location = New-Object Drawing.Point($tx, $ty)

    $lbl = New-Object Windows.Forms.Label
    $lbl.Text = $it.Name
    $lbl.Font = New-Object Drawing.Font('ไอติม', 12)
    $lbl.ForeColor = $cWhite
    $lbl.BackColor = $cCard
    $lbl.AutoSize = $true
    $lbl.Location = New-Object Drawing.Point(14, 10)

    $st = New-Object Windows.Forms.Label
    $st.Text = 'ปิด · ' + $descs[$it.Key]
    $st.Font = New-Object Drawing.Font('Segoe UI', 8.5)
    $st.ForeColor = $cOff
    $st.BackColor = $cCard
    $st.AutoSize = $false
    $st.Size = New-Object Drawing.Size(($ttw - 26), 46)
    $st.Location = New-Object Drawing.Point(14, 42)
    $statusLabels[$it.Key] = $st

    $tg = New-Object ToggleSwitch
    $tg.BackColor = $cCard
    $tg.Size = New-Object Drawing.Size(48, 26)
    $tg.Location = New-Object Drawing.Point(($ttw - 48 - 12), 10)
    $tg.Tag = $it.Key
    $script:tgMap[$it.Key] = $tg
    $tg.Add_CheckedChanged({
        param($sender, $e)
        $k = [string]$sender.Tag

        if ($script:loading) { Set-ToggleUi $k $sender.Checked $initCount[$k]; return }

        $want = $sender.Checked

        if ($k -eq 'mem') {
            if ($want) { [MemCleaner]::RunAsync(); $script:memTm.Start() }
            else { $script:memTm.Stop() }
            Set-ToggleUi $k $want 0
            return
        }

        # ปุ่มที่ 5: เปิดสวิตช์ = ปิด Windows Firewall
        if ($k -eq 'fw') {
            $ok = Set-FwState (-not $want)
            if (-not $ok) {
                [Windows.Forms.MessageBox]::Show('สั่งเปลี่ยนสถานะ Windows Firewall ไม่สำเร็จ (อาจถูกโปรแกรมป้องกันไวรัสหรือ Group Policy ล็อกไว้)', 'Fam Bypass') | Out-Null
                $script:loading = $true
                $sender.Checked = -not $want
                $script:loading = $false
                Set-ToggleUi $k (-not $want) 0
                return
            }
            Set-ToggleUi $k $want 0
            return
        }

        $sender.Enabled = $false
        $statusLabels[$k].ForeColor = $cLav
        $statusLabels[$k].Text = 'กำลังทำงานเบื้องหลัง... (โปรแกรมไม่ค้าง)'
        $mode = 'off'
        if ($want) { $mode = 'on' }
        Start-Bg $fwCode @{ mode = $mode; k = $k } $fwDone @{ Tg = $sender; K = $k; Want = $want }
    })

    if ($state[$it.Key]) {
        $script:loading = $true
        $tg.Checked = $true
        $script:loading = $false
    }

    $card.Controls.AddRange(@($lbl, $st, $tg))
    $form.Controls.Add($card)
    $tx += $ttw + 13
}

# =====================================================================
#  แถวที่ 4: ปุ่มดูรหัส WiFi
# =====================================================================
$by = $ty + $th + 14
$wifiBtn = New-Object GradButton
$wifiBtn.Text = 'ดูรหัส WiFi ที่บันทึกไว้'
$wifiBtn.C1 = [Drawing.Color]::FromArgb(14, 165, 233)
$wifiBtn.C2 = [Drawing.Color]::FromArgb(59, 130, 246)
$wifiBtn.Size = New-Object Drawing.Size(($W - 48), 46)
$wifiBtn.Location = New-Object Drawing.Point(24, $by)
$wifiBtn.Add_Click({ Show-WifiPasswords })
# =====================================================================
#  วิธีใส่: ในไฟล์ FlowSkipper.bat หาช่วงนี้ (ท้ายสุดก่อน $form.Controls.Add($summary))
#
#      $by = $ty + $th + 14
#      $wifiBtn = New-Object GradButton
#      ...
#      $form.Controls.Add($wifiBtn)
#
#  แล้ว "แทนที่ทั้งช่วง" ด้วยโค้ดด้านล่างนี้ทั้งหมด (บรรทัด $form.Controls.Add($summary) และ UpdateSummary ที่ตามหลังให้คงไว้เหมือนเดิม)
# =====================================================================

# =====================================================================
#  แถวที่ 4: พื้นที่ไดรฟ์ (1 การ์ดต่อ 1 ไดรฟ์ ตามจำนวนที่มีในเครื่อง) + ปุ่มดูรหัส WiFi + ปุ่มล้างไฟล์ขยะ
# =====================================================================
$by = $ty + $th + 14

function Format-Bytes([double]$b) {
    $u = @('B', 'KB', 'MB', 'GB', 'TB', 'PB')
    $i = 0
    while ($b -ge 1024 -and $i -lt 5) { $b = $b / 1024; $i++ }
    if ($i -eq 0) { return (([int]$b).ToString() + ' B') }
    if ($b -ge 100) { $s = '{0:N0}' -f $b }
    elseif ($b -ge 10) { $s = '{0:N1}' -f $b }
    else { $s = '{0:N2}' -f $b }
    return ($s + ' ' + $u[$i])
}

function Get-DriveList {
    $out = @()
    foreach ($d in [IO.DriveInfo]::GetDrives()) {
        try {
            if (($d.DriveType -eq 'Fixed' -or $d.DriveType -eq 'Removable') -and $d.IsReady -and $d.TotalSize -gt 0) {
                $out += $d
            }
        } catch { }
    }
    return $out
}

function Get-DriveTitle($d) {
    $label = ''
    try { $label = $d.VolumeLabel } catch { }
    if (-not $label) {
        if ($d.DriveType -eq 'Removable') { $label = 'Removable Disk' } else { $label = 'Local Disk' }
    }
    return ($label + ' (' + $d.Name.Substring(0, 2) + ')')
}

function Update-Drives {
    foreach ($u in $script:drvUi) {
        try {
            $d = New-Object IO.DriveInfo $u.Letter
            if (-not $d.IsReady) { continue }
            $total = [double]$d.TotalSize
            $free = [double]$d.AvailableFreeSpace
            $usedPct = [int][Math]::Round(($total - $free) / $total * 100.0)
            if ($usedPct -ge 90) {
                $u.Bar.C1 = [Drawing.Color]::FromArgb(239, 68, 68)
                $u.Bar.C2 = [Drawing.Color]::FromArgb(248, 113, 113)
                $u.Pct.ForeColor = [Drawing.Color]::FromArgb(248, 113, 113)
            } else {
                $u.Bar.C1 = [Drawing.Color]::FromArgb(139, 92, 246)
                $u.Bar.C2 = [Drawing.Color]::FromArgb(74, 222, 128)
                $u.Pct.ForeColor = $cLav
            }
            $u.Bar.Value = $usedPct
            $u.Pct.Text = ([string]$usedPct + '%')
            $u.Txt.Text = ((Format-Bytes $free) + ' free of ' + (Format-Bytes $total))
        } catch { }
    }
}

$drvH = 78
$script:drvUi = @()
$drives = @(Get-DriveList)
$dx = 24
$dy = $by
$col = 0
foreach ($d in $drives) {
    if ($col -ge 4) { $col = 0; $dx = 24; $dy += $drvH + 10 }

    $dc = New-Object Card
    $dc.BackColor = [Drawing.Color]::Transparent
    $dc.Size = New-Object Drawing.Size($tw, $drvH)
    $dc.Location = New-Object Drawing.Point($dx, $dy)

    $dn = New-Object Windows.Forms.Label
    $dn.Text = (Get-DriveTitle $d)
    $dn.Font = New-Object Drawing.Font('ไอติม', 10.5)
    $dn.ForeColor = $cWhite
    $dn.BackColor = $cCard
    $dn.AutoSize = $false
    $dn.AutoEllipsis = $true
    $dn.Size = New-Object Drawing.Size(150, 22)
    $dn.Location = New-Object Drawing.Point(18, 8)

    $dp = New-Object Windows.Forms.Label
    $dp.Text = '-'
    $dp.Font = New-Object Drawing.Font('ไอติม', 10.5)
    $dp.ForeColor = $cLav
    $dp.BackColor = $cCard
    $dp.AutoSize = $false
    $dp.TextAlign = 'MiddleRight'
    $dp.Size = New-Object Drawing.Size(50, 22)
    $dp.Location = New-Object Drawing.Point(($tw - 18 - 50), 8)

    $db = New-Object GradBar
    $db.BackColor = $cCard
    $db.Size = New-Object Drawing.Size(($tw - 36), 12)
    $db.Location = New-Object Drawing.Point(18, 38)

    $dt = New-Object Windows.Forms.Label
    $dt.Text = ''
    $dt.Font = New-Object Drawing.Font('Segoe UI', 9)
    $dt.ForeColor = $cOff
    $dt.BackColor = $cCard
    $dt.AutoSize = $false
    $dt.Size = New-Object Drawing.Size(($tw - 36), 20)
    $dt.Location = New-Object Drawing.Point(18, 54)

    $dc.Controls.AddRange(@($dn, $dp, $db, $dt))
    $form.Controls.Add($dc)
    $script:drvUi += @{ Letter = $d.Name; Bar = $db; Txt = $dt; Pct = $dp }

    $col++
    $dx += $tw + 13
}
if ($drives.Count -gt 0) { $by = $dy + $drvH + 14 }
Update-Drives

$drvTm = New-Object Windows.Forms.Timer
$drvTm.Interval = 5000
$drvTm.Add_Tick({ Update-Drives })
$drvTm.Start()
$form.Add_FormClosed({ $drvTm.Stop(); $drvTm.Dispose() })

# ---------------------------------------------------------------------
#  ล้างไฟล์ขยะ + แคช (ทำใน runspace เบื้องหลัง หน้าต่างไม่ค้าง)
#  ลบเฉพาะ "เนื้อใน" โฟลเดอร์ชั่วคราว/แคช ไม่ลบตัวโฟลเดอร์ และข้ามไฟล์ที่โปรแกรมกำลังใช้อยู่
# ---------------------------------------------------------------------
$junkFuncs = @'
function Get-FreeSum {
    $s = [long]0
    foreach ($d in [IO.DriveInfo]::GetDrives()) {
        try { if ($d.DriveType -eq 'Fixed' -and $d.IsReady) { $s += $d.AvailableFreeSpace } } catch { }
    }
    return $s
}

function Remove-DirContents([IO.DirectoryInfo]$dir) {
    $freed = [long]0
    $files = @()
    try { $files = $dir.GetFiles() } catch { }
    foreach ($f in $files) {
        try {
            $len = $f.Length
            if ($f.IsReadOnly) { $f.IsReadOnly = $false }
            $f.Delete()
            $freed += $len
        } catch { }
    }
    $subs = @()
    try { $subs = $dir.GetDirectories() } catch { }
    foreach ($s in $subs) {
        if ($s.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }   # ไม่ตามลิงก์/junction
        $freed += Remove-DirContents $s
        try { $s.Delete() } catch { }                                             # ลบได้เฉพาะโฟลเดอร์ที่ว่างแล้ว
    }
    return $freed
}

function Remove-Junk([string]$path) {
    if (-not $path) { return [long]0 }
    if ($path.TrimEnd('\').Length -le 3) { return [long]0 }                       # กันพลาด: ห้ามแตะรากไดรฟ์
    $di = $null
    try { $di = New-Object IO.DirectoryInfo $path } catch { return [long]0 }
    if (-not $di.Exists) { return [long]0 }
    return (Remove-DirContents $di)
}

function Remove-Thumbs {
    $freed = [long]0
    $dir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'
    if (Test-Path -LiteralPath $dir) {
        foreach ($f in (Get-ChildItem -LiteralPath $dir -Filter 'thumbcache_*.db' -Force -File -ErrorAction SilentlyContinue)) {
            try { $len = $f.Length; Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; $freed += $len } catch { }
        }
    }
    return $freed
}

function Get-JunkTargets {
    $t = New-Object System.Collections.ArrayList
    $win = $env:SystemRoot
    $la = $env:LOCALAPPDATA
    $ra = $env:APPDATA
    $pd = $env:ProgramData

    $fixed = @(
        $env:TEMP, $env:TMP,
        (Join-Path $win 'Temp'),
        (Join-Path $win 'SoftwareDistribution\Download'),
        (Join-Path $win 'Minidump'),
        (Join-Path $win 'ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache'),
        (Join-Path $pd 'Microsoft\Windows\WER\ReportQueue'),
        (Join-Path $pd 'Microsoft\Windows\WER\ReportArchive'),
        (Join-Path $pd 'NVIDIA Corporation\NV_Cache'),
        (Join-Path $la 'CrashDumps'),
        (Join-Path $la 'Microsoft\Windows\INetCache'),
        (Join-Path $la 'Microsoft\Windows\WER'),
        (Join-Path $la 'D3DSCache'),
        (Join-Path $la 'NVIDIA\DXCache'),
        (Join-Path $la 'NVIDIA\GLCache'),
        (Join-Path $la 'AMD\DxCache'),
        (Join-Path $la 'Steam\htmlcache'),
        (Join-Path $ra 'discord\Cache'),
        (Join-Path $ra 'discord\Code Cache'),
        (Join-Path $ra 'discord\GPUCache')
    )
    foreach ($p in $fixed) { if ($p) { [void]$t.Add($p) } }

    # เบราว์เซอร์ตระกูล Chromium: ลบเฉพาะแคช (ไม่แตะคุกกี้/รหัสผ่าน/ประวัติ/บุ๊กมาร์ก)
    foreach ($b in @('Google\Chrome', 'Microsoft\Edge', 'BraveSoftware\Brave-Browser', 'Vivaldi')) {
        $ud = Join-Path $la ($b + '\User Data')
        if (-not (Test-Path -LiteralPath $ud)) { continue }
        foreach ($x in @('ShaderCache', 'GrShaderCache')) { [void]$t.Add((Join-Path $ud $x)) }
        foreach ($pf in (Get-ChildItem -LiteralPath $ud -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(Default|Profile \d+|Guest Profile)$' })) {
            foreach ($x in @('Cache', 'Code Cache', 'GPUCache')) { [void]$t.Add((Join-Path $pf.FullName $x)) }
        }
    }

    # Firefox
    $ff = Join-Path $la 'Mozilla\Firefox\Profiles'
    if (Test-Path -LiteralPath $ff) {
        foreach ($pf in (Get-ChildItem -LiteralPath $ff -Directory -ErrorAction SilentlyContinue)) {
            [void]$t.Add((Join-Path $pf.FullName 'cache2'))
        }
    }
    return @($t | Select-Object -Unique)
}
'@

$junkWorker = @'
[Threading.Thread]::CurrentThread.Priority = 'BelowNormal'
try {
    $before = Get-FreeSum
    $counted = [long]0
    foreach ($p in (Get-JunkTargets)) { $counted += (Remove-Junk $p) }
    $counted += (Remove-Thumbs)
    if ($withBin) { try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue } catch { } }
    $after = Get-FreeSum
    $delta = $after - $before
    'OK:' + [Math]::Max([long]$delta, [long]$counted)
} catch { 'ERR:' + $_.Exception.Message }
'@
$junkCode = $junkFuncs + "`r`n" + $junkWorker

$junkDone = {
    param($out, $ctx)
    $btn = $ctx.Btn
    $btn.Enabled = $true
    $btn.Text = 'ล้างไฟล์ขยะ & แคช'
    try { Update-Drives } catch { }
    $res = [string](@($out)[-1])
    if ($res -like 'OK:*') {
        $n = [double]($res.Substring(3))
        [Windows.Forms.MessageBox]::Show(('ล้างเสร็จแล้ว ได้พื้นที่คืนประมาณ ' + (Format-Bytes $n)), 'Clean Junk') | Out-Null
    } else {
        [Windows.Forms.MessageBox]::Show(('ล้างไม่สำเร็จ: ' + $res), 'Clean Junk') | Out-Null
    }
}

# ---------- ปุ่ม 2 ปุ่มข้างกัน: WiFi | ล้างไฟล์ขยะ ----------
$half = [int](($W - 48 - 13) / 2)

$wifiBtn = New-Object GradButton
$wifiBtn.Text = 'ดูรหัส WiFi ที่บันทึกไว้'
$wifiBtn.C1 = [Drawing.Color]::FromArgb(14, 165, 233)
$wifiBtn.C2 = [Drawing.Color]::FromArgb(59, 130, 246)
$wifiBtn.Size = New-Object Drawing.Size($half, 46)
$wifiBtn.Location = New-Object Drawing.Point(24, $by)
$wifiBtn.Add_Click({ Show-WifiPasswords })
$form.Controls.Add($wifiBtn)

$cleanBtn = New-Object GradButton
$cleanBtn.Text = 'ล้างไฟล์ขยะ & แคช'
$cleanBtn.C1 = [Drawing.Color]::FromArgb(34, 197, 94)
$cleanBtn.C2 = [Drawing.Color]::FromArgb(16, 185, 129)
$cleanBtn.Size = New-Object Drawing.Size($half, 46)
$cleanBtn.Location = New-Object Drawing.Point((24 + $half + 13), $by)
$cleanBtn.Add_Click({
    $msg = "จะลบไฟล์ชั่วคราวและแคช ได้แก่:`n`n" +
           "• ไฟล์ Temp ของผู้ใช้และของ Windows`n" +
           "• แคช Windows Update / รายงานข้อผิดพลาด / Crash dump`n" +
           "• แคชเบราว์เซอร์ (Chrome, Edge, Brave, Firefox) - ไม่ลบรหัสผ่าน คุกกี้ หรือประวัติ`n" +
           "• แคชเชเดอร์ (DirectX/NVIDIA/AMD), Discord, Steam`n" +
           "• ถังขยะ (กู้คืนไม่ได้)`n`n" +
           "ไฟล์ที่โปรแกรมกำลังใช้อยู่จะถูกข้าม ปิดเบราว์เซอร์ก่อนจะล้างได้เยอะขึ้น`n`nดำเนินการต่อ?"
    if ([Windows.Forms.MessageBox]::Show($msg, 'Clean Junk', 'YesNo', 'Question') -ne 'Yes') { return }
    $cleanBtn.Enabled = $false
    $cleanBtn.Text = 'กำลังล้าง... (โปรแกรมไม่ค้าง)'
    Start-Bg $junkCode @{ withBin = $true } $junkDone @{ Btn = $cleanBtn }
})
$form.Controls.Add($cleanBtn)

# ---------- เกจคะแนน (วาดเองด้วย C#  คอมไพล์ตอนเปิดหน้าต่างครั้งแรก) ----------
$cs3 = @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
 
public class ScoreGauge : Control
{
    public string Caption = "Protection score";
    public string Rating = "";
    public bool Busy;
    int target = -1;
    float shown;
    float spin;
    Timer tm = new Timer();
 
    public ScoreGauge()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        Size = new Size(240, 200);
        tm.Interval = 25;
        tm.Tick += delegate { Step(); };
    }
 
    public int Score
    {
        get { return target; }
        set { target = value; Kick(); }
    }
 
    public void SetBusy(bool b) { Busy = b; Kick(); Invalidate(); }
 
    void Kick() { if (!tm.Enabled) tm.Start(); }
 
    void Step()
    {
        bool moving = false;
        float t = target < 0 ? 0f : (float)target;
        float d = t - shown;
        if (Math.Abs(d) > 0.4f) { shown += d * 0.12f; moving = true; }
        else shown = t;
        if (Busy) { spin += 7f; if (spin >= 360f) spin -= 360f; moving = true; }
        Invalidate();
        if (!moving) tm.Stop();
    }
 
    static Color ColorFor(int s)
    {
        if (s >= 90) return Color.FromArgb(74, 222, 128);
        if (s >= 75) return Color.FromArgb(163, 230, 53);
        if (s >= 50) return Color.FromArgb(251, 146, 60);
        return Color.FromArgb(248, 113, 113);
    }
 
    static Color Mix(Color a, Color b, float t)
    {
        return Color.FromArgb((int)(a.R + (b.R - a.R) * t), (int)(a.G + (b.G - a.G) * t), (int)(a.B + (b.B - a.B) * t));
    }
 
    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.Clear(BackColor);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        int side = Math.Min(Width, Height) - 8;
        if (side < 80) return;
 
        float pw = 16f;
        Rectangle box = new Rectangle((Width - side) / 2, 4, side, side);
        int inset = (int)(pw / 2 + 2);
        Rectangle ar = Rectangle.Inflate(box, -inset, -inset);
 
        // ราง
        using (Pen tp = new Pen(Color.FromArgb(46, 36, 84), pw))
        {
            tp.StartCap = LineCap.Round;
            tp.EndCap = LineCap.Round;
            g.DrawArc(tp, ar, 135f, 270f);
        }
 
        // ค่าคะแนน (ไล่สีจากอ่อนไปเข้ม เหมือน Malwarebytes)
        if (target >= 0 && shown > 0.5f)
        {
            Color c = ColorFor((int)Math.Round(shown));
            Color lite = Mix(c, Color.White, 0.55f);
            using (LinearGradientBrush lb = new LinearGradientBrush(box, lite, c, 315f))
            using (Pen vp = new Pen(lb, pw))
            {
                vp.StartCap = LineCap.Round;
                vp.EndCap = LineCap.Round;
                g.DrawArc(vp, ar, 135f, 270f * shown / 100f);
            }
        }
 
        // วงจุดด้านใน
        Rectangle dr = Rectangle.Inflate(ar, -26, -26);
        using (Pen dp = new Pen(Color.FromArgb(60, 255, 255, 255), 1.5f))
        {
            dp.DashStyle = DashStyle.Dot;
            g.DrawEllipse(dp, dr);
        }
        if (Busy)
        {
            using (Pen sp = new Pen(Color.FromArgb(196, 181, 253), 3f))
            {
                sp.StartCap = LineCap.Round;
                sp.EndCap = LineCap.Round;
                g.DrawArc(sp, dr, spin, 70f);
            }
        }
 
        // ข้อความกลางเกจ
        int cy = box.Y + side / 2;
        TextFormatFlags fl = TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter
            | TextFormatFlags.SingleLine | TextFormatFlags.NoPadding;
        using (Font f1 = new Font("ไอติม", 9.5f))
            TextRenderer.DrawText(g, Caption, f1, new Rectangle(box.X, cy - 56, side, 20), Color.FromArgb(196, 181, 253), fl);
        string num = target < 0 ? "--" : ((int)Math.Round(shown)).ToString();
        using (Font f2 = new Font("ไอติม Bold", 34f))
            TextRenderer.DrawText(g, num, f2, new Rectangle(box.X, cy - 38, side, 56), Color.White, fl);
        string rt = Busy ? "กำลังทำงาน..." : Rating;
        Color rc = (Busy || target < 0) ? Color.FromArgb(196, 181, 253) : ColorFor(target);
        using (Font f3 = new Font("ไอติม", 12f))
            TextRenderer.DrawText(g, rt, f3, new Rectangle(box.X, cy + 22, side, 26), rc, fl);
    }
 
    protected override void Dispose(bool disposing)
    {
        if (disposing) tm.Dispose();
        base.Dispose(disposing);
    }
}
'@
 
# ---------- ฟังก์ชันตรวจความปลอดภัย (รันใน runspace เบื้องหลัง) ----------
$secFuncs = @'
function Get-AgeDays($v) {
    if ($null -eq $v) { return -1 }
    try {
        $n = [double]$v
        if ($n -lt 0 -or $n -ge 4294967295) { return -1 }
        return [int]$n
    } catch { return -1 }
}
 
function Get-AgeText([int]$d) {
    if ($d -lt 0) { return 'ยังไม่เคยสแกน' }
    if ($d -eq 0) { return 'วันนี้' }
    if ($d -eq 1) { return 'เมื่อวาน' }
    return ([string]$d + ' วันก่อน')
}
 
function New-Chk([string]$id, [string]$name, [int]$max, [int]$pts, [string]$note, [bool]$app) {
    return [pscustomobject]@{ Id = $id; Name = $name; Max = $max; Pts = $pts; Note = $note; App = $app }
}
 
function Get-SecInfo {
    $checks = New-Object System.Collections.ArrayList
    $fixes = New-Object System.Collections.ArrayList
    $threatLines = New-Object System.Collections.ArrayList
    $lastText = 'ไม่ทราบ'
    $threatActive = $false
 
    # --- Windows Defender ---
    $mp = $null
    try { $mp = Get-MpComputerStatus -ErrorAction Stop } catch { }
    $defActive = $false
    if ($mp) { try { $defActive = ([bool]$mp.AntivirusEnabled -and [bool]$mp.AMServiceEnabled) } catch { } }
 
    # --- โปรแกรมป้องกันไวรัสอื่นที่ลงไว้ (อ่านจาก Security Center) ---
    $others = @()
    try {
        foreach ($p in @(Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntivirusProduct -ErrorAction Stop)) {
            $hx = ('{0:X6}' -f [int]$p.productState)
            $others += [pscustomobject]@{
                Name  = [string]$p.displayName
                On    = ($hx.Substring(2, 2) -eq '10')
                Fresh = ($hx.Substring(4, 2) -eq '00')
            }
        }
    } catch { }
    $others = @($others | Where-Object { $_.Name -notmatch 'Windows Defender|Microsoft Defender' })
 
    if ($defActive) {
        [void]$checks.Add((New-Chk 'engine' 'โปรแกรมป้องกันไวรัส' 10 10 'Windows Defender ทำงานอยู่' $true))
 
        # Real-time protection
        $rt = $false
        try { $rt = [bool]$mp.RealTimeProtectionEnabled } catch { }
        if ($rt) {
            [void]$checks.Add((New-Chk 'rt' 'Real-time protection' 20 20 'เปิดอยู่ ตรวจไฟล์ที่เปิด/ดาวน์โหลดแบบเรียลไทม์' $true))
        } else {
            [void]$checks.Add((New-Chk 'rt' 'Real-time protection' 20 0 'ปิดอยู่ เครื่องไม่ได้รับการป้องกันแบบเรียลไทม์' $true))
            [void]$fixes.Add('rt')
        }
 
        # ฐานข้อมูลไวรัส
        $sa = Get-AgeDays $mp.AntivirusSignatureAge
        if ($sa -ge 0 -and $sa -le 2) {
            [void]$checks.Add((New-Chk 'sig' 'ฐานข้อมูลไวรัส' 15 15 ('ล่าสุด (อัปเดต ' + (Get-AgeText $sa) + ')') $true))
        } elseif ($sa -ge 0 -and $sa -le 7) {
            [void]$checks.Add((New-Chk 'sig' 'ฐานข้อมูลไวรัส' 15 8 ('เริ่มเก่า (อัปเดต ' + $sa + ' วันก่อน)') $true))
            [void]$fixes.Add('sig')
        } else {
            [void]$checks.Add((New-Chk 'sig' 'ฐานข้อมูลไวรัส' 15 0 'เก่าเกินไปหรือไม่ทราบสถานะ ควรอัปเดต' $true))
            [void]$fixes.Add('sig')
        }
 
        # การสแกนล่าสุด
        $qa = Get-AgeDays $mp.QuickScanAge
        $fa = Get-AgeDays $mp.FullScanAge
        $best = -1
        foreach ($a in @($qa, $fa)) { if ($a -ge 0 -and ($best -lt 0 -or $a -lt $best)) { $best = $a } }
        $lastText = Get-AgeText $best
        if ($best -ge 0 -and $best -le 7) {
            [void]$checks.Add((New-Chk 'scan' 'สแกนล่าสุด' 10 10 ('สแกนเมื่อ ' + $lastText) $true))
        } elseif ($best -ge 0 -and $best -le 30) {
            [void]$checks.Add((New-Chk 'scan' 'สแกนล่าสุด' 10 5 ('สแกนเมื่อ ' + $lastText + ' ควรสแกนใหม่') $true))
            [void]$fixes.Add('scan')
        } else {
            [void]$checks.Add((New-Chk 'scan' 'สแกนล่าสุด' 10 0 ('ไม่ได้สแกนนานแล้ว / ' + $lastText) $true))
            [void]$fixes.Add('scan')
        }
 
        # ภัยคุกคามที่ยังค้างอยู่
        $thrOk = $true
        $act = @()
        try { $act = @(Get-MpThreat -ErrorAction Stop | Where-Object { $_.IsActive }) } catch { $thrOk = $false }
        if (-not $thrOk) {
            [void]$checks.Add((New-Chk 'thr' 'ภัยคุกคามที่ตรวจพบ' 25 0 'ตรวจรายการภัยคุกคามไม่ได้ (ไม่นำมาคิดคะแนน)' $false))
        } elseif ($act.Count -gt 0) {
            $threatActive = $true
            [void]$checks.Add((New-Chk 'thr' 'ภัยคุกคามที่ตรวจพบ' 25 0 ('พบภัยคุกคามที่ยังไม่ถูกกำจัด ' + $act.Count + ' รายการ') $true))
            [void]$fixes.Add('thr')
            foreach ($t in $act) {
                [void]$threatLines.Add([string]$t.ThreatName + '   ' + ((@($t.Resources) | Select-Object -First 2) -join '; '))
            }
        } else {
            [void]$checks.Add((New-Chk 'thr' 'ภัยคุกคามที่ตรวจพบ' 25 25 'ไม่พบภัยคุกคามที่ค้างอยู่' $true))
        }
 
        # การป้องกันเสริม
        $bm = $false; $io = $false
        try { $bm = [bool]$mp.BehaviorMonitorEnabled; $io = [bool]$mp.IoavProtectionEnabled } catch { }
        if ($bm -and $io) {
            [void]$checks.Add((New-Chk 'extra' 'การป้องกันเสริม' 5 5 'Behavior monitor และการสแกนไฟล์ดาวน์โหลดเปิดอยู่' $true))
        } elseif ($bm -or $io) {
            [void]$checks.Add((New-Chk 'extra' 'การป้องกันเสริม' 5 2 'เปิดอยู่บางส่วน (Behavior monitor / สแกนไฟล์ดาวน์โหลด)' $true))
            [void]$fixes.Add('extra')
        } else {
            [void]$checks.Add((New-Chk 'extra' 'การป้องกันเสริม' 5 0 'Behavior monitor และการสแกนไฟล์ดาวน์โหลดปิดอยู่' $true))
            [void]$fixes.Add('extra')
        }
    }
    else {
        $onOthers = @($others | Where-Object { $_.On })
        $lastText = 'ตรวจไม่ได้ (ไม่ได้ใช้ Windows Defender)'
        if ($onOthers.Count -gt 0) {
            $nm = (($onOthers | ForEach-Object { $_.Name }) -join ', ')
            [void]$checks.Add((New-Chk 'engine' 'โปรแกรมป้องกันไวรัส' 10 10 ('ใช้ ' + $nm + ' (อ่านสถานะจาก Windows Security Center)') $true))
            [void]$checks.Add((New-Chk 'rt' 'Real-time protection' 20 20 'โปรแกรมรายงานว่าเปิดการป้องกันอยู่' $true))
            $fresh = @($onOthers | Where-Object { $_.Fresh })
            if ($fresh.Count -gt 0) {
                [void]$checks.Add((New-Chk 'sig' 'ฐานข้อมูลไวรัส' 15 15 'โปรแกรมรายงานว่าเป็นเวอร์ชันล่าสุด' $true))
            } else {
                [void]$checks.Add((New-Chk 'sig' 'ฐานข้อมูลไวรัส' 15 0 'โปรแกรมรายงานว่าฐานข้อมูลล้าสมัย' $true))
            }
        } else {
            [void]$checks.Add((New-Chk 'engine' 'โปรแกรมป้องกันไวรัส' 10 0 'ไม่พบโปรแกรมป้องกันไวรัสที่ทำงานอยู่' $true))
            [void]$checks.Add((New-Chk 'rt' 'Real-time protection' 20 0 'ไม่มีการป้องกันแบบเรียลไทม์' $true))
            if ($mp) { [void]$fixes.Add('rt') }
        }
    }
 
    # --- Windows Firewall ---
    $fwOn = 0
    try {
        $pol = New-Object -ComObject HNetCfg.FwPolicy2
        foreach ($pr in 1, 2, 4) { if ($pol.FirewallEnabled($pr)) { $fwOn++ } }
    } catch { $fwOn = -1 }
    if ($fwOn -lt 0) {
        [void]$checks.Add((New-Chk 'fw' 'Windows Firewall' 10 0 'อ่านสถานะไม่ได้ (ไม่นำมาคิดคะแนน)' $false))
    } elseif ($fwOn -ge 3) {
        [void]$checks.Add((New-Chk 'fw' 'Windows Firewall' 10 10 'เปิดครบทุกโปรไฟล์' $true))
    } else {
        $fp = [int][Math]::Round(10 * $fwOn / 3)
        [void]$checks.Add((New-Chk 'fw' 'Windows Firewall' 10 $fp ('เปิดอยู่ ' + $fwOn + ' จาก 3 โปรไฟล์') $true))
        [void]$fixes.Add('fw')
    }
 
    # --- UAC ---
    $uac = $null
    try { $uac = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name EnableLUA -ErrorAction Stop).EnableLUA } catch { }
    if ($uac -eq 1) {
        [void]$checks.Add((New-Chk 'uac' 'User Account Control (UAC)' 5 5 'เปิดอยู่' $true))
    } else {
        [void]$checks.Add((New-Chk 'uac' 'User Account Control (UAC)' 5 0 'ปิดอยู่ (ต้องเปิดเองในการตั้งค่า Windows แล้วรีสตาร์ท)' $true))
    }
 
    # --- คำนวณคะแนน ---
    $max = 0; $pts = 0
    foreach ($c in $checks) { if ($c.App) { $max += $c.Max; $pts += $c.Pts } }
    $score = 0
    if ($max -gt 0) { $score = [int][Math]::Round($pts * 100.0 / $max) }
    if ($threatActive -and $score -gt 49) { $score = 49 }
 
    $rating = 'เสี่ยง'
    if ($score -ge 90) { $rating = 'ปลอดภัยมาก' }
    elseif ($score -ge 75) { $rating = 'ดี' }
    elseif ($score -ge 50) { $rating = 'พอใช้' }
 
    $order = @('sig', 'rt', 'extra', 'fw', 'thr', 'scan')
    $fx = @($order | Where-Object { $fixes -contains $_ })
 
    return [pscustomobject]@{
        Score    = $score
        Rating   = $rating
        Checks   = @($checks)
        Fixes    = $fx
        LastScan = $lastText
        DefActive = $defActive
        Threats  = @($threatLines)
    }
}
'@
 
# งานตรวจสอบอย่างเดียว (ไม่สแกน)
$secCheckWorker = @'
try { Get-SecInfo } catch { 'ERR:' + $_.Exception.Message }
'@
$secCheckCode = $secFuncs + "`r`n" + $secCheckWorker
 
# งานสแกน ($stype = QuickScan / FullScan / CustomScan, $spath = โฟลเดอร์สำหรับ CustomScan)
$secScanWorker = @'
[Threading.Thread]::CurrentThread.Priority = 'BelowNormal'
try {
    $before = @{}
    foreach ($d in @(Get-MpThreatDetection -ErrorAction SilentlyContinue)) { $before[[string]$d.DetectionID] = 1 }
 
    if ($stype -eq 'CustomScan') { Start-MpScan -ScanType CustomScan -ScanPath $spath -ErrorAction Stop }
    else { Start-MpScan -ScanType $stype -ErrorAction Stop }
 
    $stMap = @{ 1 = 'ตรวจพบ'; 2 = 'ทำความสะอาดแล้ว'; 3 = 'กักกันแล้ว'; 4 = 'ลบแล้ว'; 5 = 'อนุญาตไว้'; 6 = 'บล็อกแล้ว';
                102 = 'กักกันล้มเหลว'; 103 = 'ลบล้มเหลว'; 104 = 'อนุญาตล้มเหลว'; 105 = 'ถูกยกเลิก'; 107 = 'บล็อกล้มเหลว' }
    $names = @{}
    foreach ($t in @(Get-MpThreat -ErrorAction SilentlyContinue)) { $names[[string]$t.ThreatID] = [string]$t.ThreatName }
 
    $nl = [Environment]::NewLine
    $det = New-Object System.Collections.ArrayList
    foreach ($d in @(Get-MpThreatDetection -ErrorAction SilentlyContinue)) {
        if ($before.ContainsKey([string]$d.DetectionID)) { continue }
        $nm = $names[[string]$d.ThreatID]
        if (-not $nm) { $nm = 'Threat ID ' + $d.ThreatID }
        $stt = $stMap[[int]$d.ThreatStatusID]
        if (-not $stt) { $stt = 'สถานะ ' + $d.ThreatStatusID }
        $res = ((@($d.Resources) | Select-Object -First 2) -join '; ')
        [void]$det.Add($nm + '  [' + $stt + ']' + $nl + '     ' + $res)
    }
 
    $info = Get-SecInfo
    Add-Member -InputObject $info -NotePropertyMembers @{ DetCount = [int]$det.Count; DetText = ($det -join $nl) } -PassThru
} catch { 'ERR:' + $_.Exception.Message }
'@
$secScanCode = $secFuncs + "`r`n" + $secScanWorker
 
# งานแก้ไขอัตโนมัติ ($fixes = รายการ id)
$secFixWorker = @'
[Threading.Thread]::CurrentThread.Priority = 'BelowNormal'
try {
    $log = New-Object System.Collections.ArrayList
    $fwFixed = $false
    foreach ($f in @($fixes)) {
        try {
            switch ([string]$f) {
                'sig'   { Update-MpSignature -ErrorAction Stop; [void]$log.Add('อัปเดตฐานข้อมูลไวรัสแล้ว') }
                'rt'    { Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop; [void]$log.Add('เปิด Real-time protection แล้ว') }
                'extra' { Set-MpPreference -DisableBehaviorMonitoring $false -DisableIOAVProtection $false -ErrorAction Stop; [void]$log.Add('เปิด Behavior monitor และการสแกนไฟล์ดาวน์โหลดแล้ว') }
                'fw'    { $null = & netsh advfirewall set allprofiles state on 2>&1; if ($LASTEXITCODE -ne 0) { throw 'netsh ทำงานไม่สำเร็จ' }; $fwFixed = $true; [void]$log.Add('เปิด Windows Firewall แล้ว') }
                'thr'   { Remove-MpThreat -ErrorAction Stop; [void]$log.Add('กำจัดภัยคุกคามแล้ว') }
                'scan'  { Start-MpScan -ScanType QuickScan -ErrorAction Stop; [void]$log.Add('สแกนด่วนเสร็จแล้ว') }
            }
        } catch { [void]$log.Add('ไม่สำเร็จ [' + $f + ']: ' + $_.Exception.Message) }
    }
    $info = Get-SecInfo
    Add-Member -InputObject $info -NotePropertyMembers @{ FixText = ($log -join [Environment]::NewLine); FwFixed = [bool]$fwFixed } -PassThru
} catch { 'ERR:' + $_.Exception.Message }
'@
$secFixCode = $secFuncs + "`r`n" + $secFixWorker
 
# ---------- สถานะของหน้าต่าง Security ----------
$script:secUi = $null
$script:secBusy = $false
$script:secT0 = Get-Date
$script:secMsg = ''
$script:secInfo = $null
$script:secTm = $null
 
function Set-SecStatus([string]$t) {
    $u = $script:secUi
    if ($null -eq $u -or $u.Form.IsDisposed) { return }
    $u.Status.Text = $t
}
 
function Set-SecBusy([bool]$b, [string]$msg = '') {
    $was = $script:secBusy
    $script:secBusy = $b
    if ($b) {
        if (-not $was) { $script:secT0 = Get-Date }
        $script:secMsg = $msg
    }
    $u = $script:secUi
    if ($null -eq $u -or $u.Form.IsDisposed) { return }
    foreach ($x in $u.Btns) { $x.Enabled = (-not $b) }
    $u.Gauge.SetBusy($b)
    if ($b) { $u.Status.Text = $msg } else { $u.Status.Text = 'พร้อมสแกน' }
}
 
function Update-SecUi($info) {
    $u = $script:secUi
    if ($null -eq $u -or $u.Form.IsDisposed) { return }
    $script:secInfo = $info
 
    $u.Gauge.Rating = [string]$info.Rating
    $u.Gauge.Score = [int]$info.Score
    $u.Last.Text = 'สแกนล่าสุด: ' + [string]$info.LastScan
 
    $ok = [string][char]0x2714
    $no = [string][char]0x2716
    $nl = [Environment]::NewLine
    $sb = New-Object Text.StringBuilder
    [void]$sb.AppendLine('ผลการตรวจสอบ (ยิ่งคะแนนเต็มยิ่งปลอดภัย)')
    [void]$sb.AppendLine('')
    foreach ($c in @($info.Checks)) {
        if (-not $c.App) { $mk = '-' }
        elseif ($c.Pts -ge $c.Max) { $mk = $ok }
        elseif ($c.Pts -gt 0) { $mk = '!' }
        else { $mk = $no }
        $pt = ''
        if ($c.App) { $pt = '   (' + $c.Pts + '/' + $c.Max + ')' }
        [void]$sb.AppendLine($mk + '  ' + $c.Name + $pt)
        [void]$sb.AppendLine('      ' + $c.Note)
    }
    $thr = @($info.Threats)
    if ($thr.Count -gt 0) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('ภัยคุกคามที่ยังค้างอยู่:')
        foreach ($t in $thr) { [void]$sb.AppendLine('  ' + $no + ' ' + $t) }
    }
    if ($info.PSObject.Properties['DetCount'] -and [int]$info.DetCount -gt 0) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('ตรวจพบในการสแกนครั้งนี้ (' + $info.DetCount + ' รายการ):')
        [void]$sb.AppendLine([string]$info.DetText)
    }
        $newTxt = $sb.ToString()
    if ($u.Box.Text -ne $newTxt) {
        $u.Box.Text = $newTxt
        $u.Box.SelectionStart = 0
        $u.Box.ScrollToCaret()
    }
 
    $u.Boost.Visible = (@($info.Fixes).Count -gt 0)
}
 
function Start-SecCheck {
    if ($script:secBusy) { return }
    Set-SecBusy $true 'กำลังตรวจสอบความปลอดภัย...'
    Start-Bg $script:secCheckCode @{} $script:secCheckDone @{}
}
 
function Start-SecScan([string]$type, [string]$path) {
    if ($script:secBusy) { return }
    $names = @{ QuickScan = 'กำลังสแกนด่วน...'; FullScan = 'กำลังสแกนทั้งเครื่อง...'; CustomScan = 'กำลังสแกนโฟลเดอร์...' }
    Set-SecBusy $true $names[$type]
    Start-Bg $script:secScanCode @{ stype = $type; spath = $path } $script:secScanDone @{}
}
 
function Start-SecFix {
    if ($script:secBusy -or $null -eq $script:secInfo) { return }
    $fx = @($script:secInfo.Fixes | ForEach-Object { [string]$_ })
    if ($fx.Count -eq 0) { return }
    $desc = @{
        sig   = '• อัปเดตฐานข้อมูลไวรัส'
        rt    = '• เปิด Real-time protection'
        extra = '• เปิด Behavior monitor / สแกนไฟล์ดาวน์โหลด'
        fw    = '• เปิด Windows Firewall ทุกโปรไฟล์ (สวิตช์ Bypass Firewall ในโปรแกรมนี้จะถูกปิดตาม)'
        thr   = '• กำจัดภัยคุกคามที่ตรวจพบ'
        scan  = '• สแกนด่วน 1 รอบ (ใช้เวลาสักครู่)'
    }
    $lines = (($fx | ForEach-Object { $desc[[string]$_] }) -join "`n")
    $ans = [Windows.Forms.MessageBox]::Show(("จะดำเนินการต่อไปนี้:`n`n" + $lines + "`n`nดำเนินการต่อ?"), 'Boost your score', 'YesNo', 'Question')
    if ($ans -ne 'Yes') { return }
    Set-SecBusy $true 'กำลังปรับปรุงความปลอดภัย...'
    Start-Bg $script:secFixCode @{ fixes = [string[]]$fx } $script:secFixDone @{}
}
 
# ---------- callback เมื่องานเบื้องหลังเสร็จ ----------
$secCheckDone = {
    param($out, $ctx)
    $last = @($out)[-1]
    Set-SecBusy $false
    if ($null -ne $last -and $last.PSObject.Properties['Score']) { Update-SecUi $last }
    else { Set-SecStatus ('ตรวจสอบไม่สำเร็จ: ' + [string]$last) }
}
 
$secScanDone = {
    param($out, $ctx)
    $last = @($out)[-1]
    Set-SecBusy $false
    if ($null -ne $last -and $last.PSObject.Properties['Score']) {
        Update-SecUi $last
        Set-SecStatus ('สแกนเสร็จเมื่อ ' + (Get-Date).ToString('HH:mm'))
        $n = [int]$last.DetCount
        if ($n -gt 0) {
            [Windows.Forms.MessageBox]::Show(('สแกนเสร็จแล้ว พบภัยคุกคาม ' + $n + ' รายการ' + "`n`n" + 'ดูรายละเอียดในรายการด้านล่าง ถ้ายังมีภัยค้างอยู่ให้กด "เพิ่มคะแนน" เพื่อกำจัด'), 'Security Scan') | Out-Null
        } else {
            [Windows.Forms.MessageBox]::Show(('สแกนเสร็จแล้ว ไม่พบภัยคุกคาม' + "`n`n" + 'คะแนนความปลอดภัย: ' + $last.Score + ' (' + $last.Rating + ')'), 'Security Scan') | Out-Null
        }
    } else {
        [Windows.Forms.MessageBox]::Show(('สแกนไม่สำเร็จ: ' + [string]$last + "`n`n" + 'ตรวจสอบว่า Windows Defender เปิดอยู่ และไม่ได้ถูกปิดด้วยโปรแกรมป้องกันไวรัสอื่น'), 'Security Scan') | Out-Null
    }
}
 
$secFixDone = {
    param($out, $ctx)
    $last = @($out)[-1]
    Set-SecBusy $false
    if ($null -ne $last -and $last.PSObject.Properties['Score']) {
        if ($last.FwFixed -and $script:tgMap['fw'].Checked) {
            $script:loading = $true
            $script:tgMap['fw'].Checked = $false
            $script:loading = $false
        }
        Update-SecUi $last
        [Windows.Forms.MessageBox]::Show(([string]$last.FixText + "`n`n" + 'คะแนนตอนนี้: ' + $last.Score + ' (' + $last.Rating + ')'), 'Boost your score') | Out-Null
    } else {
        [Windows.Forms.MessageBox]::Show(('ทำงานไม่สำเร็จ: ' + [string]$last), 'Boost your score') | Out-Null
    }
}
 
# ---------- หน้าต่าง Security Scan ----------
$script:secAuto = $false

$secAutoDone = {
    param($out, $ctx)
    $script:secAuto = $false
    if ($script:secBusy) { return }
    try {
        $last = @($out)[-1]
        if ($null -ne $last -and $last.PSObject.Properties['Score']) {
            $old = $script:secInfo
            if ($null -ne $old -and $old.PSObject.Properties['DetCount']) {
                Add-Member -InputObject $last -NotePropertyMembers @{ DetCount = $old.DetCount; DetText = $old.DetText } -Force
            }
            Update-SecUi $last
            Set-SecStatus ('อัปเดตอัตโนมัติ ' + (Get-Date).ToString('HH:mm:ss'))
        }
    } catch { }
}

function Start-SecAuto {
    if ($script:secBusy -or $script:secAuto) { return }
    $script:secAuto = $true
    Start-Bg $script:secCheckCode @{} $script:secAutoDone @{}
}
function Show-SecurityCenter {
    if (-not ('ScoreGauge' -as [type])) {
        Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition $script:cs3 -Language CSharp -ErrorAction Stop
    }
    if ($null -ne $script:secUi -and -not $script:secUi.Form.IsDisposed) { $script:secUi.Form.Activate(); return }
 
    $sfW = 500
    $sfH = 690
    $cWh = [Drawing.Color]::White
    $cLv = [Drawing.Color]::FromArgb(196, 181, 253)
    $cMt = [Drawing.Color]::FromArgb(148, 140, 170)
    $cCd = [Drawing.Color]::FromArgb(24, 13, 50)
    $cGr = [Drawing.Color]::FromArgb(74, 222, 128)
 
    $sf = New-Object GradForm
    $sf.Radius = 14
    $sf.BgA = [Drawing.Color]::FromArgb(9, 5, 20)
    $sf.BgB = [Drawing.Color]::FromArgb(36, 15, 70)
    $sf.Glows = $false
    $sf.Text = 'Security Scan'
    $sf.ClientSize = New-Object Drawing.Size($sfW, $sfH)
    $sf.StartPosition = 'CenterScreen'
    $sf.KeyPreview = $true
    $sf.Font = New-Object Drawing.Font('Segoe UI', 10)
 
    $tt = New-Object Windows.Forms.Label
    $tt.Text = 'Security Scan'
    $tt.Font = New-Object Drawing.Font('ไอติม Bold', 16)
    $tt.ForeColor = $cWh
    $tt.BackColor = [Drawing.Color]::Transparent
    $tt.AutoSize = $true
    $tt.Location = New-Object Drawing.Point(24, 18)
    $tt.Add_MouseDown({ [Gfx]::Drag($sf.Handle) })
 
    $xx = New-Object Windows.Forms.Label
    $xx.Text = [string][char]0x2715
    $xx.Font = New-Object Drawing.Font('Segoe UI Symbol', 12)
    $xx.ForeColor = $cLv
    $xx.BackColor = [Drawing.Color]::Transparent
    $xx.Cursor = [Windows.Forms.Cursors]::Hand
    $xx.Size = New-Object Drawing.Size(32, 32)
    $xx.TextAlign = 'MiddleCenter'
    $xx.Location = New-Object Drawing.Point(($sfW - 48), 14)
    $xx.Add_MouseEnter({ $xx.ForeColor = [Drawing.Color]::White })
    $xx.Add_MouseLeave({ $xx.ForeColor = [Drawing.Color]::FromArgb(196, 181, 253) })
    $xx.Add_Click({ $sf.Close() })
 
    # --- การ์ดเกจคะแนน ---
    $gc = New-Object Card
    $gc.BackColor = [Drawing.Color]::Transparent
    $gc.Size = New-Object Drawing.Size(($sfW - 48), 246)
    $gc.Location = New-Object Drawing.Point(24, 64)
 
    $gauge = New-Object ScoreGauge
    $gauge.BackColor = $cCd
    $gauge.Size = New-Object Drawing.Size(240, 200)
    $gauge.Location = New-Object Drawing.Point([int](($sfW - 48 - 240) / 2), 8)
 
    $boost = New-Object Windows.Forms.Label
    $boost.Text = 'เพิ่มคะแนนความปลอดภัย ' + [string][char]0x2192
    $boost.Font = New-Object Drawing.Font('ไอติม', 11)
    $boost.ForeColor = $cGr
    $boost.BackColor = $cCd
    $boost.TextAlign = 'MiddleCenter'
    $boost.Cursor = [Windows.Forms.Cursors]::Hand
    $boost.Size = New-Object Drawing.Size(($sfW - 48), 26)
    $boost.Location = New-Object Drawing.Point(0, 212)
    $boost.Visible = $false
    $boost.Add_Click({ Start-SecFix })
 
    $refresh = New-Object Windows.Forms.Label
    $refresh.Text = 'ตรวจใหม่ ' + [string][char]0x21BB
    $refresh.Font = New-Object Drawing.Font('Segoe UI', 9)
    $refresh.ForeColor = $cLv
    $refresh.BackColor = $cCd
    $refresh.TextAlign = 'MiddleRight'
    $refresh.Cursor = [Windows.Forms.Cursors]::Hand
    $refresh.Size = New-Object Drawing.Size(100, 22)
    $refresh.Location = New-Object Drawing.Point(($sfW - 48 - 112), 10)
    $refresh.Add_Click({ Start-SecCheck })
 
    $gc.Controls.AddRange(@($gauge, $boost, $refresh))
 
    # --- การ์ด Scanner ---
    $sc = New-Object Card
    $sc.BackColor = [Drawing.Color]::Transparent
    $sc.Size = New-Object Drawing.Size(($sfW - 48), 138)
    $sc.Location = New-Object Drawing.Point(24, 322)
 
    $ic = New-Object Windows.Forms.Label
    $ic.Text = [string][char]0x25CE
    $ic.Font = New-Object Drawing.Font('Segoe UI Symbol', 20)
    $ic.ForeColor = $cGr
    $ic.BackColor = $cCd
    $ic.TextAlign = 'MiddleCenter'
    $ic.Size = New-Object Drawing.Size(40, 40)
    $ic.Location = New-Object Drawing.Point(14, 10)
 
    $sn = New-Object Windows.Forms.Label
    $sn.Text = 'Scanner'
    $sn.Font = New-Object Drawing.Font('ไอติม', 13)
    $sn.ForeColor = $cWh
    $sn.BackColor = $cCd
    $sn.AutoSize = $true
    $sn.Location = New-Object Drawing.Point(62, 8)
 
    $lLast = New-Object Windows.Forms.Label
    $lLast.Text = 'สแกนล่าสุด: ...'
    $lLast.Font = New-Object Drawing.Font('Segoe UI', 9.5)
    $lLast.ForeColor = $cMt
    $lLast.BackColor = $cCd
    $lLast.AutoSize = $false
    $lLast.Size = New-Object Drawing.Size(($sfW - 48 - 76), 20)
    $lLast.Location = New-Object Drawing.Point(62, 34)
 
    $lStat = New-Object Windows.Forms.Label
    $lStat.Text = 'กำลังเริ่มต้น...'
    $lStat.Font = New-Object Drawing.Font('Segoe UI', 9.5)
    $lStat.ForeColor = $cLv
    $lStat.BackColor = $cCd
    $lStat.AutoSize = $false
    $lStat.Size = New-Object Drawing.Size(($sfW - 48 - 28), 22)
    $lStat.Location = New-Object Drawing.Point(18, 62)
 
    $btnQ = New-Object GradButton
    $btnQ.Text = 'สแกนด่วน'
    $btnQ.C1 = [Drawing.Color]::FromArgb(109, 40, 217)
    $btnQ.C2 = [Drawing.Color]::FromArgb(34, 160, 110)
    $btnQ.Size = New-Object Drawing.Size(132, 38)
    $btnQ.Location = New-Object Drawing.Point(18, 90)
    $btnQ.Add_Click({ Start-SecScan 'QuickScan' '' })
 
    $btnF = New-Object GradButton
    $btnF.Text = 'สแกนทั้งเครื่อง'
    $btnF.C1 = [Drawing.Color]::FromArgb(88, 32, 176)
    $btnF.C2 = [Drawing.Color]::FromArgb(124, 58, 237)
    $btnF.Size = New-Object Drawing.Size(132, 38)
    $btnF.Location = New-Object Drawing.Point(160, 90)
    $btnF.Add_Click({
        $a = [Windows.Forms.MessageBox]::Show(("สแกนทั้งเครื่องอาจใช้เวลานาน (หลายสิบนาทีถึงหลายชั่วโมง) และกดยกเลิกกลางคันไม่ได้`n`nดำเนินการต่อ?"), 'Full Scan', 'YesNo', 'Question')
        if ($a -eq 'Yes') { Start-SecScan 'FullScan' '' }
    })
 
    $btnC = New-Object GradButton
    $btnC.Text = 'เลือกโฟลเดอร์'
    $btnC.C1 = [Drawing.Color]::FromArgb(70, 50, 120)
    $btnC.C2 = [Drawing.Color]::FromArgb(109, 40, 217)
    $btnC.Size = New-Object Drawing.Size(132, 38)
    $btnC.Location = New-Object Drawing.Point(302, 90)
    $btnC.Add_Click({
        $fbd = New-Object Windows.Forms.FolderBrowserDialog
        $fbd.Description = 'เลือกโฟลเดอร์ที่ต้องการสแกน'
        if ($fbd.ShowDialog() -eq 'OK' -and $fbd.SelectedPath) { Start-SecScan 'CustomScan' $fbd.SelectedPath }
    })
 
    $sc.Controls.AddRange(@($ic, $sn, $lLast, $lStat, $btnQ, $btnF, $btnC))
 
    # --- การ์ดรายการตรวจสอบ ---
    $fc = New-Object Card
    $fc.BackColor = [Drawing.Color]::Transparent
    $fc.Size = New-Object Drawing.Size(($sfW - 48), 190)
    $fc.Location = New-Object Drawing.Point(24, 472)
 
    $txt = New-Object Windows.Forms.TextBox
    $txt.Multiline = $true
    $txt.ReadOnly = $true
    $txt.ScrollBars = 'Vertical'
    $txt.BorderStyle = 'None'
    $txt.BackColor = $cCd
    $txt.ForeColor = $cWh
    $txt.Font = New-Object Drawing.Font('Segoe UI', 9.5)
    $txt.Size = New-Object Drawing.Size(($sfW - 48 - 24), 166)
    $txt.Location = New-Object Drawing.Point(12, 12)
    $txt.Text = 'กำลังตรวจสอบ...'
    $fc.Controls.Add($txt)
 
    $sf.Controls.AddRange(@($tt, $xx, $gc, $sc, $fc))
 
    $script:secUi = @{
        Form = $sf; Gauge = $gauge; Last = $lLast; Status = $lStat; Box = $txt; Boost = $boost
        Btns = @($btnQ, $btnF, $btnC, $refresh)
    }
 
    # ตัวนับเวลาระหว่างสแกน
        $script:secTick = 0
    $script:secAutoT0 = Get-Date
    $script:secTm = New-Object Windows.Forms.Timer
    $script:secTm.Interval = 1000
    $script:secTm.Add_Tick({
        try {
            $u = $script:secUi
            if ($null -eq $u -or $u.Form.IsDisposed) { return }
            if ($script:secBusy) {
                $script:secTick = 0
                $el = (Get-Date) - $script:secT0
                $u.Status.Text = $script:secMsg + '  ' + ('{0:00}:{1:00}' -f [int][Math]::Floor($el.TotalMinutes), $el.Seconds)
                return
            }
            if ($script:secAuto) {
                if (((Get-Date) - $script:secAutoT0).TotalSeconds -gt 25) { $script:secAuto = $false }
                return
            }
            $script:secTick++
            if ($script:secTick -ge 3) {
                $script:secTick = 0
                $script:secAuto = $true
                $script:secAutoT0 = Get-Date
                try { Start-Bg $script:secCheckCode @{} $script:secAutoDone @{} } catch { $script:secAuto = $false }
            }
        } catch { $script:secAuto = $false }
    })
    $script:secTm.Start()
 
    $sf.Add_KeyDown({
        param($sender, $e)
        if ($e.KeyCode -eq 'Escape') { $sf.Close() }
    })
    $sf.Add_FormClosed({
        try { $script:secTm.Stop(); $script:secTm.Dispose() } catch { }
        $script:secUi = $null
    })
    $sf.Add_Shown({
        if ($script:secBusy) { Set-SecBusy $true $script:secMsg } else { Start-SecCheck }
    })
 
    [void]$sf.ShowDialog()
}
 
# ---------- จัดปุ่มแถวล่างเป็น 3 ปุ่ม + เพิ่มปุ่มสแกนไวรัส ----------
$third = [int](($W - 48 - 26) / 3)
$wifiBtn.Size = New-Object Drawing.Size($third, 46)
$wifiBtn.Location = New-Object Drawing.Point(24, $by)
$cleanBtn.Size = New-Object Drawing.Size($third, 46)
$cleanBtn.Location = New-Object Drawing.Point((24 + $third + 13), $by)
 
$secBtn = New-Object GradButton
$secBtn.Text = 'สแกนไวรัส & ความปลอดภัย'
$secBtn.C1 = [Drawing.Color]::FromArgb(109, 40, 217)
$secBtn.C2 = [Drawing.Color]::FromArgb(34, 160, 110)
$secBtn.Size = New-Object Drawing.Size($third, 46)
$secBtn.Location = New-Object Drawing.Point((24 + 2 * ($third + 13)), $by)
$secBtn.Add_Click({ Show-SecurityCenter })
$form.Controls.Add($secBtn)

# ปรับความสูงหน้าต่างตามจำนวนแถวไดรฟ์
$H = $by + 88
$form.ClientSize = New-Object Drawing.Size($W, $H)
$summary.Location = New-Object Drawing.Point(0, ($H - 40))
$form.Controls.Add($summary)
UpdateSummary



# =====================================================================
#  ตัวอัปเดตกราฟเรียลไทม์ (ทุก 1 วินาที)  -  แค่อ่านค่าจาก thread เบื้องหลัง ไม่เรียกคำสั่งหนัก ๆ บน UI
# =====================================================================
$script:mon = New-Object SysMon
$script:mon.Start()

$tm = New-Object Windows.Forms.Timer
$tm.Interval = 1000
$tm.Add_Tick({
    $m = $script:mon

    Set-Row 'cpu' $m.Cpu ([string]$m.Cpu + '%') 'การใช้งานรวมทุก core'
    Set-Row 'ram' $m.RamPct ([string]$m.RamPct + '%') ('{0:N1} / {1:N1} GB' -f $m.RamUsed, $m.RamTotal)

    if (-not $m.GpuOk) { Set-Row 'gpu' 0 'N/A' 'ไม่พบ nvidia-smi / การ์ด NVIDIA' }
    elseif ($m.GpuText) { Set-Row 'gpu' $m.GpuV $m.GpuText $m.GpuSub }
    else { Set-Row 'gpu' 0 '-' 'กำลังอ่านค่า...' }

    if ($m.PingSeen) {
        if ($m.PingOk) { Set-Row 'ping' $m.PingMs ([string]$m.PingMs + ' ms') 'ปลายทาง 8.8.8.8' }
        else { Set-Row 'ping' 0 'Timeout' 'ปลายทาง 8.8.8.8' }
    }

    if ($m.Wifi -ge 0) { Set-Row 'wifi' $m.Wifi ([string]$m.Wifi + '%') ('SSID: ' + $m.Ssid) }
    else { Set-Row 'wifi' 0 'ไม่ได้ใช้ WiFi' 'ไม่พบการเชื่อมต่อ Wi-Fi (อาจใช้สาย LAN)' }
})

$form.Add_KeyDown({
    param($sender, $e)
    if ($e.KeyCode -eq 'Escape') { $form.Close() }
})
$form.Add_FormClosed({
    $tm.Stop(); $tm.Dispose()
    $spTm.Stop(); $spTm.Dispose(); $script:eng.Cancel()
    $bgTm.Stop(); $bgTm.Dispose()
    $script:memTm.Stop(); $script:memTm.Dispose()
    $script:mon.Stop()
})

# ---------- สวิตช์ "จำการตั้งค่า" มุมขวาบน ----------
$remCard = New-Object Card
$remCard.BackColor = [Drawing.Color]::Transparent
$remCard.Size = New-Object Drawing.Size(180, 40)
$remCard.Location = New-Object Drawing.Point(($W - 48 - 190), 16)

$remLbl = New-Object Windows.Forms.Label
$remLbl.Text = 'จำการตั้งค่า'
$remLbl.Font = New-Object Drawing.Font('ไอติม', 10)
$remLbl.ForeColor = $cWhite
$remLbl.BackColor = $cCard
$remLbl.AutoSize = $true
$remLbl.Location = New-Object Drawing.Point(14, 9)

$remTg = New-Object ToggleSwitch
$remTg.BackColor = $cCard
$remTg.Size = New-Object Drawing.Size(48, 26)
$remTg.Location = New-Object Drawing.Point(120, 7)
$remTg.Checked = [bool]$script:cfg.remember
$remTg.Add_CheckedChanged({
    param($sender, $e)
    $script:cfg.remember = $sender.Checked
    Save-Cfg
    if ($sender.Checked) { Save-Settings }     # เปิดสวิตช์ = บันทึกสถานะปัจจุบันทันที
})

$remCard.Controls.AddRange(@($remLbl, $remTg))
$form.Controls.Add($remCard)

# ---------- โหลดค่าที่จำไว้ของเครื่องนี้ ตอนหน้าต่างแสดงขึ้นมา ----------
$form.Add_Shown({
    try {
        if ($script:cfg.remember) {
            $sv = $script:cfg.settings[$myHw]
            if ($sv) {
                foreach ($k in @('net', 'web', 'game', 'mem', 'fw')) {
                    if ($sv.ContainsKey($k)) {
                        $want = [bool]$sv[$k]
                        $t = $script:tgMap[$k]
                        if ($t -and ($t.Checked -ne $want)) { $t.Checked = $want }
                    }
                }
            }
        }
    } catch { }
    $script:cfgReady = $true
})

# ===== THEME: Orion (ม่วงเข้ม + เขียวนีออน) =====
$tGreen  = [Drawing.Color]::FromArgb(74, 222, 128)
$tMint   = [Drawing.Color]::FromArgb(52, 211, 153)
$tPurple = [Drawing.Color]::FromArgb(168, 85, 247)
$tViolet = [Drawing.Color]::FromArgb(192, 132, 252)
$tTeal   = [Drawing.Color]::FromArgb(45, 212, 191)
 
$form.BgA = [Drawing.Color]::FromArgb(9, 5, 20)
$form.BgB = [Drawing.Color]::FromArgb(36, 15, 70)
 
# กราฟ 5 ใบ
$tmap = @{ cpu = $tGreen; ram = $tPurple; gpu = $tViolet; ping = $tMint; wifi = $tTeal }
foreach ($k in $tmap.Keys) {
    $script:ui[$k].G.Line = $tmap[$k]
    $script:ui[$k].Val.ForeColor = $tmap[$k]
}
 
# Speed Test
$cDown = $tGreen; $cUp = $tViolet; $cPing = $tMint
$spG.Line = $cDown
$vPing.ForeColor = $cPing; $vDown.ForeColor = $cDown; $vUp.ForeColor = $cUp
$spGo.C1 = $tPurple; $spGo.C2 = $tGreen
 
# ปุ่ม
$wifiBtn.C1 = [Drawing.Color]::FromArgb(109, 40, 217)
$wifiBtn.C2 = [Drawing.Color]::FromArgb(34, 160, 110)
$cleanBtn.C1 = [Drawing.Color]::FromArgb(22, 163, 74)
$cleanBtn.C2 = $tMint
 
# สวิตช์ (เปิด = เขียวนีออน / ปิด = เทาม่วง)
foreach ($c in $form.Controls) {
    if ($c -is [Card]) {
        foreach ($x in $c.Controls) {
            if ($x -is [ToggleSwitch]) {
                $x.OnColor = $tGreen
                $x.OffColor = [Drawing.Color]::FromArgb(70, 58, 104)
            }
        }
    }
}
$sub.ForeColor = [Drawing.Color]::FromArgb(150, 140, 190)

# =====================================================================
#  ORION LAYOUT  -  จัดหน้าตาใหม่ให้เหมือนดีไซน์อวกาศ (Dashboard)
#  ใช้การ์ด/ตัวควบคุมเดิมทั้งหมด (สวิตช์, Speed Test, ไดรฟ์, ปุ่มเครื่องมือ) แค่ย้ายมาอยู่ในเลย์เอาต์ใหม่
# =====================================================================
$oldTop = @($form.Controls | ForEach-Object { $_ })

$form.Glows = $false
$form.Stars = $true
$form.BgA = [Drawing.Color]::FromArgb(6, 4, 14)
$form.BgB = [Drawing.Color]::FromArgb(22, 10, 44)

$oW = 1040
$oPad = 20
$oCW = $oW - 2 * $oPad
$oLav = [Drawing.Color]::FromArgb(150, 140, 190)
$oGreen = [Drawing.Color]::FromArgb(74, 222, 128)
$oViolet = [Drawing.Color]::FromArgb(192, 132, 252)
$oBarFill = [Drawing.Color]::FromArgb(33, 19, 64)

# ---------- ย้ายตัวควบคุมที่ต้องใช้ต่อ ออกจากการ์ดเดิม แล้วซ่อนของเก่า ----------
$drvCards = @($script:drvUi | ForEach-Object { $_.Bar.Parent })
$keepTop = @($summary) + $drvCards
foreach ($c in $oldTop) {
    if ($keepTop -contains $c) { continue }
    $c.Visible = $false
}

# ---------- ส่วนหัว ----------
$hTitle = New-Object Windows.Forms.Label
$hTitle.Text = 'Fam Bypass'
$hTitle.Font = New-Object Drawing.Font('ไอติม', 22, [Drawing.FontStyle]::Bold)
$hTitle.ForeColor = $cWhite
$hTitle.BackColor = [Drawing.Color]::Transparent
$hTitle.AutoSize = $true
$hTitle.Location = New-Object Drawing.Point(24, 8)
$hTitle.Add_MouseDown({ [Gfx]::Drag($form.Handle) })

$hSub = New-Object Windows.Forms.Label
$hSub.Text = 'Overview & quick controls'
$hSub.UseMnemonic = $false
$hSub.Font = New-Object Drawing.Font('Segoe UI', 9)
$hSub.ForeColor = $oLav
$hSub.BackColor = [Drawing.Color]::Transparent
$hSub.AutoSize = $true
$hSub.Location = New-Object Drawing.Point(27, 50)
$hSub.Add_MouseDown({ [Gfx]::Drag($form.Handle) })

$pill = New-Object Pill
$pill.Size = New-Object Drawing.Size(104, 30)
$pill.Location = New-Object Drawing.Point(($oW - 250), 18)

$hMin = New-Object Windows.Forms.Label
$hMin.Text = [string][char]0x2013
$hMin.Font = New-Object Drawing.Font('Segoe UI', 13)
$hMin.ForeColor = $oLav
$hMin.BackColor = [Drawing.Color]::Transparent
$hMin.Cursor = [Windows.Forms.Cursors]::Hand
$hMin.Size = New-Object Drawing.Size(32, 32)
$hMin.TextAlign = 'MiddleCenter'
$hMin.Location = New-Object Drawing.Point(($oW - 132), 17)
$hMin.Add_MouseEnter({ $hMin.ForeColor = $cWhite })
$hMin.Add_MouseLeave({ $hMin.ForeColor = $oLav })
$hMin.Add_Click({ $form.WindowState = [Windows.Forms.FormWindowState]::Minimized })

$hMax = New-Object Windows.Forms.Label
$hMax.Text = [string][char]0x25A1
$hMax.Font = New-Object Drawing.Font('Segoe UI', 11)
$hMax.ForeColor = $oLav
$hMax.BackColor = [Drawing.Color]::Transparent
$hMax.Cursor = [Windows.Forms.Cursors]::Hand
$hMax.Size = New-Object Drawing.Size(32, 32)
$hMax.TextAlign = 'MiddleCenter'
$hMax.Location = New-Object Drawing.Point(($oW - 96), 17)
$hMax.Add_MouseEnter({ $hMax.ForeColor = $cWhite })
$hMax.Add_MouseLeave({ $hMax.ForeColor = $oLav })
$hMax.Add_Click({ $form.ToggleMax() })

$hClose = New-Object Windows.Forms.Label
$hClose.Text = [string][char]0x2715
$hClose.Font = New-Object Drawing.Font('Segoe UI Symbol', 11)
$hClose.ForeColor = $oLav
$hClose.BackColor = [Drawing.Color]::Transparent
$hClose.Cursor = [Windows.Forms.Cursors]::Hand
$hClose.Size = New-Object Drawing.Size(32, 32)
$hClose.TextAlign = 'MiddleCenter'
$hClose.Location = New-Object Drawing.Point(($oW - 60), 17)
$hClose.Add_MouseEnter({ $hClose.ForeColor = $cWhite })
$hClose.Add_MouseLeave({ $hClose.ForeColor = $oLav })
$hClose.Add_Click({ $form.Close() })

$form.Controls.AddRange(@($hTitle, $hSub, $pill, $hMin, $hMax, $hClose))

# ---------- แถว A: LIVE STATISTICS (คลื่นขยับ) + LIVE ----------
$yA = 80
$stats = New-Object WaveCard
$stats.Cap = 'LIVE STATISTICS'
$stats.Size = New-Object Drawing.Size(642, 100)
$stats.Location = New-Object Drawing.Point($oPad, $yA)

$tAct = New-Object StatTile
$tAct.IconKind = 5; $tAct.Caption = 'ACTIVE'; $tAct.Value = '0'
$tAct.Size = New-Object Drawing.Size(190, 50)
$tAct.Location = New-Object Drawing.Point(18, 30)

$tCpu = New-Object StatTile
$tCpu.IconKind = 6; $tCpu.Caption = 'CPU'; $tCpu.Value = '0%'
$tCpu.Size = New-Object Drawing.Size(190, 50)
$tCpu.Location = New-Object Drawing.Point(222, 30)

$tPing = New-Object StatTile
$tPing.IconKind = 7; $tPing.Caption = 'PING'; $tPing.Value = '-'
$tPing.Accent = $oViolet
$tPing.Size = New-Object Drawing.Size(190, 50)
$tPing.Location = New-Object Drawing.Point(426, 30)
$stats.Controls.AddRange(@($tAct, $tCpu, $tPing))

$live = New-Object Glass
$live.Cap = 'LIVE'
$live.Size = New-Object Drawing.Size(346, 100)
$live.Location = New-Object Drawing.Point((20 + 642 + 12), $yA)

$liveVal = New-Object Windows.Forms.Label
$liveVal.Text = '- ms'
$liveVal.Font = New-Object Drawing.Font('ไอติม Bold', 12)
$liveVal.ForeColor = $cWhite
$liveVal.BackColor = [Drawing.Color]::Transparent
$liveVal.AutoSize = $false
$liveVal.TextAlign = 'MiddleRight'
$liveVal.Size = New-Object Drawing.Size(140, 24)
$liveVal.Location = New-Object Drawing.Point((346 - 18 - 140), 8)

$liveLn = New-Object LiveLine
$liveLn.Size = New-Object Drawing.Size(318, 52)
$liveLn.Location = New-Object Drawing.Point(14, 40)
$live.Controls.AddRange(@($liveVal, $liveLn))

$form.Controls.AddRange(@($stats, $live))

# ---------- แถว B/C: การ์ดฟีเจอร์ (คลิกที่การ์ด = เปิด/ปิดสวิตช์เดิม) ----------
$script:featMap = @{}
$fmeta = @{
    net  = @{ I = 0; B = 'NET' }
    web  = @{ I = 1; B = 'WEB' }
    game = @{ I = 2; B = 'GAME' }
    mem  = @{ I = 3; B = 'RAM' }
    fw   = @{ I = 4; B = 'FW' }
}
$yB = 194
$yC = 288
$cw3 = [int](($oCW - 28) / 3)
$pos = @{
    net  = @($oPad, $yB, $cw3)
    web  = @(($oPad + $cw3 + 14), $yB, $cw3)
    game = @(($oPad + 2 * ($cw3 + 14)), $yB, $cw3)
    mem  = @($oPad, $yC, $cw3)
    fw   = @(($oPad + $cw3 + 14), $yC, ($oCW - $cw3 - 14))
}
foreach ($it in $items) {
    $k = $it.Key
    $fc = New-Object FeatureCard
    $fc.Title = $it.Name
    $fc.Badge = $fmeta[$k].B
    $fc.IconKind = $fmeta[$k].I
    $fc.Tag = $k
    $fc.Size = New-Object Drawing.Size($pos[$k][2], 84)
    $fc.Location = New-Object Drawing.Point($pos[$k][0], $pos[$k][1])
    $fc.SetState($false, $false, [string]$descs[$k])
    $fc.Add_Click({
        param($sender, $e)
        $tg = $script:tgMap[[string]$sender.Tag]
        if ($tg -and $tg.Enabled) { $tg.Checked = -not $tg.Checked }
    })
    $script:featMap[$k] = $fc
    $form.Controls.Add($fc)
}

# ---------- แถว D: SYSTEM MONITOR + SPEED TEST ----------
$yD = 386
$nDrv = $drvCards.Count
$dRows = [int][Math]::Ceiling([Math]::Max(1, $nDrv) / 3.0)
if ($nDrv -eq 0) { $dRows = 0 }
$sysH = [Math]::Max(206, (112 + $dRows * 86 + 10))

$sys = New-Object Glass
$sys.Cap = 'SYSTEM MONITOR'
$sys.Size = New-Object Drawing.Size(642, $sysH)
$sys.Location = New-Object Drawing.Point($oPad, $yD)

$bxCpu = New-Object StatBox
$bxCpu.Caption = 'CPU'
$bxCpu.Size = New-Object Drawing.Size(170, 68)
$bxCpu.Location = New-Object Drawing.Point(20, 36)
$bxRam = New-Object StatBox
$bxRam.Caption = 'MEMORY'
$bxRam.ValColor = $oViolet
$bxRam.Size = New-Object Drawing.Size(170, 68)
$bxRam.Location = New-Object Drawing.Point(236, 36)
$bxGpu = New-Object StatBox
$bxGpu.Caption = 'GPU'
$bxGpu.Size = New-Object Drawing.Size(170, 68)
$bxGpu.Location = New-Object Drawing.Point(452, 36)

foreach ($ax in @(190, 406)) {
    $ar = New-Object Windows.Forms.Label
    $ar.Text = [string][char]0x2192
    $ar.Font = New-Object Drawing.Font('Segoe UI', 13)
    $ar.ForeColor = [Drawing.Color]::FromArgb(110, 100, 160)
    $ar.BackColor = [Drawing.Color]::Transparent
    $ar.TextAlign = 'MiddleCenter'
    $ar.Size = New-Object Drawing.Size(46, 68)
    $ar.Location = New-Object Drawing.Point($ax, 36)
    $sys.Controls.Add($ar)
}
$sys.Controls.AddRange(@($bxCpu, $bxRam, $bxGpu))

$speed = New-Object Glass
$speed.Cap = 'SPEED TEST'
$speed.Size = New-Object Drawing.Size(346, $sysH)
$speed.Location = New-Object Drawing.Point((20 + 642 + 12), $yD)

$form.Controls.AddRange(@($sys, $speed))

# --- ไดรฟ์: ใช้การ์ดเดิม ย้ายมาเรียงในช่อง SYSTEM MONITOR ---
$dkFill = [Drawing.Color]::FromArgb(15, 9, 33)
for ($i = 0; $i -lt $nDrv; $i++) {
    $dc = $drvCards[$i]
    $row = [int][Math]::Floor($i / 3)
    $col = $i % 3
    $dc.Fill = $dkFill
    foreach ($ch in $dc.Controls) { $ch.BackColor = $dkFill }
    $dc.Size = New-Object Drawing.Size(194, 78)
    $sys.Controls.Add($dc)
    $dc.Location = New-Object Drawing.Point((20 + $col * 204), (116 + $row * 86))
    $u = $script:drvUi[$i]
    $dc.Controls[0].Width = 104
    $u.Pct.Left = 194 - 14 - 50
    $u.Bar.Width = 194 - 36
    $u.Txt.Width = 194 - 36
    $dc.Visible = $true
    $dc.BringToFront()
}

# --- Speed Test: ย้ายตัวควบคุมเดิมมาไว้ในการ์ดใหม่ ---
$spGo.BackColor = [Drawing.Color]::Transparent
$spGo.Size = New-Object Drawing.Size(92, 92)
$spGo.Location = New-Object Drawing.Point(16, 38)
$speed.Controls.Add($spGo)

$capFont = New-Object Drawing.Font('Segoe UI', 7.2, [Drawing.FontStyle]::Bold)
$ry = 36
foreach ($row in @(
    @{ N = $lPingN; V = $vPing; S = $sPing; Y = 36 },
    @{ N = $lDownN; V = $vDown; S = $sDown; Y = 76 },
    @{ N = $lUpN;   V = $vUp;   S = $sUp;   Y = 116 }
)) {
    $row.N.Font = $capFont
    $row.N.ForeColor = [Drawing.Color]::FromArgb(120, 110, 165)
    $row.N.BackColor = [Drawing.Color]::Transparent
    $row.N.Size = New-Object Drawing.Size(150, 14)
    $row.N.Location = New-Object Drawing.Point(124, $row.Y)

    $row.V.Font = New-Object Drawing.Font('ไอติม Bold', 15)
    $row.V.BackColor = [Drawing.Color]::Transparent
    $row.V.TextAlign = 'MiddleLeft'
    $row.V.Size = New-Object Drawing.Size(76, 26)
    $row.V.Location = New-Object Drawing.Point(124, ($row.Y + 12))

    $row.S.Font = New-Object Drawing.Font('Segoe UI', 8.5)
    $row.S.BackColor = [Drawing.Color]::Transparent
    $row.S.TextAlign = 'MiddleLeft'
    $row.S.Size = New-Object Drawing.Size(130, 26)
    $row.S.Location = New-Object Drawing.Point(202, ($row.Y + 12))

    $speed.Controls.AddRange(@($row.N, $row.V, $row.S))
}
$lPingN.Text = 'PING'; $lDownN.Text = 'DOWNLOAD'; $lUpN.Text = 'UPLOAD'

foreach ($pr in @(
    @{ C = $lIsp;  X = 16;  Y = ($sysH - 52); W = 150; F = (New-Object Drawing.Font('ไอติม', 9.5)); Col = $cWhite },
    @{ C = $lIp;   X = 16;  Y = ($sysH - 32); W = 150; F = (New-Object Drawing.Font('Segoe UI', 8.5)); Col = $cOff },
    @{ C = $lSrv;  X = 176; Y = ($sysH - 52); W = 154; F = (New-Object Drawing.Font('ไอติม', 9.5)); Col = $cWhite },
    @{ C = $lSrvS; X = 176; Y = ($sysH - 32); W = 154; F = (New-Object Drawing.Font('Segoe UI', 8.5)); Col = $cOff }
)) {
    $pr.C.Font = $pr.F
    $pr.C.ForeColor = $pr.Col
    $pr.C.BackColor = [Drawing.Color]::Transparent
    $pr.C.Size = New-Object Drawing.Size($pr.W, 18)
    $pr.C.Location = New-Object Drawing.Point($pr.X, $pr.Y)
    $speed.Controls.Add($pr.C)
}
$spG.Visible = $false

# ---------- แถว E: แบนเนอร์เครื่องมือ (พื้นหลังดาว + ดาวเคราะห์) ----------
$yE = $yD + $sysH + 14
$ban = New-Object Glass
$ban.Art = $true
$ban.Cap = 'QUICK TOOLS'
$ban.CapX = 70
$ban.CapY = 14
$ban.F1 = [Drawing.Color]::FromArgb(235, 30, 16, 62)
$ban.F2 = [Drawing.Color]::FromArgb(235, 14, 8, 34)
$ban.Size = New-Object Drawing.Size($oCW, 64)
$ban.Location = New-Object Drawing.Point($oPad, $yE)

$bLogo = New-Object Logo
$bLogo.Size = New-Object Drawing.Size(40, 40)
$bLogo.Location = New-Object Drawing.Point(18, 12)
if ($script:logoBmp) { $bLogo.Img = $script:logoBmp }

$bSub = New-Object Windows.Forms.Label
$bSub.Text = 'ตัวช่วยจัดการเครื่อง'
$bSub.Font = New-Object Drawing.Font('Segoe UI', 8.5)
$bSub.ForeColor = $oLav
$bSub.BackColor = [Drawing.Color]::Transparent
$bSub.AutoSize = $true
$bSub.Location = New-Object Drawing.Point(70, 32)
$ban.Controls.AddRange(@($bLogo, $bSub))

$bx = 300
foreach ($b in @($wifiBtn, $cleanBtn, $secBtn)) {
    $b.Size = New-Object Drawing.Size(190, 38)
    $b.Location = New-Object Drawing.Point($bx, 13)
    $b.Visible = $true
    $ban.Controls.Add($b)
    $bx += 198
}
$form.Controls.Add($ban)

# ---------- แถว F: แถบสถานะด้านล่าง ----------
$yF = $yE + 64 + 14
$bar = New-Object Glass
$bar.Radius = 16
$bar.F1 = [Drawing.Color]::FromArgb(255, 34, 20, 66)
$bar.F2 = [Drawing.Color]::FromArgb(255, 32, 18, 62)
$bar.Size = New-Object Drawing.Size($oCW, 50)
$bar.Location = New-Object Drawing.Point($oPad, $yF)

$dot = New-Object Windows.Forms.Label
$dot.Text = [string][char]0x25CF
$dot.Font = New-Object Drawing.Font('Segoe UI', 8)
$dot.ForeColor = $oGreen
$dot.BackColor = [Drawing.Color]::Transparent
$dot.AutoSize = $true
$dot.Location = New-Object Drawing.Point(18, 16)

$summary.Parent = $bar
$summary.Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)
$summary.ForeColor = $oGreen
$summary.BackColor = [Drawing.Color]::Transparent
$summary.TextAlign = 'MiddleLeft'
$summary.Size = New-Object Drawing.Size(200, 22)
$summary.Location = New-Object Drawing.Point(36, 14)
$summary.Visible = $true

$btnGo = New-Object GradButton
$btnGo.Text = ([string][char]0x25B6 + '  Speed Test')
$btnGo.C1 = [Drawing.Color]::FromArgb(88, 50, 160)
$btnGo.C2 = [Drawing.Color]::FromArgb(40, 120, 92)
$btnGo.Size = New-Object Drawing.Size(150, 34)
$btnGo.Location = New-Object Drawing.Point(([int](($oCW - 300) / 2)), 8)
$btnGo.Add_Click({
    if ($script:eng.Running) { $script:eng.Cancel(); return }
    $vPing.Text = '-'
    $vDown.Text = '-'
    $vUp.Text = '-'
    $sPing.Text = 'ms | Jitter -'
    $script:eng.Start()
})

$btnStop = New-Object GradButton
$btnStop.Text = ([string][char]0x25A0 + '  ปิดทั้งหมด')
$btnStop.C1 = [Drawing.Color]::FromArgb(239, 68, 68)
$btnStop.C2 = [Drawing.Color]::FromArgb(244, 114, 150)
$btnStop.Size = New-Object Drawing.Size(138, 34)
$btnStop.Location = New-Object Drawing.Point(([int](($oCW - 300) / 2 + 162)), 8)
$btnStop.Add_Click({
    foreach ($k in @('net', 'web', 'game', 'mem', 'fw')) {
        $t = $script:tgMap[$k]
        if ($t -and $t.Checked -and $t.Enabled) { $t.Checked = $false }
    }
})

$remLbl2 = New-Object Windows.Forms.Label
$remLbl2.Text = 'จำการตั้งค่า'
$remLbl2.Font = New-Object Drawing.Font('ไอติม', 10)
$remLbl2.ForeColor = $cWhite
$remLbl2.BackColor = [Drawing.Color]::Transparent
$remLbl2.AutoSize = $false
$remLbl2.TextAlign = 'MiddleRight'
$remLbl2.Size = New-Object Drawing.Size(90, 26)
$remLbl2.Location = New-Object Drawing.Point(($oCW - 18 - 128 - 12 - 48 - 94), 12)

$remTg.BackColor = $oBarFill
$bar.Controls.Add($remTg)
$remTg.Location = New-Object Drawing.Point(($oCW - 18 - 128 - 12 - 48), 12)

$verLbl = New-Object Windows.Forms.Label
$verLbl.Text = 'v1.0 ' + [string][char]0x00B7 + ' Fam Bypass'
$verLbl.Font = New-Object Drawing.Font('Segoe UI', 8.5)
$verLbl.ForeColor = [Drawing.Color]::FromArgb(110, 100, 150)
$verLbl.BackColor = [Drawing.Color]::Transparent
$verLbl.AutoSize = $false
$verLbl.TextAlign = 'MiddleRight'
$verLbl.Size = New-Object Drawing.Size(128, 26)
$verLbl.Location = New-Object Drawing.Point(($oCW - 18 - 128), 12)

$bar.Controls.AddRange(@($dot, $btnGo, $btnStop, $remLbl2, $verLbl))
$form.Controls.Add($bar)

$oH = $yF + 50 + 18
$form.ClientSize = New-Object Drawing.Size($oW, $oH)

# ---------- ตัวอัปเดตค่าบนหน้าจอใหม่ ----------
$script:orionTick = 0
$script:orionTm = New-Object Windows.Forms.Timer
$script:orionTm.Interval = 400
$script:orionTm.Add_Tick({
    try {
        $m = $script:mon
        $n = 0
        $dotChar = ' ' + [string][char]0x00B7 + ' '
        foreach ($k in @('net', 'web', 'game', 'mem', 'fw')) {
            $tg = $script:tgMap[$k]
            if ($tg.Checked) { $n++ }
            $t = [string]$statusLabels[$k].Text
            $i = $t.IndexOf($dotChar)
            if ($i -ge 0) { $t = $t.Substring($i + 3) }
            $script:featMap[$k].SetState([bool]$tg.Checked, (-not $tg.Enabled), $t)
        }
        $tAct.Value = [string]$n
        $tCpu.Value = ([string]$m.Cpu + '%')
        $pill.On = ($n -gt 0)
        if ($n -gt 0) { $pill.Label = 'ACTIVE' } else { $pill.Label = 'READY' }
        $stats.Energy = [single]([Math]::Min(1.0, ($m.Cpu / 100.0) + 0.08 * $n))

        if ($m.PingSeen -and $m.PingOk) {
            $pt = ([string]$m.PingMs + ' ms')
            $tPing.Value = [string]$m.PingMs
            $liveVal.Text = $pt
            $liveLn.Push([single]$m.PingMs)
        } elseif ($m.PingSeen) {
            $tPing.Value = '-'
            $liveVal.Text = 'Timeout'
        }

        $bxCpu.Value = ([string]$m.Cpu + '%')
        $bxCpu.Sub = 'การใช้งานรวมทุก core'
        $bxRam.Value = ([string]$m.RamPct + '%')
        $bxRam.Sub = ('{0:N1} / {1:N1} GB' -f $m.RamUsed, $m.RamTotal)
        if (-not $m.GpuOk) { $bxGpu.Value = 'N/A'; $bxGpu.Sub = 'ไม่พบการ์ด NVIDIA' }
        elseif ($m.GpuText) { $bxGpu.Value = [string]$m.GpuText; $bxGpu.Sub = [string]$m.GpuSub }
        else { $bxGpu.Value = '-'; $bxGpu.Sub = 'กำลังอ่านค่า...' }
    } catch { }
})
$script:orionTm.Start()
$form.Add_FormClosed({ try { $script:orionTm.Stop(); $script:orionTm.Dispose() } catch { } })
# =====================================================================
#  SIDEBAR (แท็บบาร์แนวตั้งฝั่งซ้าย)
#  วางทั้งไฟล์นี้ใน FlowSkipper.bat "ก่อนบรรทัด  $tm.Start()"  (ท้ายสุดของไฟล์ ก่อน $spTm.Start())
#  หน้าหลักเดิมทั้งหมดยังอยู่ที่แท็บแรก (FROSTX) เหมือนเดิม แค่ขยับไปทางขวา
# =====================================================================
$cs4 = @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class SideNav : Control
{
    [DllImport("user32.dll")] static extern bool ReleaseCapture();
    [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, int m, IntPtr w, IntPtr l);

    public List<int> Icons = new List<int>();
    public List<string> Tips = new List<string>();
    public Image Logo;
    public bool Online = true;
    public event EventHandler SelectedChanged;

    int sel;
    int hot = -1;
    ToolTip tt = new ToolTip();

    const int TopY = 134;
    const int Step = 48;
    const int ItemW = 46;
    const int ItemH = 38;

    public SideNav()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer
            | ControlStyles.SupportsTransparentBackColor | ControlStyles.ResizeRedraw, true);
        BackColor = Color.Transparent;
        tt.InitialDelay = 250;
    }

    public int Selected
    {
        get { return sel; }
        set
        {
            if (sel == value) return;
            sel = value;
            Invalidate();
            if (SelectedChanged != null) SelectedChanged(this, EventArgs.Empty);
        }
    }

    static GraphicsPath Round(Rectangle r, int rad)
    {
        int d = Math.Max(1, Math.Min(rad * 2, Math.Min(r.Width, r.Height)));
        GraphicsPath p = new GraphicsPath();
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }

    Rectangle ItemRect(int i)
    {
        return new Rectangle((Width - ItemW) / 2, TopY + i * Step, ItemW, ItemH);
    }

    int HitTest(Point p)
    {
        for (int i = 0; i < Icons.Count; i++)
            if (ItemRect(i).Contains(p)) return i;
        return -1;
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        int h = HitTest(e.Location);
        if (h != hot)
        {
            hot = h;
            Cursor = h >= 0 ? Cursors.Hand : Cursors.Default;
            tt.SetToolTip(this, h >= 0 ? Tips[h] : "");
            Invalidate();
        }
        base.OnMouseMove(e);
    }

    protected override void OnMouseLeave(EventArgs e)
    {
        hot = -1;
        Invalidate();
        base.OnMouseLeave(e);
    }

    protected override void OnMouseDown(MouseEventArgs e)
    {
        if (e.Button == MouseButtons.Left)
        {
            int h = HitTest(e.Location);
            if (h >= 0) Selected = h;
            else
            {
                Form f = FindForm();
                if (f != null) { ReleaseCapture(); SendMessage(f.Handle, 0xA1, (IntPtr)2, IntPtr.Zero); }
            }
        }
        base.OnMouseDown(e);
    }

        static void DrawIcon(Graphics g, int k, Rectangle b, Color c)
    {
        float x = b.X, y = b.Y, w = b.Width, h = b.Height;
        using (Pen p = new Pen(c, 1.7f))
        using (SolidBrush sb = new SolidBrush(c))
        {
            p.StartCap = LineCap.Round;
            p.EndCap = LineCap.Round;
            p.LineJoin = LineJoin.Round;
            if (k == 0)
            {
                int s = (int)(w * 0.42f);
                Rectangle[] rs = {
                    new Rectangle(b.X, b.Y, s, s), new Rectangle(b.Right - s, b.Y, s, s),
                    new Rectangle(b.X, b.Bottom - s, s, s), new Rectangle(b.Right - s, b.Bottom - s, s, s)
                };
                foreach (Rectangle r in rs)
                    using (GraphicsPath gp = Round(r, 3)) g.DrawPath(p, gp);
            }
            else if (k == 1)
            {
                g.DrawEllipse(p, x, y, w, h);
                g.DrawLine(p, x + w * 0.5f, y + h * 0.5f, x + w * 0.5f, y + h * 0.22f);
                g.DrawLine(p, x + w * 0.5f, y + h * 0.5f, x + w * 0.74f, y + h * 0.62f);
            }
            else if (k == 2)
            {
                // ไอคอนเทอร์มินัล: กรอบ + เครื่องหมาย > + ขีดล่าง
                using (GraphicsPath gp = Round(new Rectangle((int)x, (int)(y + h * 0.1f), (int)w, (int)(h * 0.8f)), 4))
                    g.DrawPath(p, gp);
                g.DrawLine(p, x + w * 0.24f, y + h * 0.34f, x + w * 0.44f, y + h * 0.5f);
                g.DrawLine(p, x + w * 0.44f, y + h * 0.5f, x + w * 0.24f, y + h * 0.66f);
                g.DrawLine(p, x + w * 0.54f, y + h * 0.68f, x + w * 0.76f, y + h * 0.68f);
            }

                        else if (k == 4)   // ดาวน์โหลด (App Hub)
            {
                g.DrawLine(p, x + w * 0.5f, y + h * 0.08f, x + w * 0.5f, y + h * 0.66f);
                g.DrawLine(p, x + w * 0.26f, y + h * 0.44f, x + w * 0.5f, y + h * 0.68f);
                g.DrawLine(p, x + w * 0.74f, y + h * 0.44f, x + w * 0.5f, y + h * 0.68f);
                g.DrawLine(p, x + w * 0.14f, y + h * 0.92f, x + w * 0.86f, y + h * 0.92f);
            }
            else if (k == 6)   // สายฟ้า (Boots FPS)
            {
                PointF[] bolt = {
                    new PointF(x + w * 0.58f, y),
                    new PointF(x + w * 0.16f, y + h * 0.56f),
                    new PointF(x + w * 0.48f, y + h * 0.56f),
                    new PointF(x + w * 0.40f, y + h),
                    new PointF(x + w * 0.84f, y + h * 0.40f),
                    new PointF(x + w * 0.52f, y + h * 0.40f)
                };
                g.DrawPolygon(p, bolt);
            }
            else   // เป้ากลางจอ (Crosshair)
            {
                float cx = x + w * 0.5f, cy = y + h * 0.5f;
                g.DrawEllipse(p, x + w * 0.2f, y + h * 0.2f, w * 0.6f, h * 0.6f);
                g.DrawLine(p, cx, y, cx, y + h * 0.34f);
                g.DrawLine(p, cx, y + h * 0.66f, cx, y + h);
                g.DrawLine(p, x, cy, x + w * 0.34f, cy);
                g.DrawLine(p, x + w * 0.66f, cy, x + w, cy);
                g.FillEllipse(sb, cx - 1.5f, cy - 1.5f, 3f, 3f);
            }
                        
        }
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        if (Width < 20 || Height < 100) return;

        Color green = Color.FromArgb(74, 222, 128);
        Color violet = Color.FromArgb(192, 132, 252);
        Color muted = Color.FromArgb(150, 140, 190);

        // พื้นหลังแถบ + เส้นขอบขวา
        Rectangle full = new Rectangle(0, 0, Width, Height);
        using (LinearGradientBrush bg = new LinearGradientBrush(full, Color.FromArgb(215, 12, 7, 26), Color.FromArgb(215, 22, 10, 44), 90f))
            g.FillRectangle(bg, full);
        using (Pen edge = new Pen(Color.FromArgb(90, 140, 100, 225), 1f))
            g.DrawLine(edge, Width - 1, 0, Width - 1, Height);

        // ป้ายสถานะ (จุดเขียว)
        Rectangle pr = new Rectangle((Width - 44) / 2, 22, 44, 22);
        Color pc = Online ? green : Color.FromArgb(176, 150, 240);
        using (GraphicsPath pp = Round(pr, 11))
        {
            using (SolidBrush pb = new SolidBrush(Online ? Color.FromArgb(200, 14, 52, 36) : Color.FromArgb(200, 40, 26, 78)))
                g.FillPath(pb, pp);
            using (Pen ppn = new Pen(Color.FromArgb(150, pc), 1.2f))
                g.DrawPath(ppn, pp);
        }
        float cx = Width / 2f;
        using (SolidBrush gl = new SolidBrush(Color.FromArgb(55, pc)))
            g.FillEllipse(gl, cx - 8f, 25f, 16f, 16f);
        using (SolidBrush db = new SolidBrush(pc))
            g.FillEllipse(db, cx - 3.5f, 29.5f, 7f, 7f);

        // กรอบโลโก้
        Rectangle lr = new Rectangle((Width - 48) / 2, 60, 48, 54);
        using (GraphicsPath lp = Round(lr, 14))
        {
            using (SolidBrush lf = new SolidBrush(Color.FromArgb(220, 28, 16, 58)))
                g.FillPath(lf, lp);
            using (LinearGradientBrush lb = new LinearGradientBrush(lr, Color.FromArgb(220, 168, 120, 255), Color.FromArgb(160, 86, 160, 140), 60f))
            using (Pen lpn = new Pen(lb, 1.4f))
                g.DrawPath(lpn, lp);
        }
        if (Logo != null)
        {
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.DrawImage(Logo, new Rectangle(lr.X + 7, lr.Y + 10, 34, 34));
        }
        else
        {
            PointF[] tri = { new PointF(cx, 70f), new PointF(cx + 12f, 102f), new PointF(cx, 94f), new PointF(cx - 12f, 102f) };
            using (Pen tp = new Pen(violet, 1.8f))
            {
                tp.LineJoin = LineJoin.Round;
                g.DrawPolygon(tp, tri);
            }
        }

        // ไอคอนแท็บ
        for (int i = 0; i < Icons.Count; i++)
        {
            Rectangle r = ItemRect(i);
            bool s = (i == sel);
            bool h = (i == hot);
            Color ic = muted;

            using (GraphicsPath tp = Round(r, 11))
            {
                if (s)
                {
                    using (Pen glow = new Pen(Color.FromArgb(40, green), 5f))
                        g.DrawPath(glow, tp);
                    using (SolidBrush sf = new SolidBrush(Color.FromArgb(205, 14, 50, 36)))
                        g.FillPath(sf, tp);
                    using (Pen sp = new Pen(Color.FromArgb(200, green), 1.4f))
                        g.DrawPath(sp, tp);
                    ic = green;
                }
                else if (h)
                {
                    using (SolidBrush hf = new SolidBrush(Color.FromArgb(90, 90, 60, 160)))
                        g.FillPath(hf, tp);
                    ic = violet;
                }
            }
            DrawIcon(g, Icons[i], new Rectangle(r.X + (ItemW - 22) / 2, r.Y + (ItemH - 22) / 2, 22, 22), ic);
        }
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) tt.Dispose();
        base.Dispose(disposing);
    }
}
'@
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition $cs4 -Language CSharp -ErrorAction Stop

$navW = 76

# ---------- รายการแท็บ (เพิ่มแท็บใหม่ได้โดยเติมบรรทัดในนี้) ----------
# Icon: 0 = grid, 1 = นาฬิกา, 2 = เทอร์มินัล, 3 = เอกสาร
$navTabs = @(
    @{ Icon = 0; Tip = 'FROSTX';                       Title = 'FROSTX';        Sub = 'Overview & quick controls';        Cap = '' },
    @{ Icon = 1; Tip = 'ประวัติการใช้งานคอมพิวเตอร์';       Title = 'Activity History'; Sub = 'ประวัติการใช้งานคอมพิวเตอร์';          Cap = 'ACTIVITY HISTORY' },
    @{ Icon = 2; Tip = 'ประวัติคำสั่ง CMD / PowerShell';    Title = 'Command History';  Sub = 'ตรวจดูคำสั่งที่เคยรันใน CMD / PowerShell'; Cap = 'COMMAND HISTORY' },
    @{ Icon = 4; Tip = 'คลังแอป (App Hub)';               Title = 'App Hub';          Sub = 'ดาวน์โหลดแอปที่คุณเพิ่มเอง';            Cap = 'APP HUB' }
    @{ Icon = 5; Tip = 'เป้ากลางจอ (Crosshair)'; Title = 'Crosshair'; Sub = 'เป้ากลางจอ ปรับสี ความหนา ขนาดได้'; Cap = 'CROSSHAIR' }
    @{ Icon = 6; Tip = 'Boots FPS (โหมดเล่นเกม)'; Title = 'Boots FPS'; Sub = 'ปิดตัวที่ไม่จำเป็นตอนเล่นเกม แล้วคืนค่าให้ตอนเลิกเล่น'; Cap = 'BOOTS FPS' }
)

# ---------- แยกตัวควบคุมของ "หน้าหลัก" ออกมา (ตัวที่ซ่อนไว้ตั้งแต่ต้นไม่นับ) ----------
$hdrCtrls  = @($hTitle, $hSub, $pill, $hMin, $hMax, $hClose)
$dashCtrls = @($form.Controls | Where-Object { ($oldTop -notcontains $_) -and ($hdrCtrls -notcontains $_) })

# เลื่อนทุกอย่างไปทางขวาเพื่อเว้นที่ให้แถบด้านซ้าย
foreach ($c in ($dashCtrls + $hdrCtrls)) { $c.Left = $c.Left + $navW }
$form.ClientSize = New-Object Drawing.Size(($oW + $navW), $oH)

# ---------- แถบด้านซ้าย ----------
$nav = New-Object SideNav
$nav.Size = New-Object Drawing.Size($navW, $oH)
$nav.Location = New-Object Drawing.Point(0, 0)
if ($script:logoBmp) { $nav.Logo = $script:logoBmp }
foreach ($t in $navTabs) {
    $nav.Icons.Add([int]$t.Icon)
    $nav.Tips.Add([string]$t.Tip)
}
$form.Controls.Add($nav)

# ---------- หน้าเปล่าของแท็บอื่น (เตรียมไว้ใส่ฟังก์ชันทีหลัง) ----------
$script:pages = @{}
$script:pages[0] = $dashCtrls
for ($i = 1; $i -lt $navTabs.Count; $i++) {
    $pg = New-Object Glass
    $pg.Cap = [string]$navTabs[$i].Cap
    $pg.Size = New-Object Drawing.Size($oCW, ($oH - 80 - 20))
    $pg.Location = New-Object Drawing.Point(($oPad + $navW), 80)
    $pg.Visible = $false

    $ph = New-Object Windows.Forms.Label
    $ph.Text = 'หน้านี้ยังว่างอยู่ - เดี๋ยวค่อยเพิ่มฟังก์ชันทีหลัง'
    $ph.Font = New-Object Drawing.Font('ไอติม', 12)
    $ph.ForeColor = $oLav
    $ph.BackColor = [Drawing.Color]::Transparent
    $ph.Dock = 'Fill'
    $ph.TextAlign = 'MiddleCenter'
    $pg.Controls.Add($ph)

    $form.Controls.Add($pg)
    $script:pages[$i] = @($pg)
}

function Switch-Page([int]$i) {
    foreach ($k in @($script:pages.Keys)) {
        $v = ($k -eq $i)
        foreach ($c in $script:pages[$k]) { $c.Visible = $v }
    }
    $hTitle.Text = [string]$navTabs[$i].Title
    $hSub.Text = [string]$navTabs[$i].Sub
}
$nav.Add_SelectedChanged({ param($s, $e) Switch-Page ([int]$s.Selected) })
Switch-Page 0

# จุดสถานะบนแถบ: เขียว = มีฟีเจอร์เปิดอยู่ / ม่วง = พร้อมใช้งาน
$script:navTm = New-Object Windows.Forms.Timer
$script:navTm.Interval = 500
$script:navTm.Add_Tick({
    try {
        $v = [bool]$pill.On
        if ($nav.Online -ne $v) { $nav.Online = $v; $nav.Invalidate() }
    } catch { }
})
$script:navTm.Start()
$form.Add_FormClosed({ try { $script:navTm.Stop(); $script:navTm.Dispose() } catch { } })
# ---------------------------------------------------------------------
$actCode = @'
[Threading.Thread]::CurrentThread.Priority = 'BelowNormal'
$rows = New-Object System.Collections.Generic.List[object]
$start = (Get-Date).AddDays(-[double]$days)
$ms = [long]([double]$days * 86400000)
 
function Add-Row($t, [string]$type, [string]$detail, [string]$src, [int]$ord = 0) {
    $rows.Add([pscustomobject]@{ T = $t; Type = $type; Detail = $detail; Src = $src; Ord = $ord })
}
function Get-Ev([hashtable]$h, [int]$max) {
    try { @(Get-WinEvent -FilterHashtable $h -MaxEvents $max -ErrorAction Stop) } catch { @() }
}
function Get-EvX([string]$log, [string]$xp, [int]$max) {
    try { @(Get-WinEvent -LogName $log -FilterXPath $xp -MaxEvents $max -ErrorAction Stop) } catch { @() }
}
function Rot13([string]$s) {
    $sb = New-Object Text.StringBuilder
    foreach ($ch in $s.ToCharArray()) {
        $c = [int]$ch
        if ($c -ge 65 -and $c -le 90) { $c = (($c - 65 + 13) % 26) + 65 }
        elseif ($c -ge 97 -and $c -le 122) { $c = (($c - 97 + 13) % 26) + 97 }
        [void]$sb.Append([char]$c)
    }
    return $sb.ToString()
}
 
try {
    # ---- 1) เปิด/ปิดเครื่อง ----
    foreach ($e in (Get-Ev @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-General'; Id = 12, 13; StartTime = $start } 500)) {
        if ($e.Id -eq 12) { Add-Row $e.TimeCreated 'เปิด/ปิดเครื่อง' 'เปิดเครื่อง (Windows เริ่มทำงาน)' 'Kernel-General 12' }
        else { Add-Row $e.TimeCreated 'เปิด/ปิดเครื่อง' 'ปิดเครื่อง' 'Kernel-General 13' }
    }
    foreach ($e in (Get-Ev @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 41; StartTime = $start } 100)) {
        Add-Row $e.TimeCreated 'เปิด/ปิดเครื่อง' 'ปิดเครื่องไม่ปกติ (ไฟดับ / เครื่องค้าง / ถอดปลั๊ก)' 'Kernel-Power 41'
    }
    foreach ($e in (Get-Ev @{ LogName = 'System'; ProviderName = 'User32'; Id = 1074; StartTime = $start } 200)) {
        $p = $e.Properties
        $d = 'สั่งปิด/รีสตาร์ท'
        try { $d += ': ' + [string]$p[4].Value + ' โดย ' + [string]$p[0].Value + ' (' + [string]$p[6].Value + ')' } catch { }
        Add-Row $e.TimeCreated 'เปิด/ปิดเครื่อง' $d 'User32 1074'
    }
 
    # ---- 2) Sleep / Wake ----
    foreach ($e in (Get-Ev @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Kernel-Power'; Id = 42; StartTime = $start } 300)) {
        Add-Row $e.TimeCreated 'Sleep/Wake' 'เข้าสู่โหมด Sleep' 'Kernel-Power 42'
    }
    foreach ($e in (Get-Ev @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Power-Troubleshooter'; Id = 1; StartTime = $start } 300)) {
        Add-Row $e.TimeCreated 'Sleep/Wake' 'ตื่นจากโหมด Sleep' 'Power-Troubleshooter 1'
    }
 
    # ---- 3) ล็อกอิน ----
    $xp = "*[System[(EventID=4624) and TimeCreated[timediff(@SystemTime) <= $ms]]] and *[EventData[Data[@Name='LogonType']='2' or Data[@Name='LogonType']='7' or Data[@Name='LogonType']='10' or Data[@Name='LogonType']='11']]"
    $lt = @{ '2' = 'ล็อกอินหน้าเครื่อง'; '7' = 'ปลดล็อกหน้าจอ'; '10' = 'Remote Desktop'; '11' = 'ล็อกอิน (cached)' }
    foreach ($e in (Get-EvX 'Security' $xp 500)) {
        $p = $e.Properties
        if ($p.Count -lt 9) { continue }
        $user = [string]$p[5].Value
        if ($user -match '^(DWM-|UMFD-|SYSTEM$|LOCAL SERVICE|NETWORK SERVICE)') { continue }
        $ty = [string]$p[8].Value
        $d = $lt[$ty]
        if (-not $d) { $d = 'ล็อกอิน' }
        Add-Row $e.TimeCreated 'ล็อกอิน' ($d + ' - ' + [string]$p[6].Value + '\' + $user + ' (type ' + $ty + ')') 'Security 4624'
    }
 
    # ---- 4) ตรวจว่ามีการล้าง Event Log หรือไม่ ----
    foreach ($e in (Get-Ev @{ LogName = 'Security'; ProviderName = 'Microsoft-Windows-Eventlog'; Id = 1102; StartTime = $start } 50)) {
        Add-Row $e.TimeCreated 'ล้าง Event Log' 'มีการล้าง Security log' 'Security 1102'
    }
    foreach ($e in (Get-Ev @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Eventlog'; Id = 104; StartTime = $start } 50)) {
        $m = ''
        try { $m = (([string]$e.Message) -split '\r?\n')[0].Trim() } catch { }
        Add-Row $e.TimeCreated 'ล้าง Event Log' ('มีการล้าง Event Log  ' + $m) 'System 104'
    }
 
    # ---- 5) โปรแกรมที่เปิด: Prefetch ----
    $pfDir = Join-Path $env:SystemRoot 'Prefetch'
    $pfCount = 0
    foreach ($f in @(Get-ChildItem -LiteralPath $pfDir -Filter '*.pf' -File -Force -ErrorAction SilentlyContinue)) {
        $pfCount++
        if ($f.LastWriteTime -lt $start) { continue }
        $nm = $f.Name -replace '-[0-9A-Fa-f]{8}\.pf$', ''
        Add-Row $f.LastWriteTime 'โปรแกรมที่เปิด' ($nm + '   (เปิดครั้งแรก: ' + $f.CreationTime.ToString('yyyy-MM-dd HH:mm') + ')') 'Prefetch'
    }
    if ($pfCount -eq 0) { Add-Row (Get-Date) 'ข้อมูล' 'ไม่พบไฟล์ Prefetch (ระบบอาจปิดฟีเจอร์ Prefetch / บริการ SysMain)' 'Prefetch' }
 
    # ---- 6) โปรแกรมที่เปิด: UserAssist (ของผู้ใช้ที่รันโปรแกรมนี้) ----
    try {
        $uaRoot = Get-Item -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\UserAssist' -ErrorAction Stop
        foreach ($gk in $uaRoot.GetSubKeyNames()) {
            $ck = $uaRoot.OpenSubKey($gk + '\Count')
            if (-not $ck) { continue }
            foreach ($vn in $ck.GetValueNames()) {
                try {
                    $d = $ck.GetValue($vn)
                    if ($d -isnot [byte[]] -or $d.Length -lt 68) { continue }
                    $ft = [BitConverter]::ToInt64($d, 60)
                    if ($ft -le 0) { continue }
                    $when = [DateTime]::FromFileTimeUtc($ft).ToLocalTime()
                    if ($when -lt $start) { continue }
                    $nm = Rot13 $vn
                    if ($nm -like 'UEME_*') { continue }
                    $cnt = [BitConverter]::ToInt32($d, 4)
                    Add-Row $when 'โปรแกรมที่เปิด' ($nm + '   (เปิดแล้ว ' + $cnt + ' ครั้ง)') 'UserAssist'
                } catch { }
            }
        }
    } catch { }
 
    # ---- 7) ไฟล์ที่เปิดล่าสุด ----
    $rc = [Environment]::GetFolderPath('Recent')
    $sh = $null
    try { $sh = New-Object -ComObject WScript.Shell } catch { }
    $lnks = @(Get-ChildItem -LiteralPath $rc -Filter '*.lnk' -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $start } | Sort-Object LastWriteTime -Descending | Select-Object -First 600)
    foreach ($f in $lnks) {
        $tg = ''
        if ($sh) { try { $tg = [string]$sh.CreateShortcut($f.FullName).TargetPath } catch { } }
        if (-not $tg) { $tg = $f.BaseName }
        Add-Row $f.LastWriteTime 'ไฟล์ที่เปิด' $tg 'Recent'
    }
} catch { 'ERR:' + $_.Exception.Message }
 
$rows | Sort-Object @{ Expression = { if ($_.T -is [datetime]) { $_.T } else { [datetime]::MinValue } }; Descending = $true }, @{ Expression = { $_.Ord }; Descending = $false } | Select-Object -First 8000
'@
 
$cmdCode = @'
[Threading.Thread]::CurrentThread.Priority = 'BelowNormal'
$rows = New-Object System.Collections.Generic.List[object]
$start = (Get-Date).AddDays(-[double]$days)
$ms = [long]([double]$days * 86400000)
 
function Add-Row($t, [string]$type, [string]$detail, [string]$src, [int]$ord = 0) {
    $rows.Add([pscustomobject]@{ T = $t; Type = $type; Detail = $detail; Src = $src; Ord = $ord })
}
function Get-Ev([hashtable]$h, [int]$max) {
    try { @(Get-WinEvent -FilterHashtable $h -MaxEvents $max -ErrorAction Stop) } catch { @() }
}
function Get-EvX([string]$log, [string]$xp, [int]$max) {
    try { @(Get-WinEvent -LogName $log -FilterXPath $xp -MaxEvents $max -ErrorAction Stop) } catch { @() }
}
function Clip([string]$s, [int]$n) {
    $s = ($s -replace '\s+', ' ').Trim()
    if ($s.Length -gt $n) { return $s.Substring(0, $n) + ' ...' }
    return $s
}
 
try {
    # ---- 1) ประวัติที่พิมพ์ใน PowerShell (PSReadLine) ของทุกผู้ใช้ในเครื่อง ----
    $usersDir = Join-Path $env:SystemDrive 'Users'
    $fileCount = 0
    foreach ($u in @(Get-ChildItem -LiteralPath $usersDir -Directory -Force -ErrorAction SilentlyContinue)) {
        $dir = Join-Path $u.FullName 'AppData\Roaming\Microsoft\Windows\PowerShell\PSReadLine'
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter '*_history.txt' -File -Force -ErrorAction SilentlyContinue)) {
            $fileCount++
            $lines = @()
            try {
                $fs = New-Object IO.FileStream($f.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
                $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)
                try { $lines = @($sr.ReadToEnd() -split '\r?\n') } finally { $sr.Dispose(); $fs.Dispose() }
            } catch { }
            $n = $lines.Count
            for ($i = 0; $i -lt $n; $i++) {
                $ln = [string]$lines[$i]
                if (-not $ln.Trim()) { continue }
                $src = $u.Name + ' | ' + $f.Name + ' | บรรทัด ' + ($i + 1) + ' | ไฟล์แก้ไขล่าสุด ' + $f.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
                Add-Row $null 'PS History' (Clip $ln 800) $src (-($i + 1))
            }
        }
    }
    if ($fileCount -eq 0) { Add-Row (Get-Date) 'ข้อมูล' 'ไม่พบไฟล์ประวัติ PowerShell (ยังไม่เคยพิมพ์คำสั่งในคอนโซล หรือถูกลบไปแล้ว)' 'PSReadLine' }
 
    # ---- 2) PowerShell Script Block Log (Event 4104) ----
    $sbCount = 0
    foreach ($e in (Get-Ev @{ LogName = 'Microsoft-Windows-PowerShell/Operational'; Id = 4104; StartTime = $start } 1500)) {
        $sbCount++
        $p = $e.Properties
        $txt = ''
        $path = ''
        try { $txt = [string]$p[2].Value; $path = [string]$p[4].Value } catch { }
        $c = Clip $txt 700
        if (-not $c) { continue }
        if ($c -match '^(\$global:\?|prompt\b|PSConsoleHostReadLine|\$global:LASTEXITCODE)') { continue }
        $src = 'Operational 4104'
        if ($path) { $src += ' | ' + $path }
        Add-Row $e.TimeCreated 'PS ScriptBlock' $c $src
    }
    if ($sbCount -eq 0) { Add-Row (Get-Date) 'ข้อมูล' 'ไม่พบ PowerShell Script Block log (4104): ยังไม่ได้เปิดการบันทึก หรือไม่มีเหตุการณ์ในช่วงเวลานี้' 'Event Log' }
 
    # ---- 3) Process Creation (Event 4688): เห็นคำสั่งที่รันผ่าน CMD / PowerShell ----
    $xp = "*[System[(EventID=4688) and TimeCreated[timediff(@SystemTime) <= $ms]]]"
    $pe = @(Get-EvX 'Security' $xp 6000)
    $withCl = 0
    $shell = '(?i)\\(cmd|powershell|powershell_ise|pwsh)\.exe$'
    foreach ($e in $pe) {
        $p = $e.Properties
        if ($p.Count -lt 14) { continue }
        $img = [string]$p[5].Value
        $cl = [string]$p[8].Value
        $par = [string]$p[13].Value
        if ($cl) { $withCl++ }
        if (-not ($img -match $shell -or $par -match $shell)) { continue }
        $detail = $cl
        if (-not $detail) { $detail = $img + '   (ไม่มี command line)' }
        $pn = ''
        if ($par) { $pn = Split-Path -Leaf $par }
        Add-Row $e.TimeCreated 'Process Log' (Clip $detail 800) ([string]$p[1].Value + ' | parent: ' + $pn + ' | Security 4688')
    }
    if ($pe.Count -eq 0) {
        Add-Row (Get-Date) 'ข้อมูล' 'ไม่พบ Event 4688: ยังไม่ได้เปิด Audit Process Creation (กดปุ่ม "เปิดบันทึกคำสั่ง" เพื่อให้มีประวัติตั้งแต่ตอนนี้)' 'Security'
    } elseif ($withCl -eq 0) {
        Add-Row (Get-Date) 'ข้อมูล' 'พบ Event 4688 แต่ไม่มี command line (กดปุ่ม "เปิดบันทึกคำสั่ง" เพื่อให้บันทึก command line)' 'Security'
    }
 
    # ---- 4) คำสั่งที่พิมพ์ในช่อง Run (Win+R) ----
    try {
        $item = Get-Item -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\RunMRU' -ErrorAction Stop
        $order = [string]$item.GetValue('MRUList')
        for ($i = 0; $i -lt $order.Length; $i++) {
            $v = [string]$item.GetValue([string]$order[$i])
            if (-not $v) { continue }
            $v = $v -replace '\\1$', ''
            Add-Row $null 'Win+R' $v ('RunMRU | ล่าสุดอันดับ ' + ($i + 1)) ($i + 1)
        }
    } catch { }
 
    # ---- 5) เครื่องมือ command-line ที่เคยถูกเปิด (Prefetch) ----
    $cli = @('CMD.EXE', 'POWERSHELL.EXE', 'POWERSHELL_ISE.EXE', 'PWSH.EXE', 'WT.EXE', 'IPCONFIG.EXE', 'NETSH.EXE', 'NET.EXE', 'NET1.EXE',
        'PING.EXE', 'TRACERT.EXE', 'NSLOOKUP.EXE', 'NETSTAT.EXE', 'ARP.EXE', 'ROUTE.EXE', 'TASKLIST.EXE', 'TASKKILL.EXE', 'SC.EXE', 'REG.EXE',
        'SCHTASKS.EXE', 'WMIC.EXE', 'CERTUTIL.EXE', 'BITSADMIN.EXE', 'CURL.EXE', 'ROBOCOPY.EXE', 'ATTRIB.EXE', 'TAKEOWN.EXE', 'ICACLS.EXE',
        'CIPHER.EXE', 'FSUTIL.EXE', 'VSSADMIN.EXE', 'WEVTUTIL.EXE', 'BCDEDIT.EXE', 'DISKPART.EXE', 'SHUTDOWN.EXE', 'SFC.EXE', 'DISM.EXE',
        'AUDITPOL.EXE', 'MSHTA.EXE', 'WSCRIPT.EXE', 'CSCRIPT.EXE', 'RUNDLL32.EXE', 'REGSVR32.EXE', 'PSEXEC.EXE')
    $pfDir = Join-Path $env:SystemRoot 'Prefetch'
    foreach ($f in @(Get-ChildItem -LiteralPath $pfDir -Filter '*.pf' -File -Force -ErrorAction SilentlyContinue)) {
        if ($f.LastWriteTime -lt $start) { continue }
        $nm = ($f.Name -replace '-[0-9A-Fa-f]{8}\.pf$', '').ToUpper()
        if ($cli -notcontains $nm) { continue }
        Add-Row $f.LastWriteTime 'Prefetch (CLI)' ($nm + '   (เปิดครั้งแรก: ' + $f.CreationTime.ToString('yyyy-MM-dd HH:mm') + ')') 'Prefetch'
    }
} catch { 'ERR:' + $_.Exception.Message }
 
$rows | Sort-Object @{ Expression = { if ($_.T -is [datetime]) { $_.T } else { [datetime]::MinValue } }; Descending = $true }, @{ Expression = { $_.Ord }; Descending = $false } | Select-Object -First 8000
'@
 
# ---------------------------------------------------------------------
#  ตัวช่วยสร้างหน้า (ตาราง + ตัวกรอง + ค้นหา + คัดลอก + บันทึก CSV)
# ---------------------------------------------------------------------
$script:histUi = @{}
$hcDark = [Drawing.Color]::FromArgb(22, 17, 38)
$hcHead = [Drawing.Color]::FromArgb(40, 26, 78)
 
function Esc-Like([string]$s) {
    return $s.Replace("'", "''").Replace('[', '[[]').Replace('*', '[*]').Replace('%', '[%]')
}
 
function Apply-Filter($ui) {
    if ($null -eq $ui) { return }
    $parts = New-Object System.Collections.ArrayList
    $c = [string]$ui.Cat.SelectedItem
    if ($c -and $c -ne 'ทั้งหมด') { [void]$parts.Add("[Type] = '" + $c.Replace("'", "''") + "'") }
    $q = $ui.Search.Text.Trim()
    if ($q) {
        $x = Esc-Like $q
        [void]$parts.Add("([Detail] LIKE '%" + $x + "%' OR [Src] LIKE '%" + $x + "%' OR [Type] LIKE '%" + $x + "%')")
    }
    try { $ui.Dt.DefaultView.RowFilter = ($parts -join ' AND ') } catch { }
    $ui.Status.Text = ('แสดง ' + $ui.Dt.DefaultView.Count + ' / ' + $ui.Dt.Rows.Count + ' รายการ' + $ui.Info)
}
 
function Fill-Table($ui, $rows) {
    $dt = $ui.Dt
    $dt.DefaultView.RowFilter = ''
    $dt.BeginLoadData()
    $dt.Clear()
    $types = @{}
    foreach ($r in $rows) {
        $ts = '-'
        if ($r.T -is [datetime]) { $ts = $r.T.ToString('yyyy-MM-dd HH:mm:ss') }
        [void]$dt.Rows.Add($ts, [string]$r.Type, [string]$r.Detail, [string]$r.Src)
        $types[[string]$r.Type] = 1
    }
    $dt.EndLoadData()
 
    $ui.Cat.Items.Clear()
    [void]$ui.Cat.Items.Add('ทั้งหมด')
    foreach ($t in ($types.Keys | Sort-Object)) { [void]$ui.Cat.Items.Add([string]$t) }
    $ui.Cat.SelectedIndex = 0
    Apply-Filter $ui
}
 
$script:histDone = {
    param($out, $ctx)
    $ui = $script:histUi[[string]$ctx.Key]
    $ui.Busy = $false
    if ($ui.Page.IsDisposed) { return }
    $ui.Scan.Enabled = $true
    $ui.Scan.Text = 'สแกน'
    $rows = @($out | Where-Object { $_ -and $_.PSObject.Properties['Detail'] })
    $errs = @($out | Where-Object { $_ -is [string] })
    $ui.Info = '   ·   สแกนเมื่อ ' + (Get-Date).ToString('HH:mm:ss')
    if ($errs.Count -gt 0) { $ui.Info += '   ·   มีข้อผิดพลาด: ' + [string]$errs[0] }
    Fill-Table $ui $rows
}
 
function Start-HistScan([string]$key) {
    $ui = $script:histUi[$key]
    if ($null -eq $ui -or $ui.Busy) { return }
    $ui.Busy = $true
    $ui.Scan.Enabled = $false
    $ui.Scan.Text = 'กำลังสแกน...'
    $ui.Status.Text = 'กำลังอ่านข้อมูล... (หน้าต่างไม่ค้าง รอสักครู่)'
    $d = 30
    try { $d = [int](([string]$ui.Days.SelectedItem) -replace '\D', '') } catch { }
    Start-Bg $ui.Code @{ days = $d } $script:histDone @{ Key = $key }
}
 
function Export-HistCsv($ui) {
    $sfd = New-Object Windows.Forms.SaveFileDialog
    $sfd.Filter = 'CSV (*.csv)|*.csv'
    $sfd.FileName = ($ui.Key + '_' + (Get-Date).ToString('yyyyMMdd_HHmm') + '.csv')
    if ($sfd.ShowDialog() -ne 'OK') { return }
    try {
        $out = foreach ($v in $ui.Dt.DefaultView) {
            [pscustomobject]@{ Time = $v['Time']; Type = $v['Type']; Detail = $v['Detail']; Source = $v['Src'] }
        }
        @($out) | Export-Csv -LiteralPath $sfd.FileName -NoTypeInformation -Encoding UTF8
        $ui.Status.Text = 'บันทึกแล้ว: ' + $sfd.FileName
    } catch {
        [Windows.Forms.MessageBox]::Show(('บันทึกไม่สำเร็จ: ' + $_.Exception.Message), 'Export CSV') | Out-Null
    }
}
 
function Copy-HistRows($ui) {
    $sb = New-Object Text.StringBuilder
    foreach ($v in $ui.Dt.DefaultView) {
        [void]$sb.AppendLine(([string]$v['Time'] + "`t" + [string]$v['Type'] + "`t" + [string]$v['Detail'] + "`t" + [string]$v['Src']))
    }
    if ($sb.Length -gt 0) {
        try { [Windows.Forms.Clipboard]::SetText($sb.ToString()); $ui.Status.Text = 'คัดลอกรายการที่แสดงอยู่แล้ว' } catch { }
    }
}
 
function Enable-CmdLogging {
    $msg = "จะเปิดการบันทึก 2 อย่าง เพื่อให้มีประวัติคำสั่งตั้งแต่ตอนนี้เป็นต้นไป:`n`n" +
           "• Audit Process Creation + บันทึก Command line (Event 4688)`n" +
           "• PowerShell Script Block Logging (Event 4104)`n`n" +
           "การบันทึกเริ่มหลังเปิดเท่านั้น (ย้อนหลังไม่ได้) และ Event Log จะโตขึ้นเล็กน้อย`n`nดำเนินการต่อ?"
    if ([Windows.Forms.MessageBox]::Show($msg, 'เปิดบันทึกคำสั่ง', 'YesNo', 'Question') -ne 'Yes') { return }
    $log = New-Object System.Collections.ArrayList
    try {
        $arg = '/subcategory:{0CCE922B-69AE-11D9-BED3-505054503030}'
        $o = & auditpol.exe /set $arg /success:enable 2>&1
        if ($LASTEXITCODE -eq 0) { [void]$log.Add('เปิด Audit Process Creation แล้ว') }
        else { [void]$log.Add('เปิด Audit Process Creation ไม่สำเร็จ: ' + (($o | Out-String).Trim())) }
    } catch { [void]$log.Add('Audit Process Creation ผิดพลาด: ' + $_.Exception.Message) }
    try {
        $k1 = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit'
        if (-not (Test-Path -LiteralPath $k1)) { [void](New-Item -Path $k1 -Force) }
        [void](New-ItemProperty -LiteralPath $k1 -Name 'ProcessCreationIncludeCmdLine_Enabled' -Value 1 -PropertyType DWord -Force)
        [void]$log.Add('เปิดการบันทึก Command line แล้ว')
    } catch { [void]$log.Add('เปิด Command line ไม่สำเร็จ: ' + $_.Exception.Message) }
    try {
        $k2 = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'
        if (-not (Test-Path -LiteralPath $k2)) { [void](New-Item -Path $k2 -Force) }
        [void](New-ItemProperty -LiteralPath $k2 -Name 'EnableScriptBlockLogging' -Value 1 -PropertyType DWord -Force)
        [void]$log.Add('เปิด PowerShell Script Block Logging แล้ว')
    } catch { [void]$log.Add('เปิด Script Block Logging ไม่สำเร็จ: ' + $_.Exception.Message) }
    [Windows.Forms.MessageBox]::Show((($log -join "`n")), 'เปิดบันทึกคำสั่ง') | Out-Null
}
 
function New-HistPage($pg, [string]$key, [string]$code, [string]$hint, [bool]$logBtn) {
    $pg.Controls.Clear()
    $W = $pg.Width
    $H = $pg.Height
 
    $dt = New-Object Data.DataTable
    foreach ($n in @('Time', 'Type', 'Detail', 'Src')) { [void]$dt.Columns.Add($n) }
 
    # --- แถวบน: ปุ่ม + ตัวเลือก ---
    $scan = New-Object GradButton
    $scan.Text = 'สแกน'
    $scan.C1 = [Drawing.Color]::FromArgb(109, 40, 217)
    $scan.C2 = [Drawing.Color]::FromArgb(34, 160, 110)
    $scan.Size = New-Object Drawing.Size(130, 36)
    $scan.Location = New-Object Drawing.Point(18, 38)
    $scan.Tag = $key
 
    $cbDays = New-Object Windows.Forms.ComboBox
    $cbDays.DropDownStyle = 'DropDownList'
    $cbDays.FlatStyle = 'Flat'
    $cbDays.BackColor = $hcDark
    $cbDays.ForeColor = [Drawing.Color]::White
    $cbDays.Font = New-Object Drawing.Font('Segoe UI', 10)
    [void]$cbDays.Items.AddRange(@('7 วัน', '30 วัน', '90 วัน', '365 วัน'))
    $cbDays.SelectedIndex = 1
    $cbDays.Width = 92
    $cbDays.Location = New-Object Drawing.Point(160, 42)
 
    $cbCat = New-Object Windows.Forms.ComboBox
    $cbCat.DropDownStyle = 'DropDownList'
    $cbCat.FlatStyle = 'Flat'
    $cbCat.BackColor = $hcDark
    $cbCat.ForeColor = [Drawing.Color]::White
    $cbCat.Font = New-Object Drawing.Font('Segoe UI', 10)
    [void]$cbCat.Items.Add('ทั้งหมด')
    $cbCat.SelectedIndex = 0
    $cbCat.Width = 180
    $cbCat.Location = New-Object Drawing.Point(264, 42)
    $cbCat.Tag = $key
 
    $lblS = New-Object Windows.Forms.Label
    $lblS.Text = 'ค้นหา'
    $lblS.Font = New-Object Drawing.Font('ไอติม', 10)
    $lblS.ForeColor = $oLav
    $lblS.BackColor = [Drawing.Color]::Transparent
    $lblS.AutoSize = $true
    $lblS.Location = New-Object Drawing.Point(462, 46)
 
    $tbS = New-Object Windows.Forms.TextBox
    $tbS.BorderStyle = 'FixedSingle'
    $tbS.BackColor = $hcDark
    $tbS.ForeColor = [Drawing.Color]::White
    $tbS.Font = New-Object Drawing.Font('Segoe UI', 10)
    $tbS.Width = 220
    $tbS.Location = New-Object Drawing.Point(516, 42)
    $tbS.Tag = $key
 
    $btnCsv = New-Object GradButton
    $btnCsv.Text = 'บันทึก CSV'
    $btnCsv.C1 = [Drawing.Color]::FromArgb(88, 32, 176)
    $btnCsv.C2 = [Drawing.Color]::FromArgb(124, 58, 237)
    $btnCsv.Size = New-Object Drawing.Size(120, 36)
    $btnCsv.Location = New-Object Drawing.Point(($W - 18 - 120), 38)
    $btnCsv.Tag = $key
 
    $btnCopy = New-Object GradButton
    $btnCopy.Text = 'คัดลอก'
    $btnCopy.C1 = [Drawing.Color]::FromArgb(70, 50, 120)
    $btnCopy.C2 = [Drawing.Color]::FromArgb(109, 40, 217)
    $btnCopy.Size = New-Object Drawing.Size(100, 36)
    $btnCopy.Location = New-Object Drawing.Point(($W - 18 - 120 - 10 - 100), 38)
    $btnCopy.Tag = $key
 
    # --- แถวคำอธิบาย ---
    $lblH = New-Object Windows.Forms.Label
    $lblH.Text = $hint
    $lblH.Font = New-Object Drawing.Font('Segoe UI', 9)
    $lblH.ForeColor = $oLav
    $lblH.BackColor = [Drawing.Color]::Transparent
    $lblH.AutoSize = $false
    $hintW = $W - 36
    if ($logBtn) { $hintW = $W - 36 - 200 }
    $lblH.Size = New-Object Drawing.Size($hintW, 34)
    $lblH.Location = New-Object Drawing.Point(18, 80)
 
    $pg.Controls.AddRange(@($scan, $cbDays, $cbCat, $lblS, $tbS, $btnCopy, $btnCsv, $lblH))
 
    if ($logBtn) {
        $btnLog = New-Object GradButton
        $btnLog.Text = 'เปิดบันทึกคำสั่ง'
        $btnLog.C1 = [Drawing.Color]::FromArgb(22, 163, 74)
        $btnLog.C2 = [Drawing.Color]::FromArgb(52, 211, 153)
        $btnLog.Size = New-Object Drawing.Size(190, 32)
        $btnLog.Location = New-Object Drawing.Point(($W - 18 - 190), 80)
        $btnLog.Add_Click({ Enable-CmdLogging })
        $pg.Controls.Add($btnLog)
    }
 
    # --- ตาราง ---
    $grid = New-Object Windows.Forms.DataGridView
    $grid.Tag = $key
    $grid.Location = New-Object Drawing.Point(18, 118)
    $grid.Size = New-Object Drawing.Size(($W - 36), ($H - 118 - 46))
    $grid.ReadOnly = $true
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.AllowUserToResizeRows = $false
    $grid.RowHeadersVisible = $false
    $grid.BorderStyle = 'None'
    $grid.BackgroundColor = $hcDark
    $grid.GridColor = [Drawing.Color]::FromArgb(45, 34, 84)
    $grid.CellBorderStyle = 'SingleHorizontal'
    $grid.EnableHeadersVisualStyles = $false
    $grid.ColumnHeadersBorderStyle = 'None'
    $grid.ColumnHeadersHeightSizeMode = 'DisableResizing'
    $grid.ColumnHeadersHeight = 32
    $grid.ColumnHeadersDefaultCellStyle.BackColor = $hcHead
    $grid.ColumnHeadersDefaultCellStyle.ForeColor = [Drawing.Color]::FromArgb(196, 181, 253)
    $grid.ColumnHeadersDefaultCellStyle.SelectionBackColor = $hcHead
    $grid.ColumnHeadersDefaultCellStyle.Font = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)
    $grid.DefaultCellStyle.BackColor = $hcDark
    $grid.DefaultCellStyle.ForeColor = [Drawing.Color]::White
    $grid.DefaultCellStyle.SelectionBackColor = [Drawing.Color]::FromArgb(88, 50, 160)
    $grid.DefaultCellStyle.SelectionForeColor = [Drawing.Color]::White
    $grid.DefaultCellStyle.Font = New-Object Drawing.Font('Segoe UI', 9.5)
    $grid.AlternatingRowsDefaultCellStyle.BackColor = [Drawing.Color]::FromArgb(28, 21, 48)
    $grid.SelectionMode = 'FullRowSelect'
    $grid.MultiSelect = $true
    $grid.RowTemplate.Height = 26
    $grid.AutoGenerateColumns = $false
    try { $grid.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'Instance,NonPublic').SetValue($grid, $true, $null) } catch { }
 
    foreach ($c in @(@('Time', 'เวลา', 150), @('Type', 'ประเภท', 150), @('Detail', 'รายละเอียด', 0), @('Src', 'แหล่งที่มา', 230))) {
        $col = New-Object Windows.Forms.DataGridViewTextBoxColumn
        $col.DataPropertyName = $c[0]
        $col.Name = $c[0]
        $col.HeaderText = $c[1]
        $col.SortMode = 'Automatic'
        if ($c[2] -gt 0) { $col.Width = $c[2] } else { $col.AutoSizeMode = 'Fill'; $col.MinimumWidth = 220 }
        [void]$grid.Columns.Add($col)
    }
    $grid.DataSource = $dt.DefaultView
    $pg.Controls.Add($grid)
 
    # --- สถานะ ---
    $st = New-Object Windows.Forms.Label
    $st.Text = 'กด "สแกน" เพื่อเริ่ม'
    $st.Font = New-Object Drawing.Font('Segoe UI', 9)
    $st.ForeColor = $oLav
    $st.BackColor = [Drawing.Color]::Transparent
    $st.AutoSize = $false
    $st.Size = New-Object Drawing.Size(($W - 36), 22)
    $st.Location = New-Object Drawing.Point(18, ($H - 34))
    $pg.Controls.Add($st)
 
    $script:histUi[$key] = @{
        Key = $key; Page = $pg; Grid = $grid; Dt = $dt; Cat = $cbCat; Days = $cbDays; Search = $tbS
        Scan = $scan; Status = $st; Code = $code; Busy = $false; Scanned = $false; Info = ''
    }
 
    $scan.Add_Click({ param($s, $e) Start-HistScan ([string]$s.Tag) })
    $cbCat.Add_SelectedIndexChanged({ param($s, $e) Apply-Filter $script:histUi[[string]$s.Tag] })
    $tbS.Add_TextChanged({ param($s, $e) Apply-Filter $script:histUi[[string]$s.Tag] })
    $btnCsv.Add_Click({ param($s, $e) Export-HistCsv $script:histUi[[string]$s.Tag] })
    $btnCopy.Add_Click({ param($s, $e) Copy-HistRows $script:histUi[[string]$s.Tag] })
    $grid.Add_CellDoubleClick({
        param($s, $e)
        if ($e.RowIndex -lt 0) { return }
        $v = $s.Rows[$e.RowIndex].Cells['Detail'].Value
        if ($v) {
            try { [Windows.Forms.Clipboard]::SetText([string]$v) } catch { }
            $script:histUi[[string]$s.Tag].Status.Text = 'คัดลอกรายละเอียดของแถวที่เลือกแล้ว'
        }
    })
}
 
# ---------------------------------------------------------------------
#  สร้าง 2 หน้า (ใช้หน้าเปล่าที่ sidebar_patch.ps1 เตรียมไว้)
# ---------------------------------------------------------------------
New-HistPage $script:pages[1][0] 'activity' $actCode ('รวมประวัติ: เปิด/ปิดเครื่อง, Sleep/Wake, ล็อกอิน, โปรแกรมที่เปิด (Prefetch / UserAssist), ไฟล์ที่เปิดล่าสุด และตรวจว่ามีการล้าง Event Log หรือไม่ | ดับเบิลคลิกแถวเพื่อคัดลอกรายละเอียด') $false
 
New-HistPage $script:pages[2][0] 'commands' $cmdCode ('PowerShell: ประวัติที่พิมพ์ (ไม่มีเวลา) + Script Block log | CMD ไม่เก็บประวัติลงดิสก์ จะเห็นผ่าน Process Log (Event 4688) เมื่อเปิดบันทึกไว้ | Win+R และเครื่องมือ CLI ที่เคยเปิด') $true
 
# เปิดแท็บครั้งแรก = สแกนให้อัตโนมัติ 1 รอบ
$nav.Add_SelectedChanged({
    param($s, $e)
    $k = ''
    if ([int]$s.Selected -eq 1) { $k = 'activity' }
    elseif ([int]$s.Selected -eq 2) { $k = 'commands' }
    if ($k -and -not $script:histUi[$k].Scanned) {
        $script:histUi[$k].Scanned = $true
        Start-HistScan $k
    }
})
$cs5 = @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;
 
public class HistRow
{
    public string Time = "-";
    public string Type = "";
    public string Detail = "";
    public string Src = "";
    public string Hay = "";
    public int Idx;
}
 
public static class UiK
{
    public static GraphicsPath Round(Rectangle r, int rad)
    {
        int d = Math.Max(1, Math.Min(rad * 2, Math.Min(r.Width, r.Height)));
        GraphicsPath p = new GraphicsPath();
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }
 
    public static Color Lite(Color c, int n)
    {
        return Color.FromArgb(Math.Min(255, c.R + n), Math.Min(255, c.G + n), Math.Min(255, c.B + n));
    }
}
 
// ---------------------------------------------------------------------
//  ตารางผลลัพธ์ (วาดเอง): หัวตารางแบบแคปชัน, ป้ายประเภทสีสัน, แถบเลื่อนบาง ๆ สีม่วง
// ---------------------------------------------------------------------
public class HistGrid : Control
{
    public List<HistRow> All = new List<HistRow>();
    public List<HistRow> View = new List<HistRow>();
    public string EmptyText = "";
    public HistRow ActivatedRow;
    public event EventHandler ViewChanged;
    public event EventHandler RowActivated;
 
    string fType = "";
    string fQuery = "";
    int sortCol = -1;
    int sortClicks;
    bool sortDesc;
    int scroll;
    int hot = -1;
    int sel = -1;
    bool dragging;
    bool thumbHot;
    int dragOff;
    ToolTip tt = new ToolTip();
 
    const int HeadH = 36;
    const int RowH = 32;
    const int Pad = 16;
 
    static Font fHead = new Font("Segoe UI", 7.5f, FontStyle.Bold);
    static Font fTime = new Font("Consolas", 9.5f);
    static Font fTxt = new Font("Segoe UI", 9.5f);
    static Font fSrc = new Font("Segoe UI", 8.5f);
    static Font fChip = new Font("Segoe UI", 8.5f, FontStyle.Bold);
 
    public HistGrid()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer
            | ControlStyles.SupportsTransparentBackColor | ControlStyles.ResizeRedraw, true);
        BackColor = Color.Transparent;
        tt.InitialDelay = 600;
        tt.AutoPopDelay = 20000;
    }
 
    // ---------- ข้อมูล ----------
    public void SetData(List<HistRow> rows)
    {
        All = rows;
        for (int i = 0; i < All.Count; i++)
        {
            HistRow r = All[i];
            r.Idx = i;
            r.Hay = (r.Type + "\n" + r.Detail + "\n" + r.Src).ToLowerInvariant();
        }
        sortCol = -1;
        sortClicks = 0;
        Rebuild();
    }
 
    public void SetFilter(string type, string query)
    {
        fType = type == null ? "" : type;
        fQuery = query == null ? "" : query.ToLowerInvariant();
        Rebuild();
    }
 
    public List<string> Types()
    {
        Dictionary<string, int> d = new Dictionary<string, int>();
        List<string> l = new List<string>();
        foreach (HistRow r in All)
        {
            if (!d.ContainsKey(r.Type)) { d[r.Type] = 1; l.Add(r.Type); }
        }
        l.Sort(StringComparer.Ordinal);
        return l;
    }
 
    static string KeyOf(HistRow r, int c)
    {
        if (c == 0) return r.Time == "-" ? "" : r.Time;
        if (c == 1) return r.Type;
        if (c == 2) return r.Detail;
        return r.Src;
    }
 
    void Rebuild()
    {
        List<HistRow> v = new List<HistRow>();
        foreach (HistRow r in All)
        {
            if (fType.Length > 0 && r.Type != fType) continue;
            if (fQuery.Length > 0 && r.Hay.IndexOf(fQuery, StringComparison.Ordinal) < 0) continue;
            v.Add(r);
        }
        if (sortCol >= 0)
        {
            int c = sortCol;
            bool desc = sortDesc;
            v.Sort(delegate(HistRow a, HistRow b)
            {
                int x = string.Compare(KeyOf(a, c), KeyOf(b, c), StringComparison.OrdinalIgnoreCase);
                if (x == 0) x = a.Idx.CompareTo(b.Idx);
                return desc ? -x : x;
            });
        }
        View = v;
        scroll = 0;
        hot = -1;
        sel = -1;
        tt.SetToolTip(this, "");
        Invalidate();
        if (ViewChanged != null) ViewChanged(this, EventArgs.Empty);
    }
 
    // ---------- เลย์เอาต์ ----------
    int[] Lay()
    {
        int avail = Width - Pad * 2 - 14;
        int wTime = 150, wType = 150;
        int wSrc = avail > 780 ? 230 : 150;
        int wDet = Math.Max(80, avail - wTime - wType - wSrc);
        return new int[] { Pad, wTime, Pad + wTime, wType, Pad + wTime + wType, wDet, Pad + wTime + wType + wDet, wSrc };
    }
 
    int HitCol(int x)
    {
        int[] L = Lay();
        for (int i = 0; i < 4; i++)
            if (x >= L[i * 2] && x < L[i * 2] + L[i * 2 + 1]) return i;
        return -1;
    }
 
    int ViewH { get { return Height - HeadH - 8; } }
    int Total { get { return View.Count * RowH; } }
    int MaxScroll { get { return Math.Max(0, Total - ViewH); } }
    Rectangle Track { get { return new Rectangle(Width - 14, HeadH + 6, 6, Height - HeadH - 12); } }
 
    int ThumbH
    {
        get
        {
            if (MaxScroll <= 0) return 0;
            return Math.Max(32, (int)((long)Track.Height * ViewH / Math.Max(1, Total)));
        }
    }
 
    Rectangle Thumb
    {
        get
        {
            int th = ThumbH;
            if (th <= 0) return Rectangle.Empty;
            Rectangle t = Track;
            int span = t.Height - th;
            int y = t.Y + (int)((long)span * scroll / Math.Max(1, MaxScroll));
            return new Rectangle(t.X - 2, y, t.Width + 4, th);
        }
    }
 
    int RowAt(int y)
    {
        if (y < HeadH || y >= Height - 4) return -1;
        int idx = (y - HeadH + scroll) / RowH;
        return idx < View.Count ? idx : -1;
    }
 
    void SetScroll(int v)
    {
        v = Math.Max(0, Math.Min(v, MaxScroll));
        if (v != scroll) { scroll = v; Invalidate(); }
    }
 
    // ---------- เมาส์ ----------
    protected override void OnMouseEnter(EventArgs e) { Focus(); base.OnMouseEnter(e); }
 
    protected override void OnMouseLeave(EventArgs e)
    {
        hot = -1;
        thumbHot = false;
        Invalidate();
        base.OnMouseLeave(e);
    }
 
    protected override void OnMouseWheel(MouseEventArgs e)
    {
        SetScroll(scroll - Math.Sign(e.Delta) * RowH * 3);
        base.OnMouseWheel(e);
    }
 
    protected override void OnMouseMove(MouseEventArgs e)
    {
        if (dragging)
        {
            int span = Track.Height - ThumbH;
            if (span > 0) SetScroll((int)((long)(e.Y - dragOff - Track.Y) * MaxScroll / span));
            return;
        }
        bool th = MaxScroll > 0 && Thumb.Contains(e.Location);
        int h = (e.X < Width - 20) ? RowAt(e.Y) : -1;
        Cursor = (e.Y < HeadH && e.Y >= 0) ? Cursors.Hand : Cursors.Default;
        if (h != hot || th != thumbHot)
        {
            if (h != hot)
            {
                tt.SetToolTip(this, h >= 0 ? View[h].Detail + "\n\n" + View[h].Src : "");
            }
            hot = h;
            thumbHot = th;
            Invalidate();
        }
        base.OnMouseMove(e);
    }
 
    protected override void OnMouseDown(MouseEventArgs e)
    {
        Focus();
        if (e.Button == MouseButtons.Left)
        {
            if (MaxScroll > 0 && Thumb.Contains(e.Location))
            {
                dragging = true;
                dragOff = e.Y - Thumb.Y;
            }
            else if (MaxScroll > 0 && e.X >= Width - 22 && e.Y > HeadH)
            {
                SetScroll(scroll + (e.Y < Thumb.Y ? -ViewH : ViewH));
            }
            else if (e.Y < HeadH)
            {
                int hc = HitCol(e.X);
                if (hc >= 0)
                {
                    if (sortCol != hc) { sortCol = hc; sortDesc = (hc == 0); sortClicks = 1; }
                    else if (sortClicks == 1) { sortDesc = !sortDesc; sortClicks = 2; }
                    else { sortCol = -1; sortClicks = 0; }
                    Rebuild();
                }
            }
            else
            {
                int r = RowAt(e.Y);
                if (r != sel) { sel = r; Invalidate(); }
            }
        }
        base.OnMouseDown(e);
    }
 
    protected override void OnMouseUp(MouseEventArgs e)
    {
        dragging = false;
        base.OnMouseUp(e);
    }
 
    protected override void OnMouseDoubleClick(MouseEventArgs e)
    {
        int h = (e.X < Width - 20) ? RowAt(e.Y) : -1;
        if (h >= 0)
        {
            ActivatedRow = View[h];
            if (RowActivated != null) RowActivated(this, EventArgs.Empty);
        }
        base.OnMouseDoubleClick(e);
    }
 
    // ---------- วาด ----------
    static Color ChipColor(string t)
    {
        if (t.IndexOf("ล้าง") >= 0) return Color.FromArgb(248, 113, 113);
        if (t == "ข้อมูล") return Color.FromArgb(150, 140, 190);
        Color[] pal = {
            Color.FromArgb(74, 222, 128), Color.FromArgb(192, 132, 252), Color.FromArgb(56, 189, 248),
            Color.FromArgb(251, 146, 60), Color.FromArgb(244, 114, 182), Color.FromArgb(45, 212, 191),
            Color.FromArgb(163, 230, 53)
        };
        int h = 0;
        foreach (char ch in t) h = (h * 31 + ch) & 0x7fffffff;
        return pal[h % pal.Length];
    }
 
    void DrawRows(Graphics g)
    {
        TextFormatFlags fl = TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix | TextFormatFlags.VerticalCenter
            | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis | TextFormatFlags.Left;
 
        if (View.Count == 0)
        {
            TextRenderer.DrawText(g, EmptyText, fTxt, new Rectangle(0, HeadH, Width, Height - HeadH), Color.FromArgb(130, 120, 170),
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix);
            return;
        }
 
        int[] L = Lay();
        int first = Math.Max(0, scroll / RowH);
        int last = Math.Min(View.Count - 1, (scroll + ViewH + RowH) / RowH);
        for (int i = first; i <= last; i++)
        {
            HistRow row = View[i];
            int y = HeadH + i * RowH - scroll;
            Rectangle rr = new Rectangle(6, y + 1, Width - 12 - 14, RowH - 2);
 
            if (i == sel)
            {
                using (GraphicsPath gp = UiK.Round(rr, 8))
                {
                    using (SolidBrush sb = new SolidBrush(Color.FromArgb(80, 18, 70, 48))) g.FillPath(sb, gp);
                    using (Pen sp = new Pen(Color.FromArgb(170, 74, 222, 128), 1.2f)) g.DrawPath(sp, gp);
                }
            }
            else if (i == hot)
            {
                using (GraphicsPath gp = UiK.Round(rr, 8))
                using (SolidBrush hb = new SolidBrush(Color.FromArgb(70, 110, 70, 210))) g.FillPath(hb, gp);
            }
            else if ((i & 1) == 1)
            {
                using (GraphicsPath gp = UiK.Round(rr, 8))
                using (SolidBrush ab = new SolidBrush(Color.FromArgb(12, 255, 255, 255))) g.FillPath(ab, gp);
            }
 
            // เวลา
            bool noTime = (row.Time == "-");
            TextRenderer.DrawText(g, noTime ? "-" : row.Time, fTime, new Rectangle(L[0], y, L[1] - 6, RowH),
                noTime ? Color.FromArgb(100, 92, 140) : Color.FromArgb(176, 166, 215), fl);
 
            // ป้ายประเภท
            Color cc = ChipColor(row.Type);
            Size ts = TextRenderer.MeasureText(g, row.Type, fChip, new Size(L[3], 20), TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix);
            int cw = Math.Min(L[3] - 10, ts.Width + 20);
            Rectangle chip = new Rectangle(L[2], y + (RowH - 22) / 2, cw, 22);
            using (GraphicsPath cp = UiK.Round(chip, 10))
            {
                using (SolidBrush cb = new SolidBrush(Color.FromArgb(48, cc))) g.FillPath(cb, cp);
                using (Pen cpn = new Pen(Color.FromArgb(150, cc), 1f)) g.DrawPath(cpn, cp);
            }
            TextRenderer.DrawText(g, row.Type, fChip, chip, UiK.Lite(cc, 40),
                TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix
                | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis);
 
            // รายละเอียด
            Color dc = Color.White;
            if (row.Type == "ข้อมูล") dc = Color.FromArgb(196, 181, 253);
            else if (row.Type.IndexOf("ล้าง") >= 0) dc = Color.FromArgb(252, 165, 165);
            TextRenderer.DrawText(g, row.Detail, fTxt, new Rectangle(L[4], y, L[5] - 12, RowH), dc, fl);
 
            // แหล่งที่มา
            TextRenderer.DrawText(g, row.Src, fSrc, new Rectangle(L[6], y, L[7], RowH), Color.FromArgb(128, 118, 170), fl);
        }
    }
 
    void DrawHeader(Graphics g)
    {
        using (SolidBrush b = new SolidBrush(Color.FromArgb(30, 19, 62)))
            g.FillRectangle(b, 0, 0, Width, HeadH);
        using (Pen pen = new Pen(Color.FromArgb(80, 140, 100, 225), 1f))
            g.DrawLine(pen, 0, HeadH, Width, HeadH);
 
        int[] L = Lay();
        string[] names = { "TIME", "TYPE", "DETAIL", "SOURCE" };
        for (int i = 0; i < 4; i++)
        {
            string t = names[i];
            Color c = Color.FromArgb(120, 110, 165);
            if (sortCol == i)
            {
                t += sortDesc ? "   \u25BC" : "   \u25B2";
                c = Color.FromArgb(74, 222, 128);
            }
            TextRenderer.DrawText(g, t, fHead, new Rectangle(L[i * 2], 0, L[i * 2 + 1], HeadH), c,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix | TextFormatFlags.SingleLine);
        }
    }
 
    void DrawScroll(Graphics g)
    {
        if (MaxScroll <= 0) return;
        Rectangle t = Track;
        using (GraphicsPath tp = UiK.Round(t, 3))
        using (SolidBrush tb = new SolidBrush(Color.FromArgb(22, 255, 255, 255))) g.FillPath(tb, tp);
        using (GraphicsPath hp = UiK.Round(Thumb, 5))
        using (SolidBrush hb = new SolidBrush(Color.FromArgb((thumbHot || dragging) ? 230 : 150, 168, 85, 247))) g.FillPath(hb, hp);
    }
 
    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        if (Width < 160 || Height < 90) return;
        Rectangle r = new Rectangle(0, 0, Width - 1, Height - 1);
        using (GraphicsPath p = UiK.Round(r, 14))
        {
            using (SolidBrush b = new SolidBrush(Color.FromArgb(15, 9, 33))) g.FillPath(b, p);
            g.SetClip(p);
            DrawRows(g);
            DrawHeader(g);
            DrawScroll(g);
            g.ResetClip();
            using (Pen pen = new Pen(Color.FromArgb(58, 44, 100), 1.1f)) g.DrawPath(pen, p);
        }
    }
 
    protected override void Dispose(bool disposing)
    {
        if (disposing) tt.Dispose();
        base.Dispose(disposing);
    }
}
 
// ---------------------------------------------------------------------
//  ลิสต์ที่เด้งลงมาของ DarkCombo
// ---------------------------------------------------------------------
public class ComboPop : Control
{
    public List<string> Items = new List<string>();
    public int Sel = -1;
    public int PickedIndex;
    public event EventHandler Picked;
    public const int RowH = 30;
    int hot = -1;
    int top;
 
    public ComboPop()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer, true);
        BackColor = Color.FromArgb(22, 17, 38);
        Font = new Font("Segoe UI", 10f);
    }
 
    int VisRows { get { return Math.Max(1, (Height - 8) / RowH); } }
 
    protected override void OnMouseMove(MouseEventArgs e)
    {
        int idx = (e.Y < 4) ? -1 : top + (e.Y - 4) / RowH;
        if (idx >= Items.Count || idx >= top + VisRows) idx = -1;
        if (idx != hot) { hot = idx; Invalidate(); }
        base.OnMouseMove(e);
    }
 
    protected override void OnMouseLeave(EventArgs e) { hot = -1; Invalidate(); base.OnMouseLeave(e); }
 
    protected override void OnMouseWheel(MouseEventArgs e)
    {
        int max = Math.Max(0, Items.Count - VisRows);
        top = Math.Max(0, Math.Min(max, top - Math.Sign(e.Delta)));
        Invalidate();
        base.OnMouseWheel(e);
    }
 
    protected override void OnMouseClick(MouseEventArgs e)
    {
        if (hot >= 0)
        {
            PickedIndex = hot;
            if (Picked != null) Picked(this, EventArgs.Empty);
        }
        base.OnMouseClick(e);
    }
 
    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.Clear(Color.FromArgb(22, 17, 38));
        using (Pen bp = new Pen(Color.FromArgb(139, 92, 246), 1.2f))
            g.DrawRectangle(bp, 0, 0, Width - 1, Height - 1);
 
        if (Sel < top) top = Sel < 0 ? 0 : Sel;
        for (int k = 0; k < VisRows; k++)
        {
            int i = top + k;
            if (i >= Items.Count) break;
            Rectangle r = new Rectangle(5, 4 + k * RowH, Width - 10, RowH - 2);
            bool s = (i == Sel);
            if (i == hot)
            {
                using (GraphicsPath gp = UiK.Round(r, 8))
                using (SolidBrush hb = new SolidBrush(Color.FromArgb(110, 90, 60, 170))) g.FillPath(hb, gp);
            }
            else if (s)
            {
                using (GraphicsPath gp = UiK.Round(r, 8))
                using (SolidBrush sb = new SolidBrush(Color.FromArgb(70, 18, 70, 48))) g.FillPath(sb, gp);
            }
            TextRenderer.DrawText(g, Items[i], Font, new Rectangle(r.X + 10, r.Y, r.Width - 30, r.Height),
                s ? Color.FromArgb(74, 222, 128) : Color.White,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix
                | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis);
            if (s)
            {
                using (Pen ck = new Pen(Color.FromArgb(74, 222, 128), 1.8f))
                {
                    ck.StartCap = LineCap.Round;
                    ck.EndCap = LineCap.Round;
                    int cx = r.Right - 16, cy = r.Y + r.Height / 2;
                    g.DrawLine(ck, cx - 4, cy, cx - 1, cy + 3);
                    g.DrawLine(ck, cx - 1, cy + 3, cx + 5, cy - 3);
                }
            }
        }
    }
}
 
// ---------------------------------------------------------------------
//  ดรอปดาวน์สไตล์ Orion (แทน ComboBox ขาวดำ)
// ---------------------------------------------------------------------
public class DarkCombo : Control
{
    public List<string> Items = new List<string>();
    public event EventHandler SelectedChanged;
 
    int sel = -1;
    bool hover;
    bool open;
    DateTime lastClose = DateTime.MinValue;
    ToolStripDropDown dd = new ToolStripDropDown();
    ComboPop pop = new ComboPop();
    ToolStripControlHost host;
 
    public DarkCombo()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer
            | ControlStyles.SupportsTransparentBackColor | ControlStyles.ResizeRedraw, true);
        BackColor = Color.Transparent;
        Cursor = Cursors.Hand;
        ForeColor = Color.White;
        Font = new Font("Segoe UI", 10f);
 
        dd.Padding = Padding.Empty;
        dd.BackColor = Color.FromArgb(22, 17, 38);
        dd.DropShadowEnabled = false;
        host = new ToolStripControlHost(pop);
        host.Margin = Padding.Empty;
        host.Padding = Padding.Empty;
        host.AutoSize = false;
        dd.Items.Add(host);
        dd.Closed += delegate { open = false; lastClose = DateTime.Now; Invalidate(); };
        pop.Picked += delegate { Selected = pop.PickedIndex; dd.Close(); };
    }
 
    public int Selected
    {
        get { return sel; }
        set
        {
            if (sel == value) return;
            sel = value;
            Invalidate();
            if (SelectedChanged != null) SelectedChanged(this, EventArgs.Empty);
        }
    }
 
    public string SelectedItem
    {
        get { return (sel >= 0 && sel < Items.Count) ? Items[sel] : ""; }
    }
 
    void Toggle()
    {
        if (open) { dd.Close(); return; }
        if ((DateTime.Now - lastClose).TotalMilliseconds < 250) return;
        if (Items.Count == 0) return;
        int rows = Math.Min(Items.Count, 9);
        Size sz = new Size(Width, rows * ComboPop.RowH + 8);
        pop.Items = Items;
        pop.Sel = sel;
        pop.Size = sz;
        host.Size = sz;
        open = true;
        Invalidate();
        dd.Show(this, new Point(0, Height + 4));
    }
 
    protected override void OnMouseEnter(EventArgs e) { hover = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { hover = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnMouseClick(MouseEventArgs e) { Toggle(); base.OnMouseClick(e); }
 
    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        Rectangle r = new Rectangle(0, 0, Width - 1, Height - 1);
        if (r.Width < 30 || r.Height < 16) return;
        Color border = open ? Color.FromArgb(139, 92, 246) : (hover ? Color.FromArgb(110, 84, 180) : Color.FromArgb(64, 54, 94));
        using (GraphicsPath p = UiK.Round(r, 12))
        {
            using (SolidBrush b = new SolidBrush(Color.FromArgb(22, 17, 38))) g.FillPath(b, p);
            using (Pen pen = new Pen(border, 1.2f)) g.DrawPath(pen, p);
        }
        TextRenderer.DrawText(g, SelectedItem, Font, new Rectangle(14, 0, Width - 44, Height), ForeColor,
            TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding | TextFormatFlags.NoPrefix
            | TextFormatFlags.SingleLine | TextFormatFlags.EndEllipsis);
        int cx = Width - 22, cy = Height / 2;
        using (Pen ch = new Pen(open ? Color.FromArgb(196, 181, 253) : Color.FromArgb(165, 155, 195), 1.8f))
        {
            ch.StartCap = LineCap.Round;
            ch.EndCap = LineCap.Round;
            if (open)
            {
                g.DrawLine(ch, cx - 5, cy + 2, cx, cy - 3);
                g.DrawLine(ch, cx, cy - 3, cx + 5, cy + 2);
            }
            else
            {
                g.DrawLine(ch, cx - 5, cy - 2, cx, cy + 3);
                g.DrawLine(ch, cx, cy + 3, cx + 5, cy - 2);
            }
        }
    }
 
    protected override void Dispose(bool disposing)
    {
        if (disposing) { dd.Dispose(); }
        base.Dispose(disposing);
    }
}
 
// ---------------------------------------------------------------------
//  ช่องค้นหา (ไอคอนแว่นขยาย + ปุ่มล้างข้อความ)
// ---------------------------------------------------------------------
public class SearchBox : Control
{
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr SendMessage(IntPtr h, int m, IntPtr w, string l);
 
    public TextBox Box = new TextBox();
    public string Placeholder = "";
    bool focused;
    static Color Fill = Color.FromArgb(22, 17, 38);
 
    public SearchBox()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer
            | ControlStyles.SupportsTransparentBackColor | ControlStyles.ResizeRedraw, true);
        BackColor = Color.Transparent;
        Box.BorderStyle = BorderStyle.None;
        Box.BackColor = Fill;
        Box.ForeColor = Color.White;
        Box.Font = new Font("Segoe UI", 10.5f);
        Box.GotFocus += delegate { focused = true; Invalidate(); };
        Box.LostFocus += delegate { focused = false; Invalidate(); };
        Box.TextChanged += delegate { Invalidate(); };
        Box.HandleCreated += delegate
        {
            if (Placeholder.Length > 0) SendMessage(Box.Handle, 0x1501, IntPtr.Zero, Placeholder);
        };
        Controls.Add(Box);
    }
 
    void LayoutBox()
    {
        Box.Left = 40;
        Box.Width = Math.Max(20, Width - 40 - 38);
        Box.Top = Math.Max(0, (Height - Box.Height) / 2);
    }
 
    protected override void OnResize(EventArgs e) { base.OnResize(e); LayoutBox(); }
    protected override void OnHandleCreated(EventArgs e) { base.OnHandleCreated(e); LayoutBox(); }
 
    protected override void OnMouseMove(MouseEventArgs e)
    {
        Cursor = (e.X >= Width - 36 && Box.Text.Length > 0) ? Cursors.Hand : Cursors.Default;
        base.OnMouseMove(e);
    }
 
    protected override void OnMouseClick(MouseEventArgs e)
    {
        if (e.X >= Width - 36 && Box.Text.Length > 0) { Box.Text = ""; }
        Box.Focus();
        base.OnMouseClick(e);
    }
 
    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        Rectangle r = new Rectangle(0, 0, Width - 1, Height - 1);
        if (r.Width < 40 || r.Height < 16) return;
        Color border = focused ? Color.FromArgb(139, 92, 246) : Color.FromArgb(64, 54, 94);
        using (GraphicsPath p = UiK.Round(r, 12))
        {
            using (SolidBrush b = new SolidBrush(Fill)) g.FillPath(b, p);
            using (Pen pen = new Pen(border, 1.2f)) g.DrawPath(pen, p);
        }
        int cy = Height / 2;
        using (Pen kp = new Pen(focused ? Color.FromArgb(196, 181, 253) : Color.FromArgb(165, 155, 195), 1.7f))
        {
            kp.StartCap = LineCap.Round;
            kp.EndCap = LineCap.Round;
            g.DrawEllipse(kp, 15, cy - 7, 10, 10);
            g.DrawLine(kp, 23, cy + 1, 28, cy + 6);
            if (Box.Text.Length > 0)
            {
                int ex = Width - 20;
                g.DrawLine(kp, ex - 4, cy - 4, ex + 4, cy + 4);
                g.DrawLine(kp, ex - 4, cy + 4, ex + 4, cy - 4);
            }
        }
    }
}
'@
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition $cs5 -Language CSharp -ErrorAction Stop
 
# ---------------------------------------------------------------------
#  ฟังก์ชันของหน้า (ทับของเดิมที่ชื่อเดียวกัน)
# ---------------------------------------------------------------------
$script:histUi = @{}
$script:histScanLabel = ([string][char]0x25B6 + '  สแกน')
 
function Apply-HistFilter($ui) {
    if ($null -eq $ui) { return }
    $t = ''
    if ($ui.Cat.Selected -gt 0) { $t = [string]$ui.Cat.SelectedItem }
    $ui.Grid.SetFilter($t, [string]$ui.Search.Box.Text.Trim())
}
 
function Update-HistStats($ui) {
    if ($null -eq $ui) { return }
    $g = $ui.Grid
    $ui.BxShow.Value = [string]$g.View.Count
    if ($g.All.Count -gt 0 -and $g.View.Count -eq 0) { $g.EmptyText = 'ไม่พบรายการที่ตรงกับตัวกรอง' }
    $ui.Status.Text = ('แสดง ' + $g.View.Count + ' / ' + $g.All.Count + ' รายการ' + $ui.Info +
        '   ·   ดับเบิลคลิกแถวเพื่อคัดลอก   ·   คลิกหัวคอลัมน์เพื่อเรียงลำดับ')
}
 
$script:histDone = {
    param($out, $ctx)
    $ui = $script:histUi[[string]$ctx.Key]
    $ui.Busy = $false
    if ($ui.Page.IsDisposed) { return }
    $ui.Scan.Enabled = $true
    $ui.Scan.Text = $script:histScanLabel
 
    $rows = @($out | Where-Object { $_ -and $_.PSObject.Properties['Detail'] })
    $errs = @($out | Where-Object { $_ -is [string] })
 
    $list = New-Object 'System.Collections.Generic.List[HistRow]'
    foreach ($r in $rows) {
        $x = New-Object HistRow
        if ($r.T -is [datetime]) { $x.Time = $r.T.ToString('yyyy-MM-dd HH:mm:ss') }
        $x.Type = [string]$r.Type
        $x.Detail = [string]$r.Detail
        $x.Src = [string]$r.Src
        $list.Add($x)
    }
 
    $ui.Info = '   ·   สแกนเมื่อ ' + (Get-Date).ToString('HH:mm:ss')
    if ($errs.Count -gt 0) { $ui.Info += '   ·   มีข้อผิดพลาด: ' + [string]$errs[0] }
    $ui.Grid.EmptyText = 'ไม่พบข้อมูลในช่วงเวลานี้'
    $ui.Grid.SetData($list)
 
    $ui.Cat.Items.Clear()
    $ui.Cat.Items.Add('ทั้งหมด')
    $tl = @($ui.Grid.Types())
    foreach ($t in $tl) { $ui.Cat.Items.Add([string]$t) }
    $ui.Cat.Selected = 0
    $ui.Cat.Invalidate()
    Apply-HistFilter $ui
 
    $ui.BxTotal.Value = [string]$list.Count
    $ui.BxTypes.Value = [string]$tl.Count
    $ui.BxScan.Value = (Get-Date).ToString('HH:mm:ss')
    $ui.BxScan.Sub = ('ย้อนหลัง ' + $ui.DaysUsed + ' วัน')
    Update-HistStats $ui
}
 
function Start-HistScan([string]$key) {
    $ui = $script:histUi[$key]
    if ($null -eq $ui -or $ui.Busy) { return }
    $ui.Busy = $true
    $ui.Scan.Enabled = $false
    $ui.Scan.Text = 'กำลังสแกน...'
    $ui.Status.Text = 'กำลังอ่านข้อมูล... (หน้าต่างไม่ค้าง รอสักครู่)'
    $ui.Grid.EmptyText = 'กำลังอ่านข้อมูล... รอสักครู่'
    $ui.Grid.Invalidate()
    $d = 30
    try { $d = [int](([string]$ui.Days.SelectedItem) -replace '\D', '') } catch { }
    $ui.DaysUsed = $d
    Start-Bg $ui.Code @{ days = $d } $script:histDone @{ Key = $key }
}
 
function Export-HistCsv($ui) {
    $sfd = New-Object Windows.Forms.SaveFileDialog
    $sfd.Filter = 'CSV (*.csv)|*.csv'
    $sfd.FileName = ($ui.Key + '_' + (Get-Date).ToString('yyyyMMdd_HHmm') + '.csv')
    if ($sfd.ShowDialog() -ne 'OK') { return }
    try {
        $out = foreach ($r in $ui.Grid.View) {
            [pscustomobject]@{ Time = $r.Time; Type = $r.Type; Detail = $r.Detail; Source = $r.Src }
        }
        @($out) | Export-Csv -LiteralPath $sfd.FileName -NoTypeInformation -Encoding UTF8
        $ui.Status.Text = 'บันทึกแล้ว: ' + $sfd.FileName
    } catch {
        [Windows.Forms.MessageBox]::Show(('บันทึกไม่สำเร็จ: ' + $_.Exception.Message), 'Export CSV') | Out-Null
    }
}
 
function Copy-HistRows($ui) {
    $sb = New-Object Text.StringBuilder
    foreach ($r in $ui.Grid.View) {
        [void]$sb.AppendLine(([string]$r.Time + "`t" + [string]$r.Type + "`t" + [string]$r.Detail + "`t" + [string]$r.Src))
    }
    if ($sb.Length -gt 0) {
        try { [Windows.Forms.Clipboard]::SetText($sb.ToString()); $ui.Status.Text = 'คัดลอกรายการที่แสดงอยู่แล้ว' } catch { }
    }
}
 
function New-HistBox([string]$cap, [string]$sub, [int]$x, [int]$w, $col) {
    $b = New-Object StatBox
    $b.Caption = $cap
    $b.Sub = $sub
    $b.ValColor = $col
    $b.Size = New-Object Drawing.Size($w, 68)
    $b.Location = New-Object Drawing.Point($x, 122)
    return $b
}
 
function New-HistPage($pg, [string]$key, [string]$code, [string]$hint, [bool]$logBtn) {
    $pg.Controls.Clear()
    $W = $pg.Width
    $H = $pg.Height
    $mint = [Drawing.Color]::FromArgb(52, 211, 153)
 
    # ---------- แถบเครื่องมือ ----------
    $scan = New-Object GradButton
    $scan.Text = $script:histScanLabel
    $scan.C1 = [Drawing.Color]::FromArgb(109, 40, 217)
    $scan.C2 = [Drawing.Color]::FromArgb(34, 160, 110)
    $scan.Size = New-Object Drawing.Size(140, 38)
    $scan.Location = New-Object Drawing.Point(18, 36)
    $scan.Tag = $key
 
    $cbDays = New-Object DarkCombo
    foreach ($d in @('7 วัน', '30 วัน', '90 วัน', '365 วัน')) { $cbDays.Items.Add($d) }
    $cbDays.Selected = 1
    $cbDays.Size = New-Object Drawing.Size(104, 38)
    $cbDays.Location = New-Object Drawing.Point(170, 36)
 
    $cbCat = New-Object DarkCombo
    $cbCat.Items.Add('ทั้งหมด')
    $cbCat.Selected = 0
    $cbCat.Size = New-Object Drawing.Size(190, 38)
    $cbCat.Location = New-Object Drawing.Point(286, 36)
    $cbCat.Tag = $key
 
    $btnCsv = New-Object GradButton
    $btnCsv.Text = 'บันทึก CSV'
    $btnCsv.C1 = [Drawing.Color]::FromArgb(88, 32, 176)
    $btnCsv.C2 = [Drawing.Color]::FromArgb(124, 58, 237)
    $btnCsv.Size = New-Object Drawing.Size(120, 38)
    $btnCsv.Location = New-Object Drawing.Point(($W - 18 - 120), 36)
    $btnCsv.Tag = $key
 
    $btnCopy = New-Object GradButton
    $btnCopy.Text = 'คัดลอก'
    $btnCopy.C1 = [Drawing.Color]::FromArgb(70, 50, 120)
    $btnCopy.C2 = [Drawing.Color]::FromArgb(109, 40, 217)
    $btnCopy.Size = New-Object Drawing.Size(100, 38)
    $btnCopy.Location = New-Object Drawing.Point(($W - 18 - 120 - 10 - 100), 36)
    $btnCopy.Tag = $key
 
    $sx = 488
    $sbx = New-Object SearchBox
    $sbx.Placeholder = 'ค้นหาในผลลัพธ์...'
    $sbx.Box.Tag = $key
    $sbx.Location = New-Object Drawing.Point($sx, 36)
    $sbx.Size = New-Object Drawing.Size((($W - 18 - 120 - 10 - 100 - 12) - $sx), 38)
 
    $pg.Controls.AddRange(@($scan, $cbDays, $cbCat, $sbx, $btnCopy, $btnCsv))
 
    # ---------- คำอธิบาย (+ ปุ่มเปิดบันทึกคำสั่ง) ----------
    $lblH = New-Object Windows.Forms.Label
    $lblH.Text = $hint
    $lblH.Font = New-Object Drawing.Font('Segoe UI', 9)
    $lblH.ForeColor = $oLav
    $lblH.BackColor = [Drawing.Color]::Transparent
    $lblH.AutoSize = $false
    $hintW = $W - 36
    if ($logBtn) { $hintW = $W - 36 - 214 }
    $lblH.Size = New-Object Drawing.Size($hintW, 34)
    $lblH.Location = New-Object Drawing.Point(18, 80)
    $pg.Controls.Add($lblH)
 
    if ($logBtn) {
        $btnLog = New-Object GradButton
        $btnLog.Text = 'เปิดบันทึกคำสั่ง'
        $btnLog.C1 = [Drawing.Color]::FromArgb(22, 163, 74)
        $btnLog.C2 = $mint
        $btnLog.Size = New-Object Drawing.Size(200, 34)
        $btnLog.Location = New-Object Drawing.Point(($W - 18 - 200), 80)
        $btnLog.Add_Click({ Enable-CmdLogging })
        $pg.Controls.Add($btnLog)
    }
 
    # ---------- กล่องสรุป 4 ช่อง ----------
    $bw = [int](($W - 36 - 36) / 4)
    $bxTotal = New-HistBox 'TOTAL'     'รายการทั้งหมดที่สแกนได้' 18 $bw $oGreen
    $bxShow  = New-HistBox 'SHOWING'   'หลังกรอง / ค้นหา' (18 + ($bw + 12)) $bw $oViolet
    $bxTypes = New-HistBox 'CATEGORIES' 'ประเภทข้อมูลที่พบ' (18 + 2 * ($bw + 12)) $bw $mint
    $bxScan  = New-HistBox 'LAST SCAN' 'ยังไม่ได้สแกน' (18 + 3 * ($bw + 12)) $bw ([Drawing.Color]::FromArgb(196, 181, 253))
    foreach ($b in @($bxTotal, $bxShow, $bxTypes, $bxScan)) { $b.Value = '-' }
    $pg.Controls.AddRange(@($bxTotal, $bxShow, $bxTypes, $bxScan))
 
    # ---------- ตาราง ----------
    $grid = New-Object HistGrid
    $grid.Tag = $key
    $grid.EmptyText = 'กด "สแกน" เพื่อเริ่ม'
    $grid.Location = New-Object Drawing.Point(18, 202)
    $grid.Size = New-Object Drawing.Size(($W - 36), ($H - 202 - 44))
    $pg.Controls.Add($grid)
 
    # ---------- สถานะ ----------
    $st = New-Object Windows.Forms.Label
    $st.Text = 'พร้อมสแกน'
    $st.Font = New-Object Drawing.Font('Segoe UI', 9)
    $st.ForeColor = $oLav
    $st.BackColor = [Drawing.Color]::Transparent
    $st.AutoSize = $false
    $st.Size = New-Object Drawing.Size(($W - 36), 22)
    $st.Location = New-Object Drawing.Point(18, ($H - 34))
    $pg.Controls.Add($st)
 
    $script:histUi[$key] = @{
        Key = $key; Page = $pg; Grid = $grid; Cat = $cbCat; Days = $cbDays; Search = $sbx
        Scan = $scan; Status = $st; Code = $code; Busy = $false; Scanned = $false; Info = ''; DaysUsed = 30
        BxTotal = $bxTotal; BxShow = $bxShow; BxTypes = $bxTypes; BxScan = $bxScan
    }
 
    $scan.Add_Click({ param($s, $e) Start-HistScan ([string]$s.Tag) })
    $cbCat.Add_SelectedChanged({ param($s, $e) Apply-HistFilter $script:histUi[[string]$s.Tag] })
    $sbx.Box.Add_TextChanged({ param($s, $e) Apply-HistFilter $script:histUi[[string]$s.Tag] })
    $btnCsv.Add_Click({ param($s, $e) Export-HistCsv $script:histUi[[string]$s.Tag] })
    $btnCopy.Add_Click({ param($s, $e) Copy-HistRows $script:histUi[[string]$s.Tag] })
    $grid.Add_ViewChanged({ param($s, $e) Update-HistStats $script:histUi[[string]$s.Tag] })
    $grid.Add_RowActivated({
        param($s, $e)
        $r = $s.ActivatedRow
        if ($r) {
            try { [Windows.Forms.Clipboard]::SetText([string]$r.Detail) } catch { }
            $script:histUi[[string]$s.Tag].Status.Text = 'คัดลอกรายละเอียดของแถวที่เลือกแล้ว'
        }
    })
}
 
# ---------------------------------------------------------------------
#  สร้างหน้าใหม่ทับของเดิม (ตัวเปิดแท็บครั้งแรก = สแกนอัตโนมัติ ที่ผูกไว้เดิมยังใช้ได้)
# ---------------------------------------------------------------------
New-HistPage $script:pages[1][0] 'activity' $actCode ('รวมประวัติ: เปิด/ปิดเครื่อง, Sleep/Wake, ล็อกอิน, โปรแกรมที่เปิด (Prefetch / UserAssist), ไฟล์ที่เปิดล่าสุด และตรวจว่ามีการล้าง Event Log หรือไม่') $false
 
New-HistPage $script:pages[2][0] 'commands' $cmdCode ('PowerShell: ประวัติที่พิมพ์ (ไม่มีเวลา) + Script Block log | CMD ไม่เก็บประวัติลงดิสก์ จะเห็นผ่าน Process Log (Event 4688) เมื่อเปิดบันทึกไว้ | Win+R และเครื่องมือ CLI ที่เคยเปิด') $true
# =====================================================================
#  APP HUB  -  คลังแอปที่ผู้ใช้เพิ่มเอง (เก็บใน %APPDATA%\FlowSkipper\apps.json)
# =====================================================================
$csHub = @'
using System;
using System.IO;
using System.Net;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using System.Threading;
 
public class Dl
{
    public volatile bool Done;
    public volatile bool Failed;
    public long Total = -1;
    public long Got;
    public string Path = "";
    public string Error = "";
    public string Expect = "";
    volatile bool stop;
 
    static Dl() { try { ServicePointManager.SecurityProtocol |= (SecurityProtocolType)3072; } catch { } }
 
    public void Start(string url, string dir)
    {
        Thread t = new Thread(delegate() { Run(url, dir); });
        t.IsBackground = true;
        t.Start();
    }
    static string Fix(string u)
{
    Match g = Regex.Match(u, @"drive\.google\.com/file/d/([^/?]+)");
    if (g.Success) return "https://drive.usercontent.google.com/download?id=" + g.Groups[1].Value + "&export=download&confirm=t";
    g = Regex.Match(u, @"drive\.google\.com/(?:open|uc)\?(?:.*&)?id=([^&]+)");
    if (g.Success) return "https://drive.usercontent.google.com/download?id=" + g.Groups[1].Value + "&export=download&confirm=t";
    if (u.Contains("dropbox.com"))
        return Regex.Replace(u, @"([?&])dl=0", "$1dl=1");
    return u;
}
 
    public void Cancel() { stop = true; }
    static WebResponse OpenDownload(string url)
    {
        HttpWebRequest r = (HttpWebRequest)WebRequest.Create(url);
        r.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36";
        r.Proxy = null;
        r.AllowAutoRedirect = true;
        r.Timeout = 30000;
        r.ReadWriteTimeout = 30000;
        return r.GetResponse();
    }
 
    static string Safe(string n)
    {
        foreach (char c in System.IO.Path.GetInvalidFileNameChars()) n = n.Replace(c, '_');
        return n.Trim();
    }
    
 
        void Run(string url, string dir)
    {
        string part = null;
        try
        {
            Directory.CreateDirectory(dir);
            using (WebResponse resp = OpenDownload(Fix(url)))
{
    string ct = resp.ContentType == null ? "" : resp.ContentType.ToLowerInvariant();
    if (ct.StartsWith("text/html"))
    {
        Error = "ลิงก์นี้เป็นหน้าเว็บ ไม่ใช่ไฟล์ดาวน์โหลดตรง ให้ใช้ลิงก์ที่กดแล้วเริ่มโหลดทันที";
        Failed = true;
        return;
    }
                Total = resp.ContentLength;
                string name = "";
                string cd = resp.Headers["Content-Disposition"];
                if (cd != null)
                {
                    Match m = Regex.Match(cd, "filename\\*?=(?:UTF-8'')?\"?([^\";]+)");
                    if (m.Success) name = Uri.UnescapeDataString(m.Groups[1].Value);
                }
                if (name.Length == 0)
                {
                    string[] seg = resp.ResponseUri.Segments;
                    name = Uri.UnescapeDataString(seg[seg.Length - 1].Trim('/'));
                }
                name = Safe(name);
                if (name.Length == 0 || name.IndexOf('.') < 0) name = "download.bin";

                string path = System.IO.Path.Combine(dir, name);
                int i = 1;
                while (File.Exists(path))
                {
                    path = System.IO.Path.Combine(dir, System.IO.Path.GetFileNameWithoutExtension(name) + " (" + i + ")" + System.IO.Path.GetExtension(name));
                    i++;
                }
                part = path + ".part";

                using (Stream s = resp.GetResponseStream())
                using (FileStream fs = new FileStream(part, FileMode.Create, FileAccess.Write))
                {
                    byte[] buf = new byte[81920];
                    int n;
                    while (!stop && (n = s.Read(buf, 0, buf.Length)) > 0) { fs.Write(buf, 0, n); Got += n; }
                }
                if (stop) { Error = "ยกเลิก"; Failed = true; try { File.Delete(part); } catch { } return; }

                File.Move(part, path);
                part = null;

                if (Expect.Length > 0)
                {
                    string h;
                    using (SHA256 sha = SHA256.Create())
                    using (FileStream f = File.OpenRead(path))
                        h = BitConverter.ToString(sha.ComputeHash(f)).Replace("-", "");
                    if (!h.Equals(Expect.Replace(" ", "").Replace("-", ""), StringComparison.OrdinalIgnoreCase))
                    {
                        try { File.Delete(path); } catch { }
                        Error = "SHA256 ไม่ตรง ไฟล์อาจเสียหรือถูกแก้ไข จึงลบทิ้งให้แล้ว";
                        Failed = true;
                        return;
                    }
                }
                Path = path;
            }
            Done = true;
        }
        catch (Exception ex)
        {
            Error = ex.Message;
            Failed = true;
            if (part != null) { try { File.Delete(part); } catch { } }
        }
    }
}
'@
Add-Type -TypeDefinition $csHub -Language CSharp -ErrorAction Stop
 
$script:hubLocal  = Join-Path $script:cfgDir 'apps.json'
$script:hubShared = ''
if ($env:BATDIR) { $script:hubShared = Join-Path $env:BATDIR 'apps.json' }
$script:hubDir    = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads\FamHub'
$script:hubList   = @()
$script:hubJobs   = @{}
$script:hubUi     = @{}
$script:hubQuery  = ''
$script:hubPanel  = $null
$script:hubImgs   = New-Object System.Collections.ArrayList
$script:hubNewIcon = $null
$script:hubIconPrev = $null
$script:hubTip    = New-Object Windows.Forms.ToolTip
 
# ---------- อ่าน/เขียนรายการ (แก้บั๊กอาร์เรย์ซ้อน) ----------
function Add-HubItems($o, $acc) {
    if ($null -eq $o) { return }
    if ($o -is [System.Array]) {
        foreach ($i in $o) { Add-HubItems $i $acc }
        return
    }
    if ($o.PSObject.Properties['url'] -and [string]$o.url) { [void]$acc.Add($o) }
}
 
function Read-HubFile([string]$path) {
    $acc = New-Object System.Collections.ArrayList
    try {
        if ($path -and (Test-Path -LiteralPath $path)) {
            $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
            if ($raw -and $raw.Trim()) {
                $parsed = ConvertFrom-Json -InputObject $raw
                Add-HubItems $parsed $acc
            }
        }
    } catch { }
    return ,$acc
}
 
function Load-Hub {
    $all = New-Object System.Collections.ArrayList
    $seen = @{}
    foreach ($p in @($script:hubShared, $script:hubLocal)) {
        $items = Read-HubFile $p
        foreach ($a in $items) {
            $u = [string]$a.url
            if ($seen.ContainsKey($u)) { continue }
            $seen[$u] = 1
            [void]$all.Add($a)
        }
    }
    $script:hubList = @($all)
}
 
function ConvertTo-HubJson($items) {
    $parts = New-Object System.Collections.ArrayList
    foreach ($a in $items) { [void]$parts.Add((ConvertTo-Json -InputObject $a -Depth 5)) }
    return ('[' + ($parts -join ',') + ']')
}
 
function Save-Hub {
    if (-not $script:isAdmin) { return }
    $json = ConvertTo-HubJson $script:hubList
    $enc = New-Object Text.UTF8Encoding $false
    $paths = @($script:hubLocal)
    if ($script:hubShared) { $paths += $script:hubShared }
    foreach ($p in $paths) {
        try {
            $d = Split-Path -Parent $p
            if ($d -and -not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }
            [IO.File]::WriteAllText($p, $json, $enc)
        } catch {
            try { [IO.File]::WriteAllText((Join-Path $env:TEMP 'flow_hub_error.txt'), ($p + "`r`n" + ($_ | Out-String))) } catch { }
        }
    }
}
 
# ---------- รูปไอคอน (ย่อเป็น 96x96 PNG แล้วฝังเป็น base64 ในไฟล์ json) ----------
function New-ImageCopy([byte[]]$bytes) {
    $ms = New-Object IO.MemoryStream(, $bytes)
    try {
        $img = [Drawing.Image]::FromStream($ms)
        try { return (New-Object Drawing.Bitmap($img)) } finally { $img.Dispose() }
    } finally { $ms.Dispose() }
}
 
function ConvertTo-IconB64([string]$path) {
    $src = New-ImageCopy ([IO.File]::ReadAllBytes($path))
    try {
        $sz = 96
        $bmp = New-Object Drawing.Bitmap($sz, $sz, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [Drawing.Graphics]::FromImage($bmp)
        try {
            $g.Clear([Drawing.Color]::Transparent)
            $g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::HighQuality
            $g.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $s = [Math]::Min($sz / [double]$src.Width, $sz / [double]$src.Height)
            $w = [int][Math]::Max(1, [Math]::Round($src.Width * $s))
            $h = [int][Math]::Max(1, [Math]::Round($src.Height * $s))
            $g.DrawImage($src, [int](($sz - $w) / 2), [int](($sz - $h) / 2), $w, $h)
        } finally { $g.Dispose() }
        $ms = New-Object IO.MemoryStream
        try {
            $bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png)
            return [Convert]::ToBase64String($ms.ToArray())
        } finally { $ms.Dispose(); $bmp.Dispose() }
    } finally { $src.Dispose() }
}
 
function ConvertFrom-IconB64([string]$b64) {
    if (-not $b64) { return $null }
    try { return (New-ImageCopy ([Convert]::FromBase64String($b64))) } catch { return $null }
}
 
function Select-IconFile {
    $ofd = New-Object Windows.Forms.OpenFileDialog
    $ofd.Title = 'เลือกรูปไอคอนแอป'
    $ofd.Filter = 'รูปภาพ (*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.ico)|*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.ico'
    if ($ofd.ShowDialog() -eq 'OK') { return $ofd.FileName }
    return $null
}
 
function Format-Mb([double]$b) { return ('{0:N1} MB' -f ($b / 1048576.0)) }
 
# ---------- ปุ่มต่าง ๆ ของการ์ด ----------
function Hub-Click([string]$url) {
    $j = $script:hubJobs[$url]
    if ($j) {
        if ($j.Dl.Done) {
            try { Start-Process explorer.exe ('/select,"' + $j.Dl.Path + '"') } catch { }
            return
        }
        $j.Dl.Cancel()
        return
    }
    $uri = $null
    if (-not [Uri]::TryCreate($url, [UriKind]::Absolute, [ref]$uri) -or ($uri.Scheme -ne 'https' -and $uri.Scheme -ne 'http')) {
        [Windows.Forms.MessageBox]::Show('ลิงก์ต้องขึ้นต้นด้วย http:// หรือ https://', 'App Hub') | Out-Null
        return
    }
    $a = $script:hubList | Where-Object { [string]$_.url -eq $url } | Select-Object -First 1
    $d = New-Object Dl
    if ($a -and $a.sha256) { $d.Expect = [string]$a.sha256 }
    $script:hubJobs[$url] = @{ Dl = $d }
    $ui = $script:hubUi[$url]
    if ($ui) { $ui.Bar.Value = 0; $ui.Bar.Visible = $true; $ui.Btn.Text = 'กำลังเชื่อมต่อ...' }
    $d.Start($url, $script:hubDir)
}
 
function Hub-Remove([string]$url) {
    if (-not $script:isAdmin) { return }
    if ([Windows.Forms.MessageBox]::Show('ลบแอปนี้ออกจากรายการ? (ไฟล์ที่ดาวน์โหลดไว้แล้วจะไม่ถูกลบ)', 'App Hub', 'YesNo', 'Question') -ne 'Yes') { return }
    $j = $script:hubJobs[$url]
    if ($j -and -not $j.Dl.Done) { $j.Dl.Cancel() }
    $script:hubJobs.Remove($url)
    $script:hubList = @($script:hubList | Where-Object { [string]$_.url -ne $url })
    Save-Hub
    Render-Hub
}
 
function Hub-SetIcon([string]$url) {
    if (-not $script:isAdmin) { return }
    $fp = Select-IconFile
    if (-not $fp) { return }
    $b = $null
    try { $b = ConvertTo-IconB64 $fp } catch {
        [Windows.Forms.MessageBox]::Show(('อ่านรูปไม่สำเร็จ: ' + $_.Exception.Message), 'App Hub') | Out-Null
        return
    }
    foreach ($a in $script:hubList) {
        if ([string]$a.url -eq $url) {
            if ($a.PSObject.Properties['icon']) { $a.icon = $b }
            else { Add-Member -InputObject $a -NotePropertyName icon -NotePropertyValue $b }
        }
    }
    Save-Hub
    Render-Hub
}
 
# ---------- วาดรายการแอป ----------
function Render-Hub {
    $p = $script:hubPanel
    if ($null -eq $p) { return }
    $p.SuspendLayout()
    $p.AutoScrollPosition = New-Object Drawing.Point(0, 0)
    foreach ($c in @($p.Controls)) { $p.Controls.Remove($c); $c.Dispose() }
    foreach ($im in @($script:hubImgs)) { try { $im.Dispose() } catch { } }
    $script:hubImgs.Clear()
    $script:hubUi = @{}
 
    $q = $script:hubQuery.ToLowerInvariant()
    $w = $p.ClientSize.Width - 8 - [Windows.Forms.SystemInformation]::VerticalScrollBarWidth
    $y = 8
    $n = 0
    foreach ($a in $script:hubList) {
        $hay = (([string]$a.name) + ' ' + ([string]$a.description) + ' ' + (@($a.tags) -join ' ')).ToLowerInvariant()
        if ($q -and $hay.IndexOf($q) -lt 0) { continue }
        $n++
        $url = [string]$a.url
        $nm = [string]$a.name
 
        $card = New-Object Card
        $card.BackColor = [Drawing.Color]::Transparent
        $card.Size = New-Object Drawing.Size($w, 84)
        $card.Location = New-Object Drawing.Point(8, $y)
 
        $lg = New-Object Logo
        $ch = '?'
        if ($nm) { $ch = $nm.Substring(0, 1).ToUpper() }
        $lg.Text = $ch
        $lg.Size = New-Object Drawing.Size(52, 52)
        $lg.Location = New-Object Drawing.Point(14, 16)
        if ($a.PSObject.Properties['icon'] -and $a.icon) {
            $im = ConvertFrom-IconB64 ([string]$a.icon)
            if ($im) { [void]$script:hubImgs.Add($im); $lg.Img = $im }
        }
        if ($script:isAdmin) {
            $lg.Cursor = [Windows.Forms.Cursors]::Hand
            $lg.Tag = $url
            $lg.Add_Click({ param($s, $e) Hub-SetIcon ([string]$s.Tag) })
            $script:hubTip.SetToolTip($lg, 'คลิกเพื่อเปลี่ยนรูปไอคอน')
        }
 
        $lbN = New-Object Windows.Forms.Label
        $lbN.Text = $nm
        $lbN.Font = New-Object Drawing.Font('ไอติม', 12.5)
        $lbN.ForeColor = $cWhite
        $lbN.BackColor = $cCard
        $lbN.AutoSize = $false
        $lbN.AutoEllipsis = $true
        $lbN.Size = New-Object Drawing.Size(($w - 80 - 200), 24)
        $lbN.Location = New-Object Drawing.Point(80, 8)
 
        $meta = @()
        $ver = [string]$a.version
        if ($ver) {
            if ($ver -notmatch '^[vV]') { $ver = 'v' + $ver }
            $meta += $ver
        }
        if ($a.size) { $meta += [string]$a.size }
        foreach ($t in @($a.tags)) { if ($t) { $meta += [string]$t } }
        $lbM = New-Object Windows.Forms.Label
        $lbM.Text = ($meta -join '  ·  ')
        $lbM.Font = New-Object Drawing.Font('Segoe UI', 8.5, [Drawing.FontStyle]::Bold)
        $lbM.ForeColor = $tViolet
        $lbM.BackColor = $cCard
        $lbM.AutoSize = $false
        $lbM.AutoEllipsis = $true
        $lbM.Size = New-Object Drawing.Size(($w - 80 - 200), 18)
        $lbM.Location = New-Object Drawing.Point(80, 34)
 
        $lbD = New-Object Windows.Forms.Label
        $lbD.Text = [string]$a.description
        $lbD.Font = New-Object Drawing.Font('Segoe UI', 8.5)
        $lbD.ForeColor = $cOff
        $lbD.BackColor = $cCard
        $lbD.AutoSize = $false
        $lbD.AutoEllipsis = $true
        $lbD.Size = New-Object Drawing.Size(($w - 80 - 200), 18)
        $lbD.Location = New-Object Drawing.Point(80, 56)
 
        $btn = New-Object GradButton
        $btn.Text = 'ดาวน์โหลด'
        $btn.C1 = [Drawing.Color]::FromArgb(109, 40, 217)
        $btn.C2 = [Drawing.Color]::FromArgb(34, 160, 110)
        $btn.Size = New-Object Drawing.Size(150, 36)
        $btn.Location = New-Object Drawing.Point(($w - 176), 16)
        $btn.Tag = $url
        $btn.Add_Click({ param($s, $e) Hub-Click ([string]$s.Tag) })
 
        $bar = New-Object GradBar
        $bar.BackColor = $cCard
        $bar.Size = New-Object Drawing.Size(150, 8)
        $bar.Location = New-Object Drawing.Point(($w - 176), 60)
        $bar.Visible = $false
 
        $j = $script:hubJobs[$url]
        if ($j) {
            $bar.Visible = $true
            if ($j.Dl.Done) { $btn.Text = 'แสดงไฟล์'; $bar.Value = 100 } else { $btn.Text = 'กำลังโหลด...' }
        }
 
        $card.Controls.AddRange(@($lg, $lbN, $lbM, $lbD, $btn, $bar))
 
        # ปุ่มลบ (✕) เห็นเฉพาะแอดมิน
        if ($script:isAdmin) {
            $del = New-Object Windows.Forms.Label
            $del.Text = [string][char]0x2715
            $del.Font = New-Object Drawing.Font('Segoe UI Symbol', 9)
            $del.ForeColor = $cOff
            $del.BackColor = $cCard
            $del.TextAlign = 'MiddleCenter'
            $del.Cursor = [Windows.Forms.Cursors]::Hand
            $del.Size = New-Object Drawing.Size(20, 20)
            $del.Location = New-Object Drawing.Point(($w - 24), 4)
            $del.Tag = $url
            $del.Add_Click({ param($s, $e) Hub-Remove ([string]$s.Tag) })
            $card.Controls.Add($del)
        }
 
        $p.Controls.Add($card)
        $script:hubUi[$url] = @{ Btn = $btn; Bar = $bar }
        $y += 94
    }
 
    if ($n -eq 0) {
        $em = New-Object Windows.Forms.Label
        if ($script:hubList.Count -eq 0) {
            if ($script:isAdmin) { $em.Text = 'ยังไม่มีแอปในรายการ กด "+ เพิ่มแอป" เพื่อเริ่ม' } else { $em.Text = 'ยังไม่มีแอปในรายการ' }
        } else { $em.Text = 'ไม่พบแอปที่ตรงกับคำค้นหา' }
        $em.Font = New-Object Drawing.Font('ไอติม', 11)
        $em.ForeColor = $oLav
        $em.BackColor = [Drawing.Color]::Transparent
        $em.TextAlign = 'MiddleCenter'
        $em.Size = New-Object Drawing.Size($w, 60)
        $em.Location = New-Object Drawing.Point(8, 40)
        $p.Controls.Add($em)
    }
    $p.ResumeLayout()
}
 
# ---------- หน้าต่างเพิ่มแอป (แอดมินเท่านั้น) ----------
function Show-HubAdd {
    if (-not $script:isAdmin) { return }
    $script:hubNewIcon = $null
 
    $f = New-Object GradForm
    $f.Radius = 14
    $f.BgA = [Drawing.Color]::FromArgb(9, 5, 20)
    $f.BgB = [Drawing.Color]::FromArgb(36, 15, 70)
    $f.Glows = $false
    $f.Text = 'Add app'
    $f.ClientSize = New-Object Drawing.Size(460, 620)
    $f.StartPosition = 'CenterScreen'
    $f.KeyPreview = $true
    $f.Font = New-Object Drawing.Font('Segoe UI', 10)
 
    $ft = New-Object Windows.Forms.Label
    $ft.Text = 'เพิ่มแอปเข้าคลัง'
    $ft.Font = New-Object Drawing.Font('ไอติม', 16, [Drawing.FontStyle]::Bold)
    $ft.ForeColor = $cWhite
    $ft.BackColor = [Drawing.Color]::Transparent
    $ft.AutoSize = $true
    $ft.Location = New-Object Drawing.Point(24, 18)
    $ft.Add_MouseDown({ [Gfx]::Drag($f.Handle) })
 
    $fx = New-Object Windows.Forms.Label
    $fx.Text = [string][char]0x2715
    $fx.Font = New-Object Drawing.Font('Segoe UI Symbol', 12)
    $fx.ForeColor = $cLav
    $fx.BackColor = [Drawing.Color]::Transparent
    $fx.Cursor = [Windows.Forms.Cursors]::Hand
    $fx.Size = New-Object Drawing.Size(32, 32)
    $fx.TextAlign = 'MiddleCenter'
    $fx.Location = New-Object Drawing.Point(412, 14)
    $fx.Add_Click({ $f.Close() })
    $f.Controls.AddRange(@($ft, $fx))
 
    # --- ไอคอนแอป ---
    $script:hubIconPrev = New-Object Logo
    $script:hubIconPrev.Text = '+'
    $script:hubIconPrev.Size = New-Object Drawing.Size(56, 56)
    $script:hubIconPrev.Location = New-Object Drawing.Point(24, 62)
 
    $pick = New-Object GradButton
    $pick.Text = 'เลือกรูปไอคอน (ไม่บังคับ)'
    $pick.C1 = [Drawing.Color]::FromArgb(88, 32, 176)
    $pick.C2 = [Drawing.Color]::FromArgb(124, 58, 237)
    $pick.Size = New-Object Drawing.Size(250, 38)
    $pick.Location = New-Object Drawing.Point(96, 66)
    $pick.Add_Click({
        $fp = Select-IconFile
        if (-not $fp) { return }
        try {
            $b = ConvertTo-IconB64 $fp
            $im = ConvertFrom-IconB64 $b
            if ($im) {
                $script:hubNewIcon = $b
                if ($script:hubIconPrev.Img) { $script:hubIconPrev.Img.Dispose() }
                $script:hubIconPrev.Img = $im
                $script:hubIconPrev.Invalidate()
            }
        } catch {
            [Windows.Forms.MessageBox]::Show(('อ่านรูปไม่สำเร็จ: ' + $_.Exception.Message), 'App Hub') | Out-Null
        }
    })
 
    $pn = New-Object Windows.Forms.Label
    $pn.Text = 'รองรับ PNG / JPG / BMP / GIF / ICO (ย่อเป็นสี่เหลี่ยมจัตุรัสให้อัตโนมัติ)'
    $pn.Font = New-Object Drawing.Font('Segoe UI', 8)
    $pn.ForeColor = $oLav
    $pn.BackColor = [Drawing.Color]::Transparent
    $pn.AutoSize = $true
    $pn.Location = New-Object Drawing.Point(96, 108)
    $f.Controls.AddRange(@($script:hubIconPrev, $pick, $pn))
 
    $fields = @(
        @('name', 'ชื่อแอป *'),
        @('url', 'ลิงก์ดาวน์โหลด (https://...) *'),
        @('version', 'เวอร์ชัน'),
        @('size', 'ขนาด (เช่น 120 MB)'),
        @('tags', 'แท็ก (คั่นด้วยจุลภาค เช่น Windows, เครื่องมือ)'),
        @('description', 'คำอธิบายสั้น ๆ'),
        @('sha256', 'SHA256 ของไฟล์ (ไม่บังคับ ใช้ตรวจว่าไฟล์ไม่ถูกแก้)')
    )
    $tbs = @{}
    $y = 140
    foreach ($fd in $fields) {
        $l = New-Object Windows.Forms.Label
        $l.Text = $fd[1]
        $l.Font = New-Object Drawing.Font('Segoe UI', 8.5)
        $l.ForeColor = $oLav
        $l.BackColor = [Drawing.Color]::Transparent
        $l.AutoSize = $true
        $l.Location = New-Object Drawing.Point(24, $y)
        $t = New-Object Windows.Forms.TextBox
        $t.BorderStyle = 'FixedSingle'
        $t.BackColor = [Drawing.Color]::FromArgb(22, 17, 38)
        $t.ForeColor = [Drawing.Color]::White
        $t.Font = New-Object Drawing.Font('Segoe UI', 10)
        $t.Size = New-Object Drawing.Size(412, 26)
        $t.Location = New-Object Drawing.Point(24, ($y + 20))
        $f.Controls.AddRange(@($l, $t))
        $tbs[$fd[0]] = $t
        $y += 58
    }
 
    $ok = New-Object GradButton
    $ok.Text = 'บันทึก'
    $ok.C1 = [Drawing.Color]::FromArgb(109, 40, 217)
    $ok.C2 = [Drawing.Color]::FromArgb(34, 160, 110)
    $ok.Size = New-Object Drawing.Size(412, 44)
    $ok.Location = New-Object Drawing.Point(24, ($y + 6))
    $ok.Add_Click({
        $nm = $tbs['name'].Text.Trim()
        $ur = $tbs['url'].Text.Trim()
        $u = $null
        if (-not $nm) { [Windows.Forms.MessageBox]::Show('กรุณาใส่ชื่อแอป', 'App Hub') | Out-Null; return }
        if (-not [Uri]::TryCreate($ur, [UriKind]::Absolute, [ref]$u) -or ($u.Scheme -ne 'https' -and $u.Scheme -ne 'http')) {
            [Windows.Forms.MessageBox]::Show('ลิงก์ต้องขึ้นต้นด้วย http:// หรือ https://', 'App Hub') | Out-Null
            return
        }
        if (@($script:hubList | Where-Object { [string]$_.url -eq $ur }).Count -gt 0) {
            [Windows.Forms.MessageBox]::Show('มีแอปที่ใช้ลิงก์นี้อยู่แล้วในรายการ', 'App Hub') | Out-Null
            return
        }
        $tags = @($tbs['tags'].Text.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $obj = [pscustomobject]@{
            name = $nm; url = $ur; version = $tbs['version'].Text.Trim(); size = $tbs['size'].Text.Trim()
            tags = $tags; description = $tbs['description'].Text.Trim(); sha256 = $tbs['sha256'].Text.Trim()
            icon = [string]$script:hubNewIcon
        }
        $script:hubList = @($script:hubList) + $obj
        Save-Hub
        Render-Hub
        $f.Close()
    })
    $f.Controls.Add($ok)
    $f.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq 'Escape') { $f.Close() } })
    $f.Add_FormClosed({
        try { if ($script:hubIconPrev -and $script:hubIconPrev.Img) { $script:hubIconPrev.Img.Dispose(); $script:hubIconPrev.Img = $null } } catch { }
    })
    [void]$f.ShowDialog()
}
 
# ---------- สร้างหน้า ----------
$hp = $script:pages[3][0]
$hp.Controls.Clear()
$hW = $hp.Width
$hH = $hp.Height
 
$script:hubSearch = New-Object SearchBox
$script:hubSearch.Placeholder = 'ค้นหาแอป...'
$script:hubSearch.Box.Add_TextChanged({ $script:hubQuery = $script:hubSearch.Box.Text.Trim(); Render-Hub })
 
$hubCtrls = New-Object System.Collections.ArrayList
 
if ($script:isAdmin) {
    # ---- แถบเมนูแอดมิน ----
    $hAdd = New-Object GradButton
    $hAdd.Text = '+ เพิ่มแอป'
    $hAdd.C1 = [Drawing.Color]::FromArgb(109, 40, 217)
    $hAdd.C2 = [Drawing.Color]::FromArgb(34, 160, 110)
    $hAdd.Size = New-Object Drawing.Size(130, 38)
    $hAdd.Location = New-Object Drawing.Point(18, 36)
    $hAdd.Add_Click({ Show-HubAdd })
 
    $hFold = New-Object GradButton
    $hFold.Text = 'เปิดโฟลเดอร์ดาวน์โหลด'
    $hFold.C1 = [Drawing.Color]::FromArgb(88, 32, 176)
    $hFold.C2 = [Drawing.Color]::FromArgb(124, 58, 237)
    $hFold.Size = New-Object Drawing.Size(210, 38)
    $hFold.Location = New-Object Drawing.Point(158, 36)
    $hFold.Add_Click({
        try { [void](New-Item -ItemType Directory -Path $script:hubDir -Force); Start-Process explorer.exe ('"' + $script:hubDir + '"') } catch { }
    })
 
    $hRel = New-Object GradButton
    $hRel.Text = 'โหลดรายการใหม่'
    $hRel.C1 = [Drawing.Color]::FromArgb(70, 50, 120)
    $hRel.C2 = [Drawing.Color]::FromArgb(109, 40, 217)
    $hRel.Size = New-Object Drawing.Size(150, 38)
    $hRel.Location = New-Object Drawing.Point(378, 36)
    $hRel.Add_Click({ Load-Hub; Render-Hub })
 
    [void]$hubCtrls.AddRange(@($hAdd, $hFold, $hRel))
    $script:hubSearch.Location = New-Object Drawing.Point(540, 36)
    $script:hubSearch.Size = New-Object Drawing.Size(($hW - 18 - 540), 38)
    $hubTop = 90
} else {
    # ---- ผู้ใช้ทั่วไป: เห็นแค่ช่องค้นหา ----
    $script:hubSearch.Location = New-Object Drawing.Point(18, 36)
    $script:hubSearch.Size = New-Object Drawing.Size(($hW - 36), 38)
    $hubTop = 90
}
[void]$hubCtrls.Add($script:hubSearch)
 
$script:hubPanel = New-Object Windows.Forms.Panel
$script:hubPanel.AutoScroll = $true
$script:hubPanel.BackColor = [Drawing.Color]::FromArgb(15, 9, 33)
$script:hubPanel.Location = New-Object Drawing.Point(18, $hubTop)
$script:hubPanel.Size = New-Object Drawing.Size(($hW - 36), ($hH - $hubTop - 18))
[void]$hubCtrls.Add($script:hubPanel)
 
$hp.Controls.AddRange(@($hubCtrls))
 
$script:hubTm = New-Object Windows.Forms.Timer
$script:hubTm.Interval = 250
$script:hubTm.Add_Tick({
    foreach ($u in @($script:hubJobs.Keys)) {
        $j = $script:hubJobs[$u]
        $d = $j.Dl
        $ui = $script:hubUi[$u]
        if ($d.Failed) {
            $script:hubJobs.Remove($u)
            if ($ui -and -not $ui.Btn.IsDisposed) { $ui.Btn.Text = 'ดาวน์โหลด'; $ui.Bar.Visible = $false }
            if ($d.Error -ne 'ยกเลิก') { [Windows.Forms.MessageBox]::Show(('ดาวน์โหลดไม่สำเร็จ: ' + $d.Error), 'App Hub') | Out-Null }
            continue
        }
        if (-not $ui -or $ui.Btn.IsDisposed) { continue }
        if ($d.Done) { $ui.Bar.Value = 100; $ui.Btn.Text = 'แสดงไฟล์'; continue }
        if ($d.Total -gt 0) {
            $pc = [int][Math]::Min(100, $d.Got * 100 / $d.Total)
            $ui.Bar.Value = $pc
            $ui.Btn.Text = ([string]$pc + '%  ·  ยกเลิก')
        } else {
            $ui.Btn.Text = ((Format-Mb $d.Got) + '  ·  ยกเลิก')
        }
    }
})
$script:hubTm.Start()
$form.Add_FormClosed({ try { $script:hubTm.Stop(); $script:hubTm.Dispose() } catch { } })
 
Load-Hub
Render-Hub
# =====================================================================
#  CROSSHAIR  -  เป้ากลางจอ (หน้าต่างโปร่งใส คลิกทะลุได้ อยู่บนสุดเสมอ)
# =====================================================================
$cs6 = @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

public static class XH
{
    public static void Draw(Graphics g, int ix, int iy, Color c, int t, int arm, int gap, bool outline)
    {
        g.SmoothingMode = SmoothingMode.None;
        int half = t / 2;
        List<Rectangle> rs = new List<Rectangle>();
        rs.Add(new Rectangle(ix - half - gap - arm, iy - half, arm, t));
        rs.Add(new Rectangle(ix - half + t + gap, iy - half, arm, t));
        rs.Add(new Rectangle(ix - half, iy - half - gap - arm, t, arm));
        rs.Add(new Rectangle(ix - half, iy - half + t + gap, t, arm));
        if (gap == 0) rs.Add(new Rectangle(ix - half, iy - half, t, t));
        if (outline)
        {
            using (SolidBrush ob = new SolidBrush(Color.Black))
            {
                foreach (Rectangle r in rs)
                {
                    Rectangle o = r;
                    o.Inflate(1, 1);
                    g.FillRectangle(ob, o);
                }
            }
        }
        using (SolidBrush b = new SolidBrush(c))
        {
            foreach (Rectangle r in rs) g.FillRectangle(b, r);
        }
    }
}

public class CrossOverlay : Form
{
    public Color Col = Color.FromArgb(255, 105, 180);
    public int Thick = 2;
    public int Arm = 12;
    public int Gap = 4;
    public bool Outline = true;
    static Color Key = Color.FromArgb(1, 2, 3);

    public CrossOverlay()
    {
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        TopMost = true;
        BackColor = Key;
        TransparencyKey = Key;
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer, true);
    }

    protected override bool ShowWithoutActivation { get { return true; } }

    protected override CreateParams CreateParams
    {
        get
        {
            CreateParams cp = base.CreateParams;
            cp.ExStyle |= 0x80000 | 0x20 | 0x80 | 0x08000000 | 0x8;   // LAYERED | TRANSPARENT(คลิกทะลุ) | TOOLWINDOW | NOACTIVATE | TOPMOST
            return cp;
        }
    }

    public void Place()
    {
        int ext = Gap + Arm + Thick + 3;
        int s = ext * 2;
        Rectangle b = Screen.PrimaryScreen.Bounds;
        Bounds = new Rectangle(b.X + (b.Width - s) / 2, b.Y + (b.Height - s) / 2, s, s);
        Invalidate();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.Clear(Key);
        XH.Draw(e.Graphics, Width / 2, Height / 2, Col, Thick, Arm, Gap, Outline);
    }
}

public class XhPreview : Control
{
    public Color Col = Color.FromArgb(255, 105, 180);
    public int Thick = 2;
    public int Arm = 12;
    public int Gap = 4;
    public bool Outline = true;

    public XhPreview()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
    }

    static GraphicsPath Rnd(Rectangle r, int rad)
    {
        int d = Math.Max(1, rad * 2);
        GraphicsPath p = new GraphicsPath();
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.Clear(Color.FromArgb(24, 13, 50));
        if (Width < 60 || Height < 60) return;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        Rectangle r = new Rectangle(0, 0, Width - 1, Height - 1);
        using (GraphicsPath p = Rnd(r, 14))
        {
            using (LinearGradientBrush lb = new LinearGradientBrush(r, Color.FromArgb(18, 12, 38), Color.FromArgb(34, 22, 66), 60f))
                g.FillPath(lb, p);
            g.SetClip(p);
            using (Pen gp = new Pen(Color.FromArgb(22, 255, 255, 255), 1f))
            {
                for (int x = 0; x < Width; x += 24) g.DrawLine(gp, x, 0, x, Height);
                for (int y = 0; y < Height; y += 24) g.DrawLine(gp, 0, y, Width, y);
            }
            int ext = Gap + Arm + Thick + 3;
            int sc = (ext * 4 <= Math.Min(Width, Height) - 16) ? 2 : 1;
            g.TranslateTransform((float)(Width / 2), (float)(Height / 2));
            g.ScaleTransform(sc, sc);
            XH.Draw(g, 0, 0, Col, Thick, Arm, Gap, Outline);
            g.ResetTransform();
            g.SmoothingMode = SmoothingMode.AntiAlias;
            TextRenderer.DrawText(g, "PREVIEW  x" + sc, new Font("Segoe UI", 7.5f, FontStyle.Bold), new Point(14, 10), Color.FromArgb(120, 110, 165));
            g.ResetClip();
            using (Pen pen = new Pen(Color.FromArgb(120, 140, 100, 225), 1.2f)) g.DrawPath(pen, p);
        }
    }
}

public class NeonSlider : Control
{
    public int Min = 0;
    public int Max = 10;
    public Color C1 = Color.FromArgb(139, 92, 246);
    public Color C2 = Color.FromArgb(74, 222, 128);
    int val;
    bool drag;
    public event EventHandler ValueChanged;

    public NeonSlider()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        Height = 28;
        Cursor = Cursors.Hand;
        BackColor = Color.FromArgb(24, 13, 50);
    }

    public int Value
    {
        get { return val; }
        set
        {
            int v = Math.Max(Min, Math.Min(Max, value));
            if (v == val) return;
            val = v;
            Invalidate();
            if (ValueChanged != null) ValueChanged(this, EventArgs.Empty);
        }
    }

    void SetFromX(int x)
    {
        float l = 12f, r = Width - 12f;
        float t = (x - l) / (r - l);
        if (t < 0f) t = 0f;
        if (t > 1f) t = 1f;
        Value = Min + (int)Math.Round(t * (Max - Min));
    }

    protected override void OnMouseDown(MouseEventArgs e) { if (e.Button == MouseButtons.Left) { drag = true; SetFromX(e.X); } base.OnMouseDown(e); }
    protected override void OnMouseMove(MouseEventArgs e) { if (drag) SetFromX(e.X); base.OnMouseMove(e); }
    protected override void OnMouseUp(MouseEventArgs e) { drag = false; base.OnMouseUp(e); }
    protected override void OnMouseWheel(MouseEventArgs e) { Value = val + (e.Delta > 0 ? 1 : -1); base.OnMouseWheel(e); }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.Clear(BackColor);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        float l = 12f, r = Width - 12f, cy = Height / 2f;
        if (r - l < 20f) return;
        float t = (Max == Min) ? 0f : (float)(val - Min) / (Max - Min);
        float x = l + (r - l) * t;

        using (Pen tp = new Pen(Color.FromArgb(46, 36, 84), 8f))
        {
            tp.StartCap = LineCap.Round;
            tp.EndCap = LineCap.Round;
            g.DrawLine(tp, l, cy, r, cy);
        }
        if (x > l)
        {
            using (LinearGradientBrush lb = new LinearGradientBrush(new RectangleF(l - 6, 0, r - l + 12, Height), C1, C2, LinearGradientMode.Horizontal))
            using (Pen fp = new Pen(lb, 8f))
            {
                fp.StartCap = LineCap.Round;
                fp.EndCap = LineCap.Round;
                g.DrawLine(fp, l, cy, x, cy);
            }
        }
        using (SolidBrush gl = new SolidBrush(Color.FromArgb(60, 168, 85, 247)))
            g.FillEllipse(gl, x - 13, cy - 13, 26, 26);
        using (SolidBrush tb = new SolidBrush(Color.White))
            g.FillEllipse(tb, x - 9, cy - 9, 18, 18);
        using (Pen rp = new Pen(Color.FromArgb(74, 222, 128), 2f))
            g.DrawEllipse(rp, x - 9, cy - 9, 18, 18);
    }
}

public class SwatchRow : Control
{
    public Color[] Cols = new Color[0];
    public string[] Names = new string[0];
    int sel;
    int hot = -1;
    public event EventHandler SelectedChanged;
    const int Slot = 62;
    const int D = 34;

    public SwatchRow()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        Cursor = Cursors.Hand;
        Height = 66;
        BackColor = Color.FromArgb(24, 13, 50);
    }

    public int Selected
    {
        get { return sel; }
        set
        {
            if (sel == value) return;
            sel = value;
            Invalidate();
            if (SelectedChanged != null) SelectedChanged(this, EventArgs.Empty);
        }
    }

    int Hit(Point p)
    {
        for (int i = 0; i < Cols.Length; i++)
            if (new Rectangle(i * Slot, 0, Slot, Height).Contains(p)) return i;
        return -1;
    }

    protected override void OnMouseMove(MouseEventArgs e) { int h = Hit(e.Location); if (h != hot) { hot = h; Invalidate(); } base.OnMouseMove(e); }
    protected override void OnMouseLeave(EventArgs e) { hot = -1; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnMouseDown(MouseEventArgs e) { int h = Hit(e.Location); if (h >= 0 && e.Button == MouseButtons.Left) Selected = h; base.OnMouseDown(e); }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.Clear(BackColor);
        g.SmoothingMode = SmoothingMode.AntiAlias;
        using (Font f = new Font("Segoe UI", 8.5f))
        {
            for (int i = 0; i < Cols.Length; i++)
            {
                Rectangle c = new Rectangle(i * Slot + (Slot - D) / 2, 6, D, D);
                Color col = Cols[i];
                if (i == sel)
                {
                    using (SolidBrush gl = new SolidBrush(Color.FromArgb(55, col)))
                        g.FillEllipse(gl, Rectangle.Inflate(c, 8, 8));
                    using (Pen rp = new Pen(Color.White, 2.4f))
                        g.DrawEllipse(rp, Rectangle.Inflate(c, 4, 4));
                }
                else if (i == hot)
                {
                    using (Pen hp = new Pen(Color.FromArgb(140, 196, 181, 253), 1.6f))
                        g.DrawEllipse(hp, Rectangle.Inflate(c, 4, 4));
                }
                using (SolidBrush b = new SolidBrush(col))
                    g.FillEllipse(b, c);
                string nm = i < Names.Length ? Names[i] : "";
                TextRenderer.DrawText(g, nm, f, new Rectangle(i * Slot, 46, Slot, 18),
                    i == sel ? Color.White : Color.FromArgb(150, 140, 190),
                    TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.NoPadding | TextFormatFlags.SingleLine);
            }
        }
    }
}
'@
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition $cs6 -Language CSharp -ErrorAction Stop

# ---------- ค่าที่จำไว้ ----------
$script:xhFile = Join-Path $script:cfgDir 'crosshair.json'
$script:xhCfg = @{ on = $false; color = 0; thick = 2; size = 12; gap = 4; outline = $true }
try {
    if (Test-Path -LiteralPath $script:xhFile) {
        $xj = Get-Content -LiteralPath $script:xhFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($k in @('on', 'color', 'thick', 'size', 'gap', 'outline')) {
            if ($null -ne $xj.$k) { $script:xhCfg[$k] = $xj.$k }
        }
    }
} catch { }
$script:xhCfg.color = [Math]::Max(0, [Math]::Min(4, [int]$script:xhCfg.color))

$script:xhCols = @(
    [Drawing.Color]::FromArgb(255, 105, 180),   # ชมพู
    [Drawing.Color]::FromArgb(255, 230, 0),     # เหลือง
    [Drawing.Color]::FromArgb(255, 40, 40),     # แดง
    [Drawing.Color]::FromArgb(40, 120, 255),    # น้ำเงิน
    [Drawing.Color]::FromArgb(57, 255, 20)      # เขียว
)

$script:xhOv = New-Object CrossOverlay
$script:xhPrev = New-Object XhPreview

function Save-Xh {
    try {
        $o = [ordered]@{
            on = [bool]$script:xhCfg.on; color = [int]$script:xhCfg.color; thick = [int]$script:xhCfg.thick
            size = [int]$script:xhCfg.size; gap = [int]$script:xhCfg.gap; outline = [bool]$script:xhCfg.outline
        }
        ($o | ConvertTo-Json) | Set-Content -LiteralPath $script:xhFile -Encoding UTF8
    } catch { }
}

function Apply-Xh {
    $c = $script:xhCols[[int]$script:xhCfg.color]
    foreach ($t in @($script:xhOv, $script:xhPrev)) {
        $t.Col = $c
        $t.Thick = [int]$script:xhCfg.thick
        $t.Arm = [int]$script:xhCfg.size
        $t.Gap = [int]$script:xhCfg.gap
        $t.Outline = [bool]$script:xhCfg.outline
    }
    $script:xhPrev.Invalidate()
    if ($script:xhCfg.on) {
        $script:xhOv.Place()
        if (-not $script:xhOv.Visible) { $script:xhOv.Show() }
        $script:xhOv.Invalidate()
    } elseif ($script:xhOv.Visible) {
        $script:xhOv.Hide()
    }
    Save-Xh
}

# ---------- หน้า UI ----------
$xp = $script:pages[4][0]
$xp.Controls.Clear()
$xW = $xp.Width
$xH = $xp.Height
$xLW = 430

$xl = New-Object Card
$xl.BackColor = [Drawing.Color]::Transparent
$xl.Size = New-Object Drawing.Size($xLW, 500)
$xl.Location = New-Object Drawing.Point(18, 40)

$lbOn = New-SpLabel 'แสดงเป้ากลางจอ' (New-Object Drawing.Font('ไอติม', 12.5)) $cWhite 18 14 260 24
$lbOnS = New-SpLabel 'วางทับกลางจอ คลิกทะลุได้ ไม่บังเมาส์' (New-Object Drawing.Font('Segoe UI', 8.5)) $cOff 18 40 300 18

$script:xhTog = New-Object ToggleSwitch
$script:xhTog.BackColor = $cCard
$script:xhTog.OnColor = [Drawing.Color]::FromArgb(74, 222, 128)
$script:xhTog.OffColor = [Drawing.Color]::FromArgb(70, 58, 104)
$script:xhTog.Size = New-Object Drawing.Size(48, 26)
$script:xhTog.Location = New-Object Drawing.Point(($xLW - 18 - 48), 16)
$script:xhTog.Checked = [bool]$script:xhCfg.on

$lbCol = New-SpLabel 'สีเป้า' $fN $cLav 18 80 200 22
$script:xhSw = New-Object SwatchRow
$script:xhSw.Cols = [Drawing.Color[]]$script:xhCols
$script:xhSw.Names = [string[]]@('ชมพู', 'เหลือง', 'แดง', 'น้ำเงิน', 'เขียว')
$script:xhSw.Location = New-Object Drawing.Point(14, 104)
$script:xhSw.Size = New-Object Drawing.Size(($xLW - 28), 66)
$script:xhSw.Selected = [int]$script:xhCfg.color

$fVal = New-Object Drawing.Font('ไอติม', 10)

$lbTh = New-SpLabel 'ความหนา' $fN $cLav 18 184 200 22
$script:vTh = New-SpLabel '' $fVal $cOn ($xLW - 18 - 90) 184 90 22
$script:vTh.TextAlign = 'MiddleRight'
$script:sTh = New-Object NeonSlider
$script:sTh.Min = 1; $script:sTh.Max = 8
$script:sTh.Location = New-Object Drawing.Point(14, 208)
$script:sTh.Size = New-Object Drawing.Size(($xLW - 28), 28)
$script:sTh.Value = [int]$script:xhCfg.thick
$script:vTh.Text = ([string]$script:sTh.Value + ' px')

$lbSz = New-SpLabel 'ขนาด (ความยาวเส้น)' $fN $cLav 18 252 240 22
$script:vSz = New-SpLabel '' $fVal $cOn ($xLW - 18 - 90) 252 90 22
$script:vSz.TextAlign = 'MiddleRight'
$script:sSz = New-Object NeonSlider
$script:sSz.Min = 2; $script:sSz.Max = 50
$script:sSz.Location = New-Object Drawing.Point(14, 276)
$script:sSz.Size = New-Object Drawing.Size(($xLW - 28), 28)
$script:sSz.Value = [int]$script:xhCfg.size
$script:vSz.Text = ([string]$script:sSz.Value + ' px')

$lbGp = New-SpLabel 'ช่องว่างตรงกลาง' $fN $cLav 18 320 240 22
$script:vGp = New-SpLabel '' $fVal $cOn ($xLW - 18 - 90) 320 90 22
$script:vGp.TextAlign = 'MiddleRight'
$script:sGp = New-Object NeonSlider
$script:sGp.Min = 0; $script:sGp.Max = 20
$script:sGp.Location = New-Object Drawing.Point(14, 344)
$script:sGp.Size = New-Object Drawing.Size(($xLW - 28), 28)
$script:sGp.Value = [int]$script:xhCfg.gap
$script:vGp.Text = ([string]$script:sGp.Value + ' px')

$lbOl = New-SpLabel 'ขอบสีดำ (ช่วยให้เห็นชัด)' $fN $cLav 18 396 280 22
$script:xhOl = New-Object ToggleSwitch
$script:xhOl.BackColor = $cCard
$script:xhOl.OnColor = [Drawing.Color]::FromArgb(74, 222, 128)
$script:xhOl.OffColor = [Drawing.Color]::FromArgb(70, 58, 104)
$script:xhOl.Size = New-Object Drawing.Size(48, 26)
$script:xhOl.Location = New-Object Drawing.Point(($xLW - 18 - 48), 394)
$script:xhOl.Checked = [bool]$script:xhCfg.outline

$xReset = New-Object GradButton
$xReset.Text = 'รีเซ็ตค่าเริ่มต้น'
$xReset.C1 = [Drawing.Color]::FromArgb(70, 50, 120)
$xReset.C2 = [Drawing.Color]::FromArgb(109, 40, 217)
$xReset.Size = New-Object Drawing.Size(($xLW - 36), 38)
$xReset.Location = New-Object Drawing.Point(18, 442)

$xl.Controls.AddRange(@($lbOn, $lbOnS, $script:xhTog, $lbCol, $script:xhSw, $lbTh, $script:vTh, $script:sTh,
    $lbSz, $script:vSz, $script:sSz, $lbGp, $script:vGp, $script:sGp, $lbOl, $script:xhOl, $xReset))

# ---------- พรีวิวด้านขวา ----------
$pvX = 18 + $xLW + 16
$script:xhPrev.Location = New-Object Drawing.Point($pvX, 40)
$script:xhPrev.Size = New-Object Drawing.Size(($xW - $pvX - 18), 300)

$xNote = New-Object Windows.Forms.Label
$xNote.Text = "เคล็ดลับ`n• ใช้กับเกมโหมด Borderless / Windowed เท่านั้น (เกม Fullscreen แบบ Exclusive จะบังเป้า)`n• เป้าอยู่กลางจอหลัก คลิกทะลุได้ จึงไม่กระทบการเล่น`n• เลื่อนลูกกลิ้งเมาส์บนแถบเลื่อนเพื่อปรับทีละ 1 px`n• ค่าทั้งหมดถูกจำไว้ และเปิดเป้าอัตโนมัติถ้าครั้งก่อนเปิดค้างไว้"
$xNote.Font = New-Object Drawing.Font('Segoe UI', 9)
$xNote.ForeColor = $oLav
$xNote.BackColor = [Drawing.Color]::Transparent
$xNote.AutoSize = $false
$xNote.Size = New-Object Drawing.Size(($xW - $pvX - 18), 130)
$xNote.Location = New-Object Drawing.Point($pvX, 356)

$xp.Controls.AddRange(@($xl, $script:xhPrev, $xNote))

# ---------- เหตุการณ์ (ผูกหลังตั้งค่าเริ่มต้นแล้ว จึงไม่ยิงซ้ำ) ----------
$script:xhTog.Add_CheckedChanged({ $script:xhCfg.on = $script:xhTog.Checked; Apply-Xh })
$script:xhOl.Add_CheckedChanged({ $script:xhCfg.outline = $script:xhOl.Checked; Apply-Xh })
$script:xhSw.Add_SelectedChanged({ $script:xhCfg.color = $script:xhSw.Selected; Apply-Xh })
$script:sTh.Add_ValueChanged({ $script:xhCfg.thick = $script:sTh.Value; $script:vTh.Text = ([string]$script:sTh.Value + ' px'); Apply-Xh })
$script:sSz.Add_ValueChanged({ $script:xhCfg.size = $script:sSz.Value; $script:vSz.Text = ([string]$script:sSz.Value + ' px'); Apply-Xh })
$script:sGp.Add_ValueChanged({ $script:xhCfg.gap = $script:sGp.Value; $script:vGp.Text = ([string]$script:sGp.Value + ' px'); Apply-Xh })
$xReset.Add_Click({
    $script:xhSw.Selected = 0
    $script:sTh.Value = 2
    $script:sSz.Value = 12
    $script:sGp.Value = 4
    $script:xhOl.Checked = $true
})

$form.Add_FormClosed({ try { $script:xhOv.Close(); $script:xhOv.Dispose() } catch { } })
Apply-Xh
# =====================================================================
#  BOOTS FPS  -  โหมดเล่นเกม (ปิดตัวไม่จำเป็นตอนเล่น / คืนค่าตอนเลิก)
# =====================================================================
$np = $script:pages[5][0]
$np.Controls.Clear()

$script:bfFile    = Join-Path $script:cfgDir 'boost_state.json'
$script:bfCfgFile = Join-Path $script:cfgDir 'boost_cfg.json'
$script:bfActive  = $false
$script:bfBusy    = $false
$script:bfByAuto  = $false
$script:bfMiss    = 0
$script:bfState   = ''
$script:bfTogs    = New-Object System.Collections.ArrayList

# บริการที่หยุดชั่วคราว (ปลอดภัย ไม่กระทบการทำงานหลักของ Windows)
$script:bfSvcNames = @('SysMain', 'WSearch', 'DiagTrack', 'Spooler', 'WerSvc', 'MapsBroker')
# แอปพื้นหลังที่ปิดชั่วคราว (ชื่อโปรเซส ไม่ต้องใส่ .exe)
$script:bfProcNames = @('OneDrive', 'Teams', 'ms-teams', 'Skype', 'YourPhone', 'PhoneExperienceHost', 'Widgets', 'WidgetService', 'Cortana')
if ($env:BATDIR) {
    $bl = Join-Path $env:BATDIR 'bloat.txt'   # อยากปิดแอปอื่นเพิ่ม: สร้าง bloat.txt วางข้างไฟล์ .bat บรรทัดละชื่อโปรเซส
    if (Test-Path -LiteralPath $bl) {
        foreach ($l in (Get-Content -LiteralPath $bl -Encoding UTF8)) {
            $q = ($l.Trim().Trim('"') -replace '\.exe$', '')
            if ($q -and -not $q.StartsWith('#')) { $script:bfProcNames += $q }
        }
    }
}

# ---------- ค่าที่จำไว้ ----------
$script:bfCfg = @{
    auto  = $false
    games = @('cs2', 'VALORANT-Win64-Shipping', 'FortniteClient-Win64-Shipping', 'RobloxPlayerBeta', 'GenshinImpact',
              'dota2', 'r5apex', 'Overwatch', 'League of Legends', 'PUBG', 'TslGame', 'GTA5')
}
$script:bfOpt = @{ power = $true; svc = $true; proc = $true; ram = $true; prio = $true }
try {
    if (Test-Path -LiteralPath $script:bfCfgFile) {
        $bj = Get-Content -LiteralPath $script:bfCfgFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $bj.auto) { $script:bfCfg.auto = [bool]$bj.auto }
        if ($bj.games) { $script:bfCfg.games = @($bj.games | ForEach-Object { [string]$_ }) }
        if ($bj.opt) {
            foreach ($k in @('power', 'svc', 'proc', 'ram', 'prio')) {
                if ($null -ne $bj.opt.$k) { $script:bfOpt[$k] = [bool]$bj.opt.$k }
            }
        }
    }
} catch { }

function Save-Bf {
    try {
        $o = [ordered]@{ auto = [bool]$script:bfCfg.auto; games = @($script:bfCfg.games); opt = $script:bfOpt }
        ($o | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $script:bfCfgFile -Encoding UTF8
    } catch { }
}

# ---------- งานเบื้องหลัง (เปิด/ปิดโหมด) ----------
$script:bfCode = @'
$ErrorActionPreference = 'SilentlyContinue'
$guidRx = '[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}'
$hp = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
if ($mode -eq 'on') {
    $st = @{ power = ''; svcs = @(); procs = @() }
    if ($opt['power']) {
        $cur = [regex]::Match((& powercfg /getactivescheme | Out-String), $guidRx).Value
        if ($cur -and $cur -ne $hp) {
            & powercfg /setactive $hp 2>&1 | Out-Null
            $ok = ($LASTEXITCODE -eq 0)
            if (-not $ok) {
                $dup = [regex]::Match((& powercfg /duplicatescheme $hp 2>&1 | Out-String), $guidRx).Value
                if ($dup) { & powercfg /setactive $dup 2>&1 | Out-Null; $ok = ($LASTEXITCODE -eq 0) }
            }
            if ($ok) { $st.power = $cur }
        }
    }
    if ($opt['svc']) {
        $list = New-Object System.Collections.ArrayList
        foreach ($n in $svcList) {
            $s = Get-Service -Name $n
            if ($s -and $s.Status -eq 'Running' -and $s.CanStop) {
                try { Stop-Service -Name $n -Force -ErrorAction Stop; [void]$list.Add($n) } catch { }
            }
        }
        $st.svcs = @($list)
    }
    if ($opt['proc']) {
        $paths = New-Object System.Collections.ArrayList
        foreach ($n in $procList) {
            foreach ($p in @(Get-Process -Name $n)) {
                try { $pa = $p.Path; $p.Kill(); if ($pa) { [void]$paths.Add($pa) } } catch { }
            }
        }
        $st.procs = @($paths | Select-Object -Unique)
    }
    'OK:' + ($st | ConvertTo-Json -Compress)
}
else {
    $st = $stateJson | ConvertFrom-Json
    if ($st.power) { & powercfg /setactive $st.power 2>&1 | Out-Null }
    foreach ($n in @($st.svcs)) { if ($n) { try { Start-Service -Name ([string]$n) -ErrorAction Stop } catch { } } }
    foreach ($pa in @($st.procs)) {
        # เปิดผ่าน explorer เพื่อให้แอปกลับมาทำงานแบบผู้ใช้ปกติ (ไม่ใช่สิทธิ์แอดมิน)
        if ($pa -and (Test-Path -LiteralPath $pa)) { try { Start-Process explorer.exe -ArgumentList ('"' + $pa + '"') } catch { } }
    }
    'OK:restored'
}
'@

function Set-GamePrio {
    $g = @($script:bfCfg.games | Where-Object { $_ })
    if ($g.Count -eq 0) { return }
    foreach ($p in @(Get-Process -Name ([string[]]$g) -ErrorAction SilentlyContinue)) {
        try { if ($p.PriorityClass -ne 'High') { $p.PriorityClass = 'High' } } catch { }
    }
}

function Update-BfUi {
    $on = $script:bfActive
    if ($on) {
        $script:bfBtn.Text = 'ปิดโหมดเล่นเกม (คืนค่า)'
        $script:bfBtn.C1 = [Drawing.Color]::FromArgb(239, 68, 68)
        $script:bfBtn.C2 = [Drawing.Color]::FromArgb(244, 114, 150)
        $script:bfStatus.Text = 'เปิดอยู่ - เล่นเกมได้เลย'
        $script:bfStatus.ForeColor = [Drawing.Color]::FromArgb(74, 222, 128)
    } else {
        $script:bfBtn.Text = 'เปิดโหมดเล่นเกม'
        $script:bfBtn.C1 = [Drawing.Color]::FromArgb(109, 40, 217)
        $script:bfBtn.C2 = [Drawing.Color]::FromArgb(34, 160, 110)
        $script:bfStatus.Text = 'ปิดอยู่'
        $script:bfStatus.ForeColor = $cOff
    }
    $script:bfBtn.Enabled = (-not $script:bfBusy)
    $script:bfBtn.Invalidate()
    foreach ($t in $script:bfTogs) { $t.Enabled = (-not $on) }   # ล็อกตัวเลือกระหว่างเปิดโหมด
}

$script:bfDone = {
    param($out, $ctx)
    $res = [string](@($out)[-1])
    $script:bfBusy = $false
    if ($ctx.Mode -eq 'on') {
        if ($res -like 'OK:*') {
            $js = $res.Substring(3)
            $script:bfState = $js
            try { [IO.File]::WriteAllText($script:bfFile, $js, (New-Object Text.UTF8Encoding $false)) } catch { }
            $script:bfActive = $true
            $nS = 0; $nP = 0; $pw = 'ไม่เปลี่ยน'
            try {
                $o = $js | ConvertFrom-Json
                $nS = @($o.svcs | Where-Object { $_ }).Count
                $nP = @($o.procs | Where-Object { $_ }).Count
                if ($o.power) { $pw = 'High Performance' }
            } catch { }
            if ($script:bfOpt.ram) { [MemCleaner]::RunAsync() }
            if ($script:bfOpt.prio) { Set-GamePrio }
            $script:bfLog.Text = ('เปิดโหมดเมื่อ ' + (Get-Date).ToString('HH:mm:ss') + "`nPower plan: " + $pw + "`nหยุดบริการ " + $nS + ' รายการ | ปิดแอป ' + $nP + ' ตัว')
        } else {
            $script:bfLog.Text = 'เปิดโหมดไม่สำเร็จ: ' + $res
        }
    } else {
        $script:bfActive = $false
        $script:bfByAuto = $false
        try { Remove-Item -LiteralPath $script:bfFile -Force -ErrorAction SilentlyContinue } catch { }
        $script:bfState = ''
        $script:bfLog.Text = 'คืนค่าเรียบร้อย ' + (Get-Date).ToString('HH:mm:ss') + "`n(Power plan / บริการ / แอปที่ปิดไว้ ถูกเปิดกลับแล้ว)"
    }
    Update-BfUi
}

function Set-Boost([bool]$on, [bool]$byAuto) {
    if ($script:bfBusy) { return }
    if ($on -eq $script:bfActive) { return }
    $script:bfBusy = $true
    $script:bfByAuto = ($on -and $byAuto)
    $script:bfBtn.Enabled = $false
    $script:bfStatus.ForeColor = $cLav
    $script:bfStatus.Text = 'กำลังทำงานเบื้องหลัง...'
    $mode = 'off'
    if ($on) { $mode = 'on' }
    Start-Bg $script:bfCode @{ mode = $mode; opt = $script:bfOpt; stateJson = [string]$script:bfState
        svcList = [string[]]$script:bfSvcNames; procList = [string[]]$script:bfProcNames } $script:bfDone @{ Mode = $mode }
}

# ---------- สร้างหน้า ----------
$bW = $np.Width
$bH = $np.Height
$bLW = 500
$bfTitleF = New-Object Drawing.Font('ไอติม', 11)
$bfDescF  = New-Object Drawing.Font('Segoe UI', 8.5)

$bl = New-Object Card
$bl.BackColor = [Drawing.Color]::Transparent
$bl.Size = New-Object Drawing.Size($bLW, 480)
$bl.Location = New-Object Drawing.Point(18, 40)

$bfHead = New-SpLabel 'โหมดเล่นเกม' (New-Object Drawing.Font('ไอติม', 14)) $cWhite 18 12 300 26
$script:bfStatus = New-SpLabel 'ปิดอยู่' (New-Object Drawing.Font('ไอติม', 10)) $cOff 18 42 440 22

$script:bfBtn = New-Object GradButton
$script:bfBtn.Text = 'เปิดโหมดเล่นเกม'
$script:bfBtn.Size = New-Object Drawing.Size(($bLW - 36), 52)
$script:bfBtn.Location = New-Object Drawing.Point(18, 74)
$script:bfBtn.Add_Click({ Set-Boost (-not $script:bfActive) $false })

function New-BfRow($parent, [string]$key, [string]$title, [string]$desc, [int]$y) {
    $l1 = New-SpLabel $title $bfTitleF $cWhite 18 $y 330 22
    $l2 = New-SpLabel $desc $bfDescF $cOff 18 ($y + 22) 400 18
    $t = New-Object ToggleSwitch
    $t.BackColor = $cCard
    $t.OnColor = [Drawing.Color]::FromArgb(74, 222, 128)
    $t.OffColor = [Drawing.Color]::FromArgb(70, 58, 104)
    $t.Size = New-Object Drawing.Size(48, 26)
    $t.Location = New-Object Drawing.Point(($bLW - 18 - 48), ($y + 6))
    $t.Checked = [bool]$script:bfOpt[$key]
    $t.Tag = $key
    $t.Add_CheckedChanged({ param($s, $e) $script:bfOpt[[string]$s.Tag] = [bool]$s.Checked; Save-Bf })
    $parent.Controls.AddRange(@($l1, $l2, $t))
    [void]$script:bfTogs.Add($t)
}

# สวิตช์ตรวจจับเกมอัตโนมัติ
$lbAuto = New-SpLabel 'ตรวจจับเกมอัตโนมัติ' $bfTitleF $cWhite 18 142 330 22
$lbAutoS = New-SpLabel 'เปิดเกมในรายการ = เข้าโหมดเอง / ปิดเกม = คืนค่าเอง' $bfDescF $cOff 18 164 400 18
$tgAuto = New-Object ToggleSwitch
$tgAuto.BackColor = $cCard
$tgAuto.OnColor = [Drawing.Color]::FromArgb(74, 222, 128)
$tgAuto.OffColor = [Drawing.Color]::FromArgb(70, 58, 104)
$tgAuto.Size = New-Object Drawing.Size(48, 26)
$tgAuto.Location = New-Object Drawing.Point(($bLW - 18 - 48), 148)
$tgAuto.Checked = [bool]$script:bfCfg.auto
$tgAuto.Add_CheckedChanged({ param($s, $e) $script:bfCfg.auto = [bool]$s.Checked; Save-Bf })

$lbSec = New-SpLabel 'สิ่งที่จะทำเมื่อเปิดโหมด' (New-Object Drawing.Font('ไอติม', 10)) $cLav 18 200 300 20

$bl.Controls.AddRange(@($bfHead, $script:bfStatus, $script:bfBtn, $lbAuto, $lbAutoS, $tgAuto, $lbSec))
New-BfRow $bl 'power' 'Power Plan: High Performance' 'สลับแผนพลังงานเป็นประสิทธิภาพสูง แล้วคืนแผนเดิมตอนเลิก' 226
New-BfRow $bl 'svc'   'หยุดบริการที่ไม่จำเป็น' 'SysMain, Windows Search, Telemetry, Print Spooler, Error Reporting, Maps' 272
New-BfRow $bl 'proc'  'ปิดแอปพื้นหลัง' 'OneDrive, Teams, Skype, Widgets ฯลฯ (เปิดกลับให้ตอนเลิก)' 318
New-BfRow $bl 'ram'   'ล้างแรมก่อนเล่น' 'คืนหน่วยความจำจากโปรแกรมที่ไม่ได้ใช้ (ไม่แตะโปรแกรมหน้าจอ)' 364
New-BfRow $bl 'prio'  'ตั้ง Priority เกมเป็น High' 'ให้ CPU ความสำคัญกับเกมมากขึ้น (ทำกับเกมในรายการ)' 410

# ---------- การ์ดขวา: รายชื่อเกม ----------
$bx = 18 + $bLW + 16
$br = New-Object Card
$br.BackColor = [Drawing.Color]::Transparent
$br.Size = New-Object Drawing.Size(($bW - $bx - 18), 480)
$br.Location = New-Object Drawing.Point($bx, 40)
$brW = $br.Width

$brHead = New-SpLabel 'เกมที่ตรวจจับ (ชื่อโปรเซส)' (New-Object Drawing.Font('ไอติม', 12)) $cWhite 18 12 ($brW - 36) 24

$script:bfList = New-Object Windows.Forms.ListBox
$script:bfList.BorderStyle = 'None'
$script:bfList.BackColor = [Drawing.Color]::FromArgb(15, 9, 33)
$script:bfList.ForeColor = [Drawing.Color]::White
$script:bfList.Font = New-Object Drawing.Font('Segoe UI', 10)
$script:bfList.IntegralHeight = $false
$script:bfList.Size = New-Object Drawing.Size(($brW - 36), 230)
$script:bfList.Location = New-Object Drawing.Point(18, 46)
foreach ($g in $script:bfCfg.games) { [void]$script:bfList.Items.Add([string]$g) }

$bAdd = New-Object GradButton
$bAdd.Text = '+ เพิ่มเกม (.exe)'
$bAdd.C1 = [Drawing.Color]::FromArgb(109, 40, 217)
$bAdd.C2 = [Drawing.Color]::FromArgb(34, 160, 110)
$bAdd.Size = New-Object Drawing.Size([int](($brW - 36 - 10) / 2), 38)
$bAdd.Location = New-Object Drawing.Point(18, 288)
$bAdd.Add_Click({
    $ofd = New-Object Windows.Forms.OpenFileDialog
    $ofd.Title = 'เลือกไฟล์ .exe ของเกม'
    $ofd.Filter = 'โปรแกรม (*.exe)|*.exe'
    if ($ofd.ShowDialog() -ne 'OK') { return }
    $nm = [IO.Path]::GetFileNameWithoutExtension($ofd.FileName)
    if (-not $nm) { return }
    if ($script:bfCfg.games -contains $nm) { return }
    $script:bfCfg.games = @($script:bfCfg.games) + $nm
    [void]$script:bfList.Items.Add($nm)
    Save-Bf
})

$bDel = New-Object GradButton
$bDel.Text = 'ลบที่เลือก'
$bDel.C1 = [Drawing.Color]::FromArgb(70, 50, 120)
$bDel.C2 = [Drawing.Color]::FromArgb(109, 40, 217)
$bDel.Size = New-Object Drawing.Size([int](($brW - 36 - 10) / 2), 38)
$bDel.Location = New-Object Drawing.Point((18 + [int](($brW - 36 - 10) / 2) + 10), 288)
$bDel.Add_Click({
    $i = $script:bfList.SelectedIndex
    if ($i -lt 0) { return }
    $nm = [string]$script:bfList.SelectedItem
    $script:bfCfg.games = @($script:bfCfg.games | Where-Object { $_ -ne $nm })
    $script:bfList.Items.RemoveAt($i)
    Save-Bf
})

$brLogH = New-SpLabel 'ผลล่าสุด' (New-Object Drawing.Font('ไอติม', 10)) $cLav 18 344 200 20
$script:bfLog = New-SpLabel 'ยังไม่ได้เปิดโหมด' (New-Object Drawing.Font('Segoe UI', 9)) $cOff 18 368 ($brW - 36) 96

$br.Controls.AddRange(@($brHead, $script:bfList, $bAdd, $bDel, $brLogH, $script:bfLog))
$np.Controls.AddRange(@($bl, $br))

# ---------- ตัวตรวจจับเกม (ทุก 3 วินาที) ----------
$script:bfTm = New-Object Windows.Forms.Timer
$script:bfTm.Interval = 3000
$script:bfTm.Add_Tick({
    try {
        if ($script:bfBusy -or -not $script:bfCfg.auto) { return }
        $g = @($script:bfCfg.games | Where-Object { $_ })
        if ($g.Count -eq 0) { return }
        $run = @(Get-Process -Name ([string[]]$g) -ErrorAction SilentlyContinue)
        if ($run.Count -gt 0) {
            $script:bfMiss = 0
            if (-not $script:bfActive) { Set-Boost $true $true }
            elseif ($script:bfOpt.prio) { Set-GamePrio }
        } elseif ($script:bfActive -and $script:bfByAuto) {
            $script:bfMiss++
            if ($script:bfMiss -ge 3) { $script:bfMiss = 0; Set-Boost $false $false }   # รอ ~9 วิ กันตัวเปิดเกมสลับโปรเซส
        }
    } catch { }
})
$script:bfTm.Start()

# ---------- ถ้าคราวก่อนโปรแกรมดับตอนเปิดโหมดค้างไว้ ----------
try {
    if (Test-Path -LiteralPath $script:bfFile) {
        $script:bfState = (Get-Content -LiteralPath $script:bfFile -Raw -Encoding UTF8).Trim()
        if ($script:bfState) {
            $script:bfActive = $true
            $script:bfLog.Text = 'พบโหมดเล่นเกมที่ค้างจากครั้งก่อน กดปุ่มด้านบนเพื่อคืนค่า'
        }
    }
} catch { }
Update-BfUi

# ---------- ปิดโปรแกรมตอนโหมดยังเปิดอยู่: ถามว่าจะคืนค่าไหม ----------
$form.Add_FormClosing({
    param($s, $e)
    if (-not $script:bfActive) { return }
    $a = [Windows.Forms.MessageBox]::Show('โหมดเล่นเกมยังเปิดอยู่ คืนค่า (เปิดบริการ/แอปที่ปิดไว้กลับ) ก่อนปิดโปรแกรมไหม?', 'Boots FPS', 'YesNo', 'Question')
    if ($a -eq 'Yes') {
        try {
            $mode = 'off'; $stateJson = [string]$script:bfState; $opt = $script:bfOpt
            Invoke-Expression $script:bfCode | Out-Null
            Remove-Item -LiteralPath $script:bfFile -Force -ErrorAction SilentlyContinue
            $script:bfActive = $false
        } catch { }
    }
})
$form.Add_FormClosed({ try { $script:bfTm.Stop(); $script:bfTm.Dispose() } catch { } })
$tm.Start()
$spTm.Start()
$script:eng.LoadInfo()
$script:base=@{}
function Snap($p){ foreach($c in $p.Controls){ $script:base[$c]=@($c.Left,$c.Top,$c.Width,$c.Height,$c.Font.Size); if($c -isnot [InputBox]){ Snap $c } } }
Snap $form; $w0=$form.ClientSize.Width; $h0=$form.ClientSize.Height
function Rescale($p,$kx,$ky){
  foreach($c in $p.Controls){ $b=$script:base[$c]; if(-not $b){continue}
    $c.SetBounds([int]($b[0]*$kx),[int]($b[1]*$ky),[int]($b[2]*$kx),[int]($b[3]*$ky))
    $fs=[single]([Math]::Max(6,$b[4]*[Math]::Min($kx,$ky)))
    if([Math]::Abs($c.Font.Size-$fs) -gt 0.4){ $c.Font=New-Object Drawing.Font($c.Font.FontFamily,$fs,$c.Font.Style) }
    if($c -isnot [InputBox]){ Rescale $c $kx $ky } } }
$form.Add_Resize({ if($form.ClientSize.Width -gt 0){ $form.SuspendLayout(); Rescale $form ($form.ClientSize.Width/$w0) ($form.ClientSize.Height/$h0); $form.ResumeLayout() } })
[void]$form.ShowDialog()