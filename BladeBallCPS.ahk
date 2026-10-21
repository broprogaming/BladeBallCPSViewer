; ============================================================================
;  BLADE BALL CPS / KPS  (AutoHotkey v2)
;  Live clicks-per-second / keys-per-second HUD, styled like Blade Ball.
;
;  Right-click the HUD  -> settings (add / remove any number of keys)
;  Drag the HUD         -> move it (the spot is remembered)
;  Tray icon            -> show / hide the HUD, settings, exit
;  Presses only count while Roblox is the active window (toggle in settings).
; ============================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent()
SetWorkingDir(A_ScriptDir)
CoordMode("Mouse", "Screen")
CoordMode("ToolTip", "Screen")

; ------------------------------ settings -----------------------------------
global INI := A_ScriptDir "\BladeBallCPS.ini"
global MAXK := 9
global C := Map(
    "keys", ["LButton"],
    "onTop", 1, "onlyRoblox", 1, "opacity", 100, "hud", 1,
    "hudX", 120, "hudY", 120
)
global ST := Map("opacity", [10, 30, 100])      ; stepper rules: step, min, max

; colour sets: top, bottom, border
global PAL := Map(
    "blue",  [0xFF4AA6FF, 0xFF165CDC, 0xFFD6EDFF],
    "green", [0xFF78FF4A, 0xFF1FAA00, 0xFFD8FFCF],
    "red",   [0xFFFF6464, 0xFFC4101C, 0xFFFFD2D2],
    "dark",  [0xFF1B2A7A, 0xFF060B2A, 0xFF7C93FF],
    "gold",  [0xFFFFC24A, 0xFFE07A00, 0xFFFFE9B8]
)

global Wins := Map()
global Presses := [], HudRate := 0, HudPeak := 0, LastPress := 0
global BoundKeys := []
global Capturing := false, CapArmed := false, CapStart := 0
global HudWin := "", SetWin := ""

LoadCfg() {
    for k in ["onTop", "onlyRoblox", "opacity", "hud", "hudX", "hudY"]
        try C[k] := Integer(IniRead(INI, "Main", k, C[k]))
    keys := []
    for nm in StrSplit(IniRead(INI, "Main", "keys", "LButton"), "|") {
        if (nm != "" && IdxOf(keys, nm) = 0 && keys.Length < MAXK)
            keys.Push(nm)
    }
    C["keys"] := keys
}

SaveCfg() {
    IniWrite(KeysStr(), INI, "Main", "keys")
    for k in ["onTop", "onlyRoblox", "opacity", "hud", "hudX", "hudY"]
        IniWrite(C[k], INI, "Main", k)
}

; ------------------------------ helpers ------------------------------------
Now() {
    static f := 0
    if !f {
        q := 0
        DllCall("QueryPerformanceFrequency", "int64*", &q)
        f := q / 1000
    }
    c := 0
    DllCall("QueryPerformanceCounter", "int64*", &c)
    return c / f
}

IsMouse(k) => RegExMatch(k, "i)^(L|R|M)Button$|^XButton[12]$") ? true : false

KeyLabel(k) {
    static m := Map("lbutton", "LEFT CLICK", "rbutton", "RIGHT CLICK", "mbutton", "MIDDLE CLICK", "xbutton1", "MOUSE 4", "xbutton2", "MOUSE 5")
    lk := StrLower(k)
    return m.Has(lk) ? m[lk] : StrUpper(k)
}

ChipLabel(k) {
    static m := Map("lbutton", "LMB", "rbutton", "RMB", "mbutton", "MMB", "xbutton1", "MB4", "xbutton2", "MB5")
    lk := StrLower(k)
    return m.Has(lk) ? m[lk] : StrUpper(k)
}

IdxOf(arr, v) {
    for i, x in arr {
        if (x = v)
            return i
    }
    return 0
}

KeysStr() {
    s := ""
    for k in C["keys"]
        s .= (A_Index = 1 ? "" : "|") . k
    return s
}

; the HUD says CPS when every bound key is a mouse button, otherwise KPS
HudLabel() {
    for k in C["keys"] {
        if !IsMouse(k)
            return "KPS"
    }
    return "CPS"
}

Toast(msg) {
    ToolTip(msg, A_ScreenWidth // 2 - 100, 40)
    SetTimer(() => ToolTip(), -1400)
}

RobloxOK() {
    if !C["onlyRoblox"]
        return true
    return WinActive("ahk_exe RobloxPlayerBeta.exe") || WinActive("ahk_exe Windows10Universal.exe")
}

; true when the mouse is over one of our own windows (HUD / settings)
OverOwnWindow() {
    mx := 0, my := 0, hw := 0
    MouseGetPos(&mx, &my, &hw)
    return Wins.Has(hw)
}

RegisterPress() {
    global LastPress
    LastPress := Now()
    Presses.Push(LastPress)
}

CurrentRate() {
    t := Now() - 1000
    while (Presses.Length && Presses[1] < t)
        Presses.RemoveAt(1)
    return Presses.Length
}

ResetStats(*) {
    global HudPeak, Presses
    HudPeak := 0
    Presses := []
}

; ------------------------------ GDI+ ---------------------------------------
GdipStart() {
    if !DllCall("GetModuleHandle", "str", "gdiplus", "ptr")
        DllCall("LoadLibrary", "str", "gdiplus")
    si := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
    NumPut("uint", 1, si)
    tok := 0
    DllCall("gdiplus\GdiplusStartup", "ptr*", &tok, "ptr", si, "ptr", 0)
    return tok
}

class Surface {
    __New(w, h) {
        this.w := w
        this.h := h
        sdc := DllCall("GetDC", "ptr", 0, "ptr")
        this.dc := DllCall("CreateCompatibleDC", "ptr", sdc, "ptr")
        DllCall("ReleaseDC", "ptr", 0, "ptr", sdc)
        bi := Buffer(40, 0)
        NumPut("uint", 40, "int", w, "int", -h, "ushort", 1, "ushort", 32, bi)
        bits := 0
        this.bmp := DllCall("CreateDIBSection", "ptr", this.dc, "ptr", bi, "uint", 0, "ptr*", &bits, "ptr", 0, "uint", 0, "ptr")
        DllCall("SelectObject", "ptr", this.dc, "ptr", this.bmp)
        gp := 0
        DllCall("gdiplus\GdipCreateFromHDC", "ptr", this.dc, "ptr*", &gp)
        this.g := gp
        DllCall("gdiplus\GdipSetSmoothingMode", "ptr", gp, "int", 4)
        DllCall("gdiplus\GdipSetPixelOffsetMode", "ptr", gp, "int", 2)
    }
    Clear() {
        DllCall("gdiplus\GdipGraphicsClear", "ptr", this.g, "uint", 0)
    }
    Push(hwnd, alpha := 255) {
        sz := Buffer(8)
        NumPut("int", this.w, "int", this.h, sz)
        src := Buffer(8, 0)
        bl := Buffer(4)
        NumPut("uchar", 0, "uchar", 0, "uchar", alpha, "uchar", 1, bl)
        DllCall("UpdateLayeredWindow", "ptr", hwnd, "ptr", 0, "ptr", 0, "ptr", sz, "ptr", this.dc, "ptr", src, "uint", 0, "ptr", bl, "uint", 2)
    }
}

; a click-through, borderless, per-pixel-alpha window that draws itself
class BBWin {
    __New(w, h, painter, sigFn, x, y, useOp := false, top := true) {
        this.w := w
        this.h := h
        this.painter := painter
        this.sigFn := sigFn
        this.useOp := useOp
        this.hits := []
        this.hover := ""
        this.sig := ""
        this.visible := true
        this.surf := Surface(w, h)
        opts := "-Caption +ToolWindow -DPIScale +E0x08080000"
        if top
            opts .= " +AlwaysOnTop"
        this.gui := Gui(opts)
        this.hwnd := this.gui.Hwnd
        this.gui.Show("NA x" x " y" y " w" w " h" h)
        Wins[this.hwnd] := this
    }
    Render() {
        this.hits := []
        this.surf.Clear()
        this.painter.Call(this, this.surf.g)
        this.surf.Push(this.hwnd, this.useOp ? Round(C["opacity"] * 2.55) : 255)
    }
    AddHit(id, x, y, w, h) {
        this.hits.Push([id, x, y, w, h])
    }
}

PolyBuf(pts) {
    b := Buffer(pts.Length * 4)
    for i, v in pts
        NumPut("float", v, b, (i - 1) * 4)
    return b
}

FillPoly(g, pts, c1, c2 := 0, rc := "") {
    n := pts.Length // 2
    b := PolyBuf(pts)
    br := 0
    if !c2
        DllCall("gdiplus\GdipCreateSolidFill", "uint", c1, "ptr*", &br)
    else {
        r := Buffer(16)
        NumPut("int", rc[1], "int", rc[2], "int", rc[3], "int", rc[4], r)
        DllCall("gdiplus\GdipCreateLineBrushFromRectI", "ptr", r, "uint", c1, "uint", c2, "int", 1, "int", 0, "ptr*", &br)
    }
    DllCall("gdiplus\GdipFillPolygon", "ptr", g, "ptr", br, "ptr", b, "int", n, "int", 0)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", br)
}

FillPath(g, path, c) {
    br := 0
    DllCall("gdiplus\GdipCreateSolidFill", "uint", c, "ptr*", &br)
    DllCall("gdiplus\GdipFillPath", "ptr", g, "ptr", br, "ptr", path)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", br)
}

; filled circle centred on (cx, cy)
EllFill(g, cx, cy, r, c) {
    p := 0
    DllCall("gdiplus\GdipCreatePath", "int", 0, "ptr*", &p)
    DllCall("gdiplus\GdipAddPathEllipse", "ptr", p, "float", cx - r, "float", cy - r, "float", r * 2, "float", r * 2)
    FillPath(g, p, c)
    DllCall("gdiplus\GdipDeletePath", "ptr", p)
}

FontFam() {
    static fam := 0, sty := 1
    if !fam {
        for nm in ["Lilita One", "Luckiest Guy", "Titan One", "Segoe UI Black", "Arial Black", "Impact", "Verdana"] {
            f := 0
            if (DllCall("gdiplus\GdipCreateFontFamilyFromName", "wstr", nm, "ptr", 0, "ptr*", &f) = 0 && f) {
                fam := f
                sty := InStr("Segoe UI Black,Arial Black,Impact,Lilita One,Luckiest Guy,Titan One", nm) ? 0 : 1
                break
            }
        }
    }
    return [fam, sty]
}

; sticker-style text: coloured fill with a thick dark outline (like the game)
OText(g, s, x, y, w, h, size, fill := 0xFFFFFFFF, ol := 0xFF0A1030, ow := 3, align := 1) {
    ff := FontFam()
    if !ff[1]
        return
    fmt := 0, path := 0, pen := 0, br := 0
    DllCall("gdiplus\GdipCreateStringFormat", "int", 0, "ushort", 0, "ptr*", &fmt)
    DllCall("gdiplus\GdipSetStringFormatAlign", "ptr", fmt, "int", align)
    DllCall("gdiplus\GdipSetStringFormatLineAlign", "ptr", fmt, "int", 1)
    DllCall("gdiplus\GdipCreatePath", "int", 0, "ptr*", &path)
    rc := Buffer(16)
    NumPut("float", x, "float", y, "float", w, "float", h, rc)
    DllCall("gdiplus\GdipAddPathString", "ptr", path, "wstr", String(s), "int", -1, "ptr", ff[1], "int", ff[2], "float", size, "ptr", rc, "ptr", fmt)
    if (ow > 0) {
        DllCall("gdiplus\GdipCreatePen1", "uint", ol, "float", ow * 2, "int", 2, "ptr*", &pen)
        DllCall("gdiplus\GdipSetPenLineJoin", "ptr", pen, "int", 2)
        DllCall("gdiplus\GdipDrawPath", "ptr", g, "ptr", pen, "ptr", path)
        DllCall("gdiplus\GdipDeletePen", "ptr", pen)
    }
    DllCall("gdiplus\GdipCreateSolidFill", "uint", fill, "ptr*", &br)
    DllCall("gdiplus\GdipFillPath", "ptr", g, "ptr", br, "ptr", path)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", br)
    DllCall("gdiplus\GdipDeletePath", "ptr", path)
    DllCall("gdiplus\GdipDeleteStringFormat", "ptr", fmt)
}

; ------------------------------ Blade Ball look ----------------------------
Para(x, y, w, h, s) => [x + s, y, x + w, y, x + w - s, y + h, x, y + h]
ParaTop(x, y, w, h, s, f) => [x + s, y, x + w, y, x + w - s * f, y + h * f, x + s * (1 - f), y + h * f]

; slanted glossy plate: shadow, light border, gradient body, shine
Plate(g, x, y, w, h, s, kind, hot := false) {
    p := PAL[kind]
    FillPoly(g, Para(x + 3, y + 5, w, h, s), 0x66000A24)
    FillPoly(g, Para(x, y, w, h, s), p[3])
    bx := x + 3, by := y + 3, bw := w - 6, bh := h - 6
    FillPoly(g, Para(bx, by, bw, bh, s), p[1], p[2], [Round(bx), Round(by), Round(bw), Round(bh)])
    FillPoly(g, ParaTop(bx, by, bw, bh, s, 0.46), 0x40FFFFFF, 0x0CFFFFFF, [Round(bx), Round(by), Round(bw), Max(1, Round(bh * 0.46))])
    if hot
        FillPoly(g, Para(bx, by, bw, bh, s), 0x2CFFFFFF)
}

Button(win, g, id, x, y, w, h, s, kind, label, size) {
    Plate(g, x, y, w, h, s, kind, win.hover = id)
    OText(g, label, x, y, w, h, size)
    win.AddHit(id, x, y, w, h)
}

; the blade ball: a glossy red sphere with a glow ring. It flashes gold on every press.
Ball(g, cx, cy, r, hot) {
    EllFill(g, cx, cy + 2, r + 4, hot ? 0x88FFD84A : 0x44FF3B3B)   ; glow
    EllFill(g, cx + 2, cy + 3, r + 2, 0x66000A24)                  ; shadow
    EllFill(g, cx, cy, r + 2, 0xFFFFFFFF)                          ; white rim
    EllFill(g, cx, cy, r, hot ? 0xFFFFE27A : 0xFFD81E2E)           ; body
    EllFill(g, cx - r * 0.3, cy - r * 0.38, r * 0.32, 0xC8FFFFFF)  ; hot spot
}

; ------------------------------ painters -----------------------------------
PaintHud(win, g) {
    Plate(g, 8, 26, 160, 62, 12, "blue")
    Plate(g, 10, 3, 66, 30, 9, "dark")
    OText(g, HudLabel(), 10, 3, 66, 30, 19)
    OText(g, HudRate, 16, 30, 104, 56, 40)
    OText(g, "PEAK", 110, 44, 52, 16, 11, 0xFFD6EDFF, 0xFF0A1030, 2)
    OText(g, HudPeak, 110, 58, 52, 26, 20)
    Ball(g, 148, 24, 14, Now() - LastPress < 110)
}

RowLabel(g, y, txt) {
    OText(g, txt, 30, y, 190, 34, 15, 0xFFFFFFFF, 0xFF0A1030, 3, 0)
}

Stepper(win, g, y, label, id, valText) {
    RowLabel(g, y, label)
    Button(win, g, id "-", 206, y + 2, 36, 30, 6, "dark", "-", 20)
    OText(g, valText, 244, y, 76, 34, 16)
    Button(win, g, id "+", 322, y + 2, 36, 30, 6, "dark", "+", 20)
}

PaintSettings(win, g) {
    Plate(g, 8, 44, 364, 412, 14, "blue")
    Plate(g, 14, 4, 280, 44, 12, "dark")
    OText(g, "SETTINGS", 14, 4, 280, 44, 25)
    Button(win, g, "x", 306, 6, 58, 40, 10, "red", "X", 26)

    RowLabel(g, 62, "ALWAYS ON TOP")
    Button(win, g, "top", 232, 64, 126, 30, 7, C["onTop"] ? "green" : "red", C["onTop"] ? "ON" : "OFF", 16)

    RowLabel(g, 102, "ONLY IN ROBLOX")
    Button(win, g, "rbx", 232, 104, 126, 30, 7, C["onlyRoblox"] ? "green" : "red", C["onlyRoblox"] ? "ON" : "OFF", 16)

    Stepper(win, g, 142, "HUD OPACITY", "opacity", C["opacity"] . "%")

    FillPoly(g, Para(22, 182, 350, 3, 0), 0x66D6EDFF)
    n := C["keys"].Length
    RowLabel(g, 190, "KEYBINDS   " . n . " / " . MAXK)

    if (n = 0)
        OText(g, "NO KEYS YET - ADD ONE BELOW", 22, 226, 350, 34, 14, 0xFFD6EDFF, 0xFF0A1030, 2)
    for i, k in C["keys"] {
        lbl := ChipLabel(k)
        Button(win, g, "del_" . i, 22 + Mod(i - 1, 3) * 116, 226 + ((i - 1) // 3) * 40, 108, 34, 8, "dark", lbl, StrLen(lbl) > 5 ? 13 : 17)
    }

    addLbl := (n >= MAXK) ? "MAX KEYS" : (Capturing ? "PRESS A KEY..." : "+ ADD KEY")
    Button(win, g, "add", 22, 352, 226, 40, 9, "gold", addLbl, 17)
    Button(win, g, "reset", 256, 352, 116, 40, 9, "dark", "RESET PEAK", 13)

    if Capturing {
        OText(g, "PRESS ANY KEY OR MOUSE BUTTON", 22, 402, 350, 20, 12, 0xFFFFD84A, 0xFF0A1030, 2)
        OText(g, "ESC TO CANCEL", 22, 420, 350, 20, 12, 0xFFD6EDFF, 0xFF0A1030, 2)
    } else {
        OText(g, "CLICK A KEY TO REMOVE IT", 22, 402, 350, 20, 12, 0xFFD6EDFF, 0xFF0A1030, 2)
        OText(g, "RIGHT-CLICK THE HUD TO OPEN THIS MENU", 22, 420, 350, 20, 12, 0xFFD6EDFF, 0xFF0A1030, 2)
    }
}

; a window only repaints when its signature changes
SigHud(w) {
    return Format("{}|{}|{}|{}|{}", HudRate, HudPeak, C["opacity"], HudLabel(), (Now() - LastPress < 110) ? 1 : 0)
}
SigSettings(w) {
    blink := Capturing ? Mod(A_TickCount // 350, 2) : -1
    return Format("{}|{}|{}|{}|{}|{}", C["onTop"], C["onlyRoblox"], C["opacity"], KeysStr(), blink, w.hover)
}

; ------------------------------ window actions -----------------------------
SetVisible(win, on) {
    win.visible := on
    if on {
        win.gui.Show("NA")
        win.sig := ""
    } else
        win.gui.Hide()
}

ApplyTop() {
    WinSetAlwaysOnTop(C["onTop"] ? 1 : 0, "ahk_id " . HudWin.hwnd)
}

ShowSettings(nearHwnd) {
    if SetWin.visible {
        SetVisible(SetWin, false)
        return
    }
    wx := 0, wy := 0, ww := 0, wh := 0
    WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " nearHwnd)
    nx := Max(0, Min(wx + 12, A_ScreenWidth - SetWin.w))
    ny := wy + wh - 8
    if (ny + SetWin.h > A_ScreenHeight)
        ny := Max(0, wy - SetWin.h + 8)
    SetWin.gui.Show("NA x" nx " y" ny)
    SetWin.visible := true
    SetWin.sig := ""
}

ToggleHud(*) {
    C["hud"] := !C["hud"]
    SetVisible(HudWin, C["hud"])
    SaveCfg()
}

; ------------------------------ key binds ----------------------------------
; one ~* hotkey per bound key; the key passes through to the game untouched
ApplyBinds() {
    global BoundKeys
    for k in BoundKeys {
        try Hotkey("~*" k, "Off")
    }
    BoundKeys := []
    for k in C["keys"] {
        try {
            Hotkey("~*" k, PhysCount.Bind(k), "On")
            BoundKeys.Push(k)
        }
    }
}

PhysCount(k, *) {
    if (!Capturing && RobloxOK() && !(IsMouse(k) && OverOwnWindow()))
        RegisterPress()
    KeyWait(k)
}

AddBind(k) {
    if IdxOf(C["keys"], k) {
        Toast("ALREADY BOUND:  " . KeyLabel(k))
        return
    }
    C["keys"].Push(k)
    ApplyBinds()
    SaveCfg()
    Toast("ADDED  " . KeyLabel(k))
}

RemoveBind(i) {
    if (i < 1 || i > C["keys"].Length)
        return
    k := C["keys"].RemoveAt(i)
    ApplyBinds()
    SaveCfg()
    Toast("REMOVED  " . KeyLabel(k))
}

StartCapture() {
    global Capturing, CapArmed, CapStart
    if (C["keys"].Length >= MAXK) {
        Toast("MAX " . MAXK . " KEYS - REMOVE ONE FIRST")
        return
    }
    Capturing := true
    CapArmed := false
    CapStart := A_TickCount
    SetTimer(CapTick, 15)
}

CapStop() {
    global Capturing
    Capturing := false
    SetTimer(CapTick, 0)
}

CapTick() {
    global CapArmed
    if !CapArmed {
        ; wait for the click that opened the capture to be released
        if !GetKeyState("LButton", "P")
            CapArmed := true
        return
    }
    if (GetKeyState("Escape", "P") || A_TickCount - CapStart > 6000) {
        CapStop()
        return
    }
    Loop 254 {
        if (A_Index = 0x1B)                 ; Escape cancels, never bound
            continue
        vk := Format("vk{:02X}", A_Index)
        pressed := false
        try pressed := GetKeyState(vk, "P")
        if !pressed
            continue
        nm := GetKeyName(vk)
        if (nm = "")
            continue
        CapStop()
        AddBind(nm)
        return
    }
}

; ------------------------------ clicks -------------------------------------
Clicked(win, id) {
    if (SubStr(id, 1, 4) = "del_") {
        RemoveBind(Integer(SubStr(id, 5)))
        return
    }
    switch id {
        case "x":
            SetVisible(win, false)
        case "top":
            C["onTop"] := !C["onTop"]
            ApplyTop()
            SaveCfg()
        case "rbx":
            C["onlyRoblox"] := !C["onlyRoblox"]
            SaveCfg()
        case "add":
            StartCapture()
        case "reset":
            ResetStats()
        default:
            nm := SubStr(id, 1, -1)
            dr := SubStr(id, -1)
            if (ST.Has(nm) && (dr = "+" || dr = "-")) {
                sp := ST[nm]
                C[nm] := Max(sp[2], Min(sp[3], C[nm] + sp[1] * (dr = "+" ? 1 : -1)))
                SaveCfg()
            }
    }
}

WM_LDOWN(wParam, lParam, msg, hwnd) {
    if !Wins.Has(hwnd)
        return
    win := Wins[hwnd]
    x := lParam & 0xFFFF
    y := (lParam >> 16) & 0xFFFF
    for h in win.hits {
        if (x >= h[2] && x < h[2] + h[4] && y >= h[3] && y < h[3] + h[5]) {
            Clicked(win, h[1])
            return 0
        }
    }
    PostMessage(0xA1, 2, 0, , "ahk_id " hwnd)
    return 0
}

WM_RDOWN(wParam, lParam, msg, hwnd) {
    if (!Wins.Has(hwnd) || hwnd = SetWin.hwnd)
        return
    ShowSettings(hwnd)
    return 0
}

WM_EXITMOVE(wParam, lParam, msg, hwnd) {
    if (!Wins.Has(hwnd) || hwnd != HudWin.hwnd)
        return
    wx := 0, wy := 0
    WinGetPos(&wx, &wy, , , "ahk_id " hwnd)
    C["hudX"] := wx
    C["hudY"] := wy
    SaveCfg()
}

; ------------------------------ tick ---------------------------------------
UiTick() {
    global HudRate, HudPeak
    r := CurrentRate()
    HudRate := r
    if (r > HudPeak)
        HudPeak := r
    mx := 0, my := 0
    MouseGetPos(&mx, &my)
    for hwnd, w in Wins {
        if !w.visible
            continue
        hv := ""
        try {
            wx := 0, wy := 0
            WinGetPos(&wx, &wy, , , "ahk_id " hwnd)
            lx := mx - wx
            ly := my - wy
            for h in w.hits {
                if (lx >= h[2] && lx < h[2] + h[4] && ly >= h[3] && ly < h[3] + h[5]) {
                    hv := h[1]
                    break
                }
            }
        }
        w.hover := hv
        sg := w.sigFn.Call(w)
        if (sg != w.sig) {
            w.sig := sg
            w.Render()
        }
    }
}

Cleanup(*) {
    SaveCfg()
}

; ------------------------------ start up -----------------------------------
LoadCfg()
global GdipTok := GdipStart()
OnExit(Cleanup)

HudWin := BBWin(176, 96, PaintHud, SigHud, C["hudX"], C["hudY"], true, true)
SetWin := BBWin(380, 466, PaintSettings, SigSettings, 0, 0, false, true)
SetVisible(SetWin, false)
if !C["hud"]
    SetVisible(HudWin, false)
ApplyTop()
ApplyBinds()

OnMessage(0x201, WM_LDOWN)
OnMessage(0x204, WM_RDOWN)
OnMessage(0x232, WM_EXITMOVE)

A_TrayMenu.Delete()
A_TrayMenu.Add("Show / Hide HUD", ToggleHud)
A_TrayMenu.Add("Settings", (*) => ShowSettings(HudWin.hwnd))
A_TrayMenu.Add()
A_TrayMenu.Add("Exit", (*) => ExitApp())
A_TrayMenu.Default := "Show / Hide HUD"

SetTimer(UiTick, 45)
Toast("BLADE BALL CPS  -  RIGHT-CLICK THE HUD TO SET KEYS")
