#Requires AutoHotkey v2.0

; Increase max hotkeys per interval to avoid warnings
A_MaxHotkeysPerInterval := 250  ; default is 50

#SingleInstance Force
SendMode "Event"
SetKeyDelay 0, 20
SetMouseDelay -1
SetWinDelay -1
try ProcessSetPriority("BelowNormal")

; ==================== CONFIG ====================
monitorIndex      := 1        ; laptop's single display
marginTL          := 14       ; top-left corner size (px)
marginBL          := 14       ; bottom-left corner size (px)
pollMs            := 25

; Visuals
highlightTLColor  := "Red"    ; TL idle hover color
highlightTLAlpha  := 210
activeTLColor     := "Yellow" ; TL active (Alt+Tab open) color
activeTLAlpha     := 230
highlightBLColor  := "Gray"   ; BL hover color
highlightBLAlpha  := 160

; Timing
altTabOpenDelayMs := 100      ; time to let Alt+Tab render before first step
stepCooldownMs    := 70       ; minimum time between steps
; ================================================

; Auto-elevate
if !A_IsAdmin {
    try {
        Run('*RunAs "' A_ScriptFullPath '"')
        ExitApp
    }
}

CoordMode("Mouse", "Screen")

; Screen/work metrics
global lScr := 0, tScr := 0, rScr := 0, bScr := 0
global lWork := 0, tWork := 0, rWork := 0, bWork := 0
MonitorGet(monitorIndex, &lScr, &tScr, &rScr, &bScr)

; Previous metrics
global _prev_lScr := lScr, _prev_tScr := tScr, _prev_rScr := rScr, _prev_bScr := bScr

; State
global TL_inside := false, TL_altTabActive := false, BL_inside := false
global lastStepTick := 0, TL_firstScrollDone := false

; Click origin state
global LB_DownInTL := false, LB_DownInBL := false, LB_SentDown := false
global RB_DownInTL := false, RB_SentDown := false

; Overlay state
global tlGuardVisible := false, guardNeedsReposition := false
global tlHoverVisible := false, tlHoverActive := false, tlHoverNeedsReposition := false
global blHoverVisible := false, blHoverNeedsReposition := false

; ---------- Helpers ----------
IsInTopLeft() {
    MouseGetPos &mx, &my
    return (mx <= lScr + marginTL && my <= tScr + marginTL)
}
IsInBottomLeft() {
    MouseGetPos &mx, &my
    return (mx <= lScr + marginBL && my >= bScr - marginBL)
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
        , "uint", SWP_NOMOVE|SWP_NOSIZE|SWP_NOACTIVATE|SWP_SHOWWINDOW, "int")
}

UpdateMetrics(*) {
    global monitorIndex, lWork, tWork, rWork, bWork
    global lScr, tScr, rScr, bScr, _prev_lScr, _prev_tScr, _prev_rScr, _prev_bScr
    global guardNeedsReposition, tlHoverNeedsReposition, blHoverNeedsReposition
    global tlGuard, tlHover, blHover

    MonitorGetWorkArea(monitorIndex, &lWork, &tWork, &rWork, &bWork)
    MonitorGet(monitorIndex, &lScr, &tScr, &rScr, &bScr)

    if (lScr != _prev_lScr || tScr != _prev_tScr || rScr != _prev_rScr || bScr != _prev_bScr) {
        guardNeedsReposition := true
        tlHoverNeedsReposition := true
        blHoverNeedsReposition := true

        _prev_lScr := lScr
        _prev_tScr := tScr
        _prev_rScr := rScr
        _prev_bScr := bScr

        if IsSet(tlGuard)
            try KeepTopMost(tlGuard.Hwnd)
        if IsSet(tlHover)
            try KeepTopMost(tlHover.Hwnd)
        if IsSet(blHover)
            try KeepTopMost(blHover.Hwnd)
    }
}   ; ✅ THIS closing brace was missing in your version

; ---------- Overlays ----------
global tlGuard := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
tlGuard.BackColor := "Black"
tlGuard.Show(Format("x{} y{} w{} h{} NA", lScr, tScr, marginTL, marginTL))
try WinSetTransparent(1, "ahk_id " . tlGuard.Hwnd)
KeepTopMost(tlGuard.Hwnd)
tlGuardVisible := true

ShowTLGuard(show := true) {
    global tlGuard, tlGuardVisible, guardNeedsReposition
    if !IsSet(tlGuard)
        return
    if (show) {
        if (!tlGuardVisible) {
            tlGuard.Show(Format("x{} y{} w{} h{} NA", lScr, tScr, marginTL, marginTL))
            tlGuardVisible := true
            guardNeedsReposition := false
        } else if (guardNeedsReposition) {
            try WinMove(lScr, tScr, marginTL, marginTL, "ahk_id " . tlGuard.Hwnd)
            guardNeedsReposition := false
        }
    } else if (tlGuardVisible) {
        try tlGuard.Hide()
        tlGuardVisible := false
    }
}

global tlHover := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
tlHover.BackColor := highlightTLColor
tlHover.Show(Format("x{} y{} w{} h{} NA", lScr, tScr, marginTL, marginTL))
try WinSetTransparent(highlightTLAlpha, "ahk_id " . tlHover.Hwnd)
tlHover.Hide()
tlHoverVisible := false
tlHoverActive  := false

ShowTLHover(show := true, active := false) {
    global tlHover, tlHoverVisible, tlHoverActive, tlHoverNeedsReposition
    if (!IsSet(tlHover))
        return
    if (show) {
        if (!tlHoverVisible) {
            try tlHover.BackColor := active ? activeTLColor : highlightTLColor
            try WinSetTransparent(active ? activeTLAlpha : highlightTLAlpha, "ahk_id " . tlHover.Hwnd)
            tlHover.Show(Format("x{} y{} w{} h{} NA", lScr, tScr, marginTL, marginTL))
            tlHoverVisible := true
            tlHoverActive := active
            tlHoverNeedsReposition := false
        } else {
            if (tlHoverActive != active) {
                try tlHover.BackColor := active ? activeTLColor : highlightTLColor
                try WinSetTransparent(active ? activeTLAlpha : highlightTLAlpha, "ahk_id " . tlHover.Hwnd)
                tlHoverActive := active
            }
            if (tlHoverNeedsReposition) {
                try WinMove(lScr, tScr, marginTL, marginTL, "ahk_id " . tlHover.Hwnd)
                tlHoverNeedsReposition := false
            }
        }
    } else if (tlHoverVisible) {
        try tlHover.Hide()
        tlHoverVisible := false
        tlHoverActive := false
        tlHoverNeedsReposition := false
    }
}

global blHover := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
blHover.BackColor := highlightBLColor
blHover.Show(Format("x{} y{} w{} h{} NA", lScr, bScr - marginBL, marginBL, marginBL))
try WinSetTransparent(highlightBLAlpha, "ahk_id " . blHover.Hwnd)
blHover.Hide()
blHoverVisible := false

ShowBLHover(show := true) {
    global blHover, blHoverVisible, blHoverNeedsReposition
    if (!IsSet(blHover))
        return
    if (show) {
        if (!blHoverVisible) {
            blHover.BackColor := highlightBLColor
            try WinSetTransparent(highlightBLAlpha, "ahk_id " . blHover.Hwnd)
            blHover.Show(Format("x{} y{} w{} h{} NA", lScr, bScr - marginBL, marginBL, marginBL))
            blHoverVisible := true
            blHoverNeedsReposition := false
        } else if (blHoverNeedsReposition) {
            try WinMove(lScr, bScr - marginBL, marginBL, marginBL, "ahk_id " . blHover.Hwnd)
            blHoverNeedsReposition := false
        }
    } else if (blHoverVisible) {
        try blHover.Hide()
        blHoverVisible := false
        blHoverNeedsReposition := false
    }
}

; ---------- Loop ----------
SetTimer(UpdateMetrics, 1500)
SetTimer(CornerLoop, pollMs)

CornerLoop() {
    global TL_inside, TL_altTabActive, BL_inside, TL_firstScrollDone
    global tlHoverVisible

    curTL := IsInTopLeft()
    if (curTL && !TL_inside) {
        TL_inside := true
        ShowTLGuard(true)
        ShowTLHover(true, TL_altTabActive)
    } else if (!curTL && TL_inside) {
        TL_inside := false
        ShowTLHover(false, false)
        EndAltTabIfActive()
        TL_firstScrollDone := false
    } else if (curTL) {
        ShowTLGuard(true)
        ShowTLHover(true, TL_altTabActive)
    } else if (tlHoverVisible) {
        ShowTLHover(false, false)
    }

    curBL := IsInBottomLeft()
    if (curBL && !BL_inside) {
        BL_inside := true
        ShowBLHover(true)
    } else if (!curBL && BL_inside) {
        BL_inside := false
        ShowBLHover(false)
    } else if (curBL) {
        ShowBLHover(true)
    }
}

; ---------- Alt+Tab control ----------
OpenSwitcherIfNeeded() {
    global TL_altTabActive
    if (TL_altTabActive)
        return
    SendEvent("{Blind}{Alt down}")
    Sleep(40)
    SendEvent("{Blind}{Tab}")
    Sleep(altTabOpenDelayMs)
    SendEvent("{Blind}+{Tab}")
    TL_altTabActive := true
    ShowTLHover(true, true)
}
StepRight() {
    if (!TL_altTabActive)
        return
    SendEvent("{Blind}{Right}")
    Sleep(10)
}
StepLeft() {
    if (!TL_altTabActive)
        return
    SendEvent("{Blind}{Left}")
    Sleep(10)
}
EndAltTabIfActive() {
    global TL_altTabActive, TL_firstScrollDone
    if (TL_altTabActive) {
        SendEvent("{Blind}{Alt up}")
        TL_altTabActive := false
        ShowTLHover(true, false)
    }
    TL_firstScrollDone := false
}

; ---------- Window control ----------
ToggleMaxMin() {
    hwnd := WinGetID("A")
    if !hwnd
        return
    mm := WinGetMinMax("ahk_id " . hwnd)
    if (mm = 1)
        WinMinimize("ahk_id " . hwnd)
    else
        WinMaximize("ahk_id " . hwnd)
}
InstantSwitchRecent() {
    SendEvent("{Blind}{Alt down}")
    Sleep(30)
    SendEvent("{Blind}{Tab}")
    Sleep(30)
    SendEvent("{Blind}{Alt up}")
}

; ---------- Mouse Wheel Hotkeys ----------
*WheelDown:: {
    global TL_firstScrollDone, TL_altTabActive
    if (IsInTopLeft()) {
        if (!TL_altTabActive) {
            OpenSwitcherIfNeeded()
            TL_firstScrollDone := true
        } else if (!TL_firstScrollDone) {
            TL_firstScrollDone := true
        } else if (CanStep()) {
            StepLeft()
        }
    } else {
        if (TL_altTabActive)
            EndAltTabIfActive()
        SendEvent("{WheelDown}")
    }
}
*WheelUp:: {
    global TL_firstScrollDone, TL_altTabActive
    if (IsInTopLeft()) {
        if (!TL_altTabActive) {
            OpenSwitcherIfNeeded()
            TL_firstScrollDone := true
        } else if (!TL_firstScrollDone) {
            TL_firstScrollDone := true
        } else if (CanStep()) {
            StepRight()
        }
    } else {
        if (TL_altTabActive)
            EndAltTabIfActive()
        SendEvent("{WheelUp}")
    }
}

; ---------- Click handlers ----------
*LButton:: {
    global LB_DownInTL, LB_DownInBL, LB_SentDown
    LB_DownInTL := IsInTopLeft()
    LB_DownInBL := IsInBottomLeft()
    if (!LB_DownInTL && !LB_DownInBL) {
        SendEvent("{LButton down}")
        LB_SentDown := true
    } else {
        LB_SentDown := false
    }
}
*LButton Up:: {
    global LB_DownInTL, LB_DownInBL, LB_SentDown
    if (LB_DownInTL && IsInTopLeft()) {
        EndAltTabIfActive()
        InstantSwitchRecent()
    } else if (LB_DownInBL && IsInBottomLeft()) {
        EndAltTabIfActive()
        SendEvent("#{Tab}")
    } else if (LB_SentDown) {
        SendEvent("{LButton up}")
    }
    LB_DownInTL := false
    LB_DownInBL := false
    LB_SentDown := false
}

*RButton:: {
    global RB_DownInTL, RB_SentDown
    RB_DownInTL := IsInTopLeft()
    if (!RB_DownInTL) {
        SendEvent("{RButton down}")
        RB_SentDown := true
    } else {
        RB_SentDown := false
    }
}
*RButton Up:: {
    global RB_DownInTL, RB_SentDown
    if (RB_DownInTL && IsInTopLeft()) {
        EndAltTabIfActive()
        ToggleMaxMin()
    } else if (RB_SentDown) {
        SendEvent("{RButton up}")
    }
    RB_DownInTL := false
    RB_SentDown := false
}

; ---------- Fix Ctrl ----------
*Ctrl::SendEvent("{Ctrl down}")
*Ctrl Up::SendEvent("{Ctrl up}")

; ---------- Safety ----------
OnExit(Cleanup)
Cleanup(Reason, Code) {
    try SendEvent("{Blind}{Alt up}")
    if (tlHoverVisible)
        ShowTLHover(false, false)
    if (blHoverVisible)
        ShowBLHover(false)
}

