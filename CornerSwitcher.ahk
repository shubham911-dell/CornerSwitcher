#Requires AutoHotkey v2.0
#SingleInstance Force
SendMode "Event"
SetKeyDelay 0, 20
SetMouseDelay -1

; ==================== CONFIG ====================
monitorIndex      := 1        ; laptop's single display
marginTL          := 14       ; top-left corner size (px)
marginBL          := 14       ; bottom-left corner size (px)
pollMs            := 25

; Visuals
highlightTLColor  := "Yellow" ; TL idle hover color
highlightTLAlpha  := 210
activeTLColor     := "Aqua"   ; TL active (Alt+Tab open) color
activeTLAlpha     := 230
highlightBLColor  := "Lime"   ; BL hover color
highlightBLAlpha  := 160

; Timing
altTabOpenDelayMs := 100      ; time to let Alt+Tab render before first step (increase if needed)
stepCooldownMs    := 70       ; minimum time between steps (prevents missed steps)
; ================================================

; Auto-elevate for reliable keystrokes
if !A_IsAdmin {
    try {
        Run '*RunAs "' A_ScriptFullPath '"'
        ExitApp
    }
}

CoordMode "Mouse", "Screen"

; Screen/work metrics
global lScr := 0, tScr := 0, rScr := 0, bScr := 0
global lWork := 0, tWork := 0, rWork := 0, bWork := 0
MonitorGet monitorIndex, &lScr, &tScr, &rScr, &bScr
UpdateMetrics()
SetTimer UpdateMetrics, 1500

; State
global TL_inside := false
global TL_altTabActive := false
global BL_inside := false
global lastStepTick := 0

; ---------- Helpers ----------
IsInTopLeft() {
    MouseGetPos &mx, &my
    return (mx <= lScr + marginTL && my <= tScr + marginTL)
}
IsInBottomLeft() {
    MouseGetPos &mx, &my
    return (mx <= lWork + marginBL && my >= bWork - marginBL)
}
CanStep() {
    global lastStepTick, stepCooldownMs
    now := A_TickCount
    if (now - lastStepTick >= stepCooldownMs) {
        lastStepTick := now
        return true
    }
    return false
}
KeepTopMost(hwnd) {
    if !hwnd
        return
    static SWP_NOSIZE := 0x0001
    static SWP_NOMOVE := 0x0002
    static SWP_NOACTIVATE := 0x0010
    static SWP_SHOWWINDOW := 0x0040
    DllCall("SetWindowPos"
        , "ptr", hwnd
        , "ptr", -1
        , "int", 0, "int", 0, "int", 0, "int", 0
        , "uint", SWP_NOMOVE|SWP_NOSIZE|SWP_NOACTIVATE|SWP_SHOWWINDOW)
}
UpdateMetrics(*) {
    MonitorGetWorkArea monitorIndex, &lWork, &tWork, &rWork, &bWork
    MonitorGet monitorIndex, &lScr, &tScr, &rScr, &bScr
    ShowTLGuard()
    ShowTLHover(false)
    ShowBLHover(false)
}

; ---------- Overlays ----------
; TL guard: always-on-top, click-through, ultra-transparent
global tlGuard := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
tlGuard.BackColor := "Black"
tlGuard.Show(Format("x{} y{} w{} h{} NA", lScr, tScr, marginTL, marginTL))
try WinSetTransparent 1, "ahk_id " . tlGuard.Hwnd
KeepTopMost tlGuard.Hwnd

ShowTLGuard() {
    if !IsSet(tlGuard)
        return
    tlGuard.Show(Format("x{} y{} w{} h{} NA", lScr, tScr, marginTL, marginTL))
    KeepTopMost tlGuard.Hwnd
}

; TL hover indicator
global tlHover := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
tlHover.BackColor := highlightTLColor
tlHover.Show(Format("x{} y{} w{} h{} NA", lScr, tScr, marginTL, marginTL))
try WinSetTransparent highlightTLAlpha, "ahk_id " . tlHover.Hwnd
tlHover.Hide()

ShowTLHover(show := true, active := false) {
    if (!IsSet(tlHover))
        return
    if (show) {
        tlHover.BackColor := active ? activeTLColor : highlightTLColor
        try WinSetTransparent active ? activeTLAlpha : highlightTLAlpha, "ahk_id " . tlHover.Hwnd
        tlHover.Show(Format("x{} y{} w{} h{} NA", lScr, tScr, marginTL, marginTL))
    } else {
        if WinExist("ahk_id " . tlHover.Hwnd)
            tlHover.Hide()
    }
}

; BL hover indicator
global blHover := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
blHover.BackColor := highlightBLColor
blHover.Show(Format("x{} y{} w{} h{} NA", lScr, bWork - marginBL, marginBL, marginBL))
try WinSetTransparent highlightBLAlpha, "ahk_id " . blHover.Hwnd
blHover.Hide()

ShowBLHover(show := true) {
    if (!IsSet(blHover))
        return
    if (show) {
        blHover.BackColor := highlightBLColor
        try WinSetTransparent highlightBLAlpha, "ahk_id " . blHover.Hwnd
        blHover.Show(Format("x{} y{} w{} h{} NA", lScr, bWork - marginBL, marginBL, marginBL))
    } else {
        if WinExist("ahk_id " . blHover.Hwnd)
            blHover.Hide()
    }
}

; ---------- Loop ----------
SetTimer CornerLoop, pollMs

CornerLoop() {
    global TL_inside, TL_altTabActive, BL_inside

    ; TL behavior: hover does nothing (only shows indicator)
    curTL := IsInTopLeft()
    if (curTL && !TL_inside) {
        TL_inside := true
        ShowTLGuard()
        ShowTLHover(true, false)
    } else if (!curTL && TL_inside) {
        TL_inside := false
        ShowTLHover(false, false)
        EndAltTabIfActive()
    } else if (curTL) {
        ShowTLGuard()
        ShowTLHover(true, TL_altTabActive)
    }

    ; BL hover indicator
    curBL := IsInBottomLeft()
    if (curBL && !BL_inside) {
        BL_inside := true
        ShowBLHover(true)
    } else if (!curBL && BL_inside) {
        BL_inside := false
        ShowBLHover(false)
    }
}

; ---------- Alt+Tab control ----------
OpenSwitcherIfNeeded() {
    global TL_altTabActive
    if (TL_altTabActive)
        return
    ; Hold Alt, show grid (Tab), then neutralize initial step with Shift+Tab
    SendEvent "{Blind}{Alt down}"
    Sleep 40
    SendEvent "{Blind}{Tab}"
    Sleep altTabOpenDelayMs
    SendEvent "{Blind}+{Tab}"
    TL_altTabActive := true
    ShowTLHover(true, true)
}
StepRight() {
    if (!TL_altTabActive)
        return
    ; Move selection right (next app)
    SendEvent "{Blind}{Right}"
    Sleep 10
}
StepLeft() {
    if (!TL_altTabActive)
        return
    ; Move selection left (previous app)
    SendEvent "{Blind}{Left}"
    Sleep 10
}
EndAltTabIfActive() {
    global TL_altTabActive
    if (TL_altTabActive) {
        SendEvent "{Blind}{Alt up}"
        TL_altTabActive := false
        ShowTLHover(true, false)
    }
}

; ---------- Window control ----------
ToggleMaxMin() {
    hwnd := WinGetID("A")
    if !hwnd
        return
    mm := WinGetMinMax("ahk_id " . hwnd) ; 1 = maximized, -1 = minimized, 0 = normal
    if (mm = 1)
        WinMinimize "ahk_id " . hwnd
    else
        WinMaximize "ahk_id " . hwnd
}
InstantSwitchRecent() {
    ; Alt down -> Tab -> Alt up (instant recent app)
    SendEvent "{Blind}{Alt down}"
    Sleep 30
    SendEvent "{Blind}{Tab}"
    Sleep 30
    SendEvent "{Blind}{Alt up}"
}

; ---------- Global mouse handlers (wildcard: work even while Alt is held) ----------
; Using wildcard (*) ensures scroll still triggers when Alt-Tab UI is visible
*WheelDown::
{
    if (IsInTopLeft()) {
        OpenSwitcherIfNeeded()
        if (CanStep())
            StepLeft()
    } else {
        SendEvent "{WheelDown}"
    }
    return
}
*WheelUp::
{
    if (IsInTopLeft()) {
        OpenSwitcherIfNeeded()
        if (CanStep())
            StepRight()
    } else {
        SendEvent "{WheelUp}"
    }
    return
}

; Left click
*LButton::
{
    if (!IsInTopLeft() && !IsInBottomLeft())
        SendEvent "{LButton down}"
    return
}
*LButton Up::
{
    if (IsInTopLeft()) {
        EndAltTabIfActive()
        InstantSwitchRecent()
    } else if (IsInBottomLeft()) {
        EndAltTabIfActive()
        SendEvent "#{Tab}"   ; Task View
    } else {
        SendEvent "{LButton up}"
    }
    return
}

; Right click
*RButton::
{
    if (!IsInTopLeft())
        SendEvent "{RButton down}"
    return
}
*RButton Up::
{
    if (IsInTopLeft()) {
        EndAltTabIfActive()
        ToggleMaxMin()
    } else {
        SendEvent "{RButton up}"
    }
    return
}
; ---------- Fix: Let Ctrl work normally ----------
*Ctrl::SendEvent "{Ctrl down}"
*Ctrl Up::SendEvent "{Ctrl up}"


; ---------- Safety ----------
OnExit Cleanup
Cleanup(Reason, Code) {
    SendEvent "{Blind}{Alt up}"
}
