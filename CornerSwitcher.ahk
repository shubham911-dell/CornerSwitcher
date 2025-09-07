; AutoHotkey v1.1.37.2
; Converted from AHK v2 keeping functionality intact

#SingleInstance, Force
#MaxHotkeysPerInterval 250

SendMode, Event
SetKeyDelay, 0, 20
SetMouseDelay, -1
SetWinDelay, -1
Process, Priority,, BelowNormal

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
if !A_IsAdmin
{
    Run, *RunAs "%A_ScriptFullPath%"
    ExitApp
}

CoordMode, Mouse, Screen

; Screen/work metrics
lScr := 0, tScr := 0, rScr := 0, bScr := 0
lWork := 0, tWork := 0, rWork := 0, bWork := 0

; Initialize monitor metrics
SysGet, WA, MonitorWorkArea, %monitorIndex%
lWork := WALeft, tWork := WATop, rWork := WARight, bWork := WABottom
SysGet, Mon, Monitor, %monitorIndex%
lScr := MonLeft, tScr := MonTop, rScr := MonRight, bScr := MonBottom

; Previous metrics
_prev_lScr := lScr, _prev_tScr := tScr, _prev_rScr := rScr, _prev_bScr := bScr

; State
TL_inside := false, TL_altTabActive := false, BL_inside := false
lastStepTick := 0, TL_firstScrollDone := false

; Click origin state
LB_DownInTL := false, LB_DownInBL := false, LB_SentDown := false
RB_DownInTL := false, RB_SentDown := false

; Overlay state
tlGuardVisible := false, guardNeedsReposition := false
tlHoverVisible := false, tlHoverActive := false, tlHoverNeedsReposition := false
blHoverVisible := false, blHoverNeedsReposition := false

; ---------- Helpers ----------
IsInTopLeft() {
    global lScr, tScr, marginTL
    MouseGetPos, mx, my
    return (mx <= lScr + marginTL && my <= tScr + marginTL)
}
IsInBottomLeft() {
    global lScr, bScr, marginBL
    MouseGetPos, mx, my
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
        , "Ptr", hwnd
        , "Ptr", -1
        , "Int", 0, "Int", 0, "Int", 0, "Int", 0
        , "UInt", SWP_NOMOVE|SWP_NOSIZE|SWP_NOACTIVATE|SWP_SHOWWINDOW)
}

UpdateMetrics() {
    global monitorIndex, lWork, tWork, rWork, bWork
    global lScr, tScr, rScr, bScr, _prev_lScr, _prev_tScr, _prev_rScr, _prev_bScr
    global guardNeedsReposition, tlHoverNeedsReposition, blHoverNeedsReposition
    global tlGuardHwnd, tlHoverHwnd, blHoverHwnd

    SysGet, WA, MonitorWorkArea, %monitorIndex%
    lWork := WALeft, tWork := WATop, rWork := WARight, bWork := WABottom
    SysGet, Mon, Monitor, %monitorIndex%
    lScr := MonLeft, tScr := MonTop, rScr := MonRight, bScr := MonBottom

    if (lScr != _prev_lScr || tScr != _prev_tScr || rScr != _prev_rScr || bScr != _prev_bScr) {
        guardNeedsReposition := true
        tlHoverNeedsReposition := true
        blHoverNeedsReposition := true

        _prev_lScr := lScr
        _prev_tScr := tScr
        _prev_rScr := rScr
        _prev_bScr := bScr

        if (tlGuardHwnd)
            KeepTopMost(tlGuardHwnd)
        if (tlHoverHwnd)
            KeepTopMost(tlHoverHwnd)
        if (blHoverHwnd)
            KeepTopMost(blHoverHwnd)
    }
}

; ---------- Overlays ----------
Gui, tlGuard: New, +AlwaysOnTop -Caption +ToolWindow +E0x20 +HwndtlGuardHwnd
Gui, tlGuard: Color, Black
Gui, tlGuard: Show, % "x" lScr " y" tScr " w" marginTL " h" marginTL " NA"
WinSet, Transparent, 1, ahk_id %tlGuardHwnd%
KeepTopMost(tlGuardHwnd)
tlGuardVisible := true

ShowTLGuard(show := true) {
    global tlGuardHwnd, tlGuardVisible, guardNeedsReposition
    global lScr, tScr, marginTL
    if (show) {
        if (!tlGuardVisible) {
            Gui, tlGuard: Show, % "x" lScr " y" tScr " w" marginTL " h" marginTL " NA"
            tlGuardVisible := true
            guardNeedsReposition := false
        } else if (guardNeedsReposition) {
            WinMove, ahk_id %tlGuardHwnd%, , %lScr%, %tScr%, %marginTL%, %marginTL%
            guardNeedsReposition := false
        }
    } else if (tlGuardVisible) {
        Gui, tlGuard: Hide
        tlGuardVisible := false
    }
}

Gui, tlHover: New, +AlwaysOnTop -Caption +ToolWindow +E0x20 +HwndtlHoverHwnd
Gui, tlHover: Color, %highlightTLColor%
Gui, tlHover: Show, % "x" lScr " y" tScr " w" marginTL " h" marginTL " NA"
WinSet, Transparent, %highlightTLAlpha%, ahk_id %tlHoverHwnd%
Gui, tlHover: Hide
tlHoverVisible := false
tlHoverActive  := false

ShowTLHover(show := true, active := false) {
    global tlHoverHwnd, tlHoverVisible, tlHoverActive, tlHoverNeedsReposition
    global lScr, tScr, marginTL
    global highlightTLColor, highlightTLAlpha, activeTLColor, activeTLAlpha

    if (show) {
        if (!tlHoverVisible) {
            color := active ? activeTLColor : highlightTLColor
            alpha := active ? activeTLAlpha : highlightTLAlpha
            Gui, tlHover: Color, %color%
            WinSet, Transparent, %alpha%, ahk_id %tlHoverHwnd%
            Gui, tlHover: Show, % "x" lScr " y" tScr " w" marginTL " h" marginTL " NA"
            tlHoverVisible := true
            tlHoverActive := active
            tlHoverNeedsReposition := false
        } else {
            if (tlHoverActive != active) {
                color := active ? activeTLColor : highlightTLColor
                alpha := active ? activeTLAlpha : highlightTLAlpha
                Gui, tlHover: Color, %color%
                WinSet, Transparent, %alpha%, ahk_id %tlHoverHwnd%
                tlHoverActive := active
            }
            if (tlHoverNeedsReposition) {
                WinMove, ahk_id %tlHoverHwnd%, , %lScr%, %tScr%, %marginTL%, %marginTL%
                tlHoverNeedsReposition := false
            }
        }
    } else if (tlHoverVisible) {
        Gui, tlHover: Hide
        tlHoverVisible := false
        tlHoverActive := false
        tlHoverNeedsReposition := false
    }
}

Gui, blHover: New, +AlwaysOnTop -Caption +ToolWindow +E0x20 +HwndblHoverHwnd
Gui, blHover: Color, %highlightBLColor%
Gui, blHover: Show, % "x" lScr " y" (bScr - marginBL) " w" marginBL " h" marginBL " NA"
WinSet, Transparent, %highlightBLAlpha%, ahk_id %blHoverHwnd%
Gui, blHover: Hide
blHoverVisible := false

ShowBLHover(show := true) {
    global blHoverHwnd, blHoverVisible, blHoverNeedsReposition
    global lScr, bScr, marginBL, highlightBLColor, highlightBLAlpha

    if (show) {
        if (!blHoverVisible) {
            Gui, blHover: Color, %highlightBLColor%
            WinSet, Transparent, %highlightBLAlpha%, ahk_id %blHoverHwnd%
            Gui, blHover: Show, % "x" lScr " y" (bScr - marginBL) " w" marginBL " h" marginBL " NA"
            blHoverVisible := true
            blHoverNeedsReposition := false
        } else if (blHoverNeedsReposition) {
            WinMove, ahk_id %blHoverHwnd%, , %lScr%, % (bScr - marginBL), %marginBL%, %marginBL%
            blHoverNeedsReposition := false
        }
    } else if (blHoverVisible) {
        Gui, blHover: Hide
        blHoverVisible := false
        blHoverNeedsReposition := false
    }
}

; ---------- Loop ----------
SetTimer, UpdateMetrics, 1500
SetTimer, CornerLoop, %pollMs%

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
    global TL_altTabActive, altTabOpenDelayMs
    if (TL_altTabActive)
        return
    SendEvent, {Blind}{Alt down}
    Sleep, 40
    SendEvent, {Blind}{Tab}
    Sleep, %altTabOpenDelayMs%
    SendEvent, {Blind}+{Tab}
    TL_altTabActive := true
    ShowTLHover(true, true)
}
StepRight() {
    global TL_altTabActive
    if (!TL_altTabActive)
        return
    SendEvent, {Blind}{Right}
    Sleep, 10
}
StepLeft() {
    global TL_altTabActive
    if (!TL_altTabActive)
        return
    SendEvent, {Blind}{Left}
    Sleep, 10
}
EndAltTabIfActive() {
    global TL_altTabActive, TL_firstScrollDone
    if (TL_altTabActive) {
        SendEvent, {Blind}{Alt up}
        TL_altTabActive := false
        ShowTLHover(true, false)
    }
    TL_firstScrollDone := false
}

; ---------- Window control ----------
ToggleMaxMin() {
    WinGet, hwnd, ID, A
    if !hwnd
        return
    WinGet, mm, MinMax, ahk_id %hwnd%
    if (mm = 1)
        WinMinimize, ahk_id %hwnd%
    else
        WinMaximize, ahk_id %hwnd%
}
InstantSwitchRecent() {
    SendEvent, {Blind}{Alt down}
    Sleep, 30
    SendEvent, {Blind}{Tab}
    Sleep, 30
    SendEvent, {Blind}{Alt up}
}

; ---------- Mouse Wheel Hotkeys ----------
*WheelDown::
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
    SendEvent, {WheelDown}
}
return

*WheelUp::
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
    SendEvent, {WheelUp}
}
return

; ---------- Click handlers ----------
*LButton::
LB_DownInTL := IsInTopLeft()
LB_DownInBL := IsInBottomLeft()
if (!LB_DownInTL && !LB_DownInBL) {
    SendEvent, {LButton down}
    LB_SentDown := true
} else {
    LB_SentDown := false
}
return

*LButton Up::
if (LB_DownInTL && IsInTopLeft()) {
    EndAltTabIfActive()
    InstantSwitchRecent()
} else if (LB_DownInBL && IsInBottomLeft()) {
    EndAltTabIfActive()
    SendEvent, #{Tab}
} else if (LB_SentDown) {
    SendEvent, {LButton up}
}
LB_DownInTL := false
LB_DownInBL := false
LB_SentDown := false
return

*RButton::
RB_DownInTL := IsInTopLeft()
if (!RB_DownInTL) {
    SendEvent, {RButton down}
    RB_SentDown := true
} else {
    RB_SentDown := false
}
return

*RButton Up::
if (RB_DownInTL && IsInTopLeft()) {
    EndAltTabIfActive()
    ToggleMaxMin()
} else if (RB_SentDown) {
    SendEvent, {RButton up}
}
RB_DownInTL := false
RB_SentDown := false
return

; ---------- Fix Ctrl ----------
*Ctrl:: 
SendEvent, {Ctrl down}
return

*Ctrl Up::
SendEvent, {Ctrl up}
return

; ---------- Safety ----------
OnExit, Cleanup

Cleanup:
    SendEvent, {Blind}{Alt up}
    if (tlHoverVisible)
        ShowTLHover(false, false)
    if (blHoverVisible)
        ShowBLHover(false)
ExitApp
