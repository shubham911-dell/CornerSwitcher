; ====================================================================
; Stable corner nav, chording, and browser zoom (Windows-like pacing)
; ====================================================================

#NoEnv
#SingleInstance Force
#InstallMouseHook
#InstallKeybdHook
#UseHook
SendMode Input
SetBatchLines -1
ListLines Off
; Use Windows-like defaults instead of hyper-fast settings
SetKeyDelay, 10, 10
SetMouseDelay, 10
SetDefaultMouseSpeed, 2
CoordMode, Mouse, Screen
; Removed High priority for a more native feel
; Process, Priority,, High

; ---------------------------- Auto-elevate -----------------------------
if !A_IsAdmin
{
    Try
    {
        Run *RunAs "%A_ScriptFullPath%",, Hide
        ExitApp
    }
}

; ============================ SETTINGS ================================
NavMethod := "AltArrows"      ; "AltArrows" or "XButtons"
monitorIndex := 1

; Corner hit areas
marginTL := 20
marginBL := 20

; Behavior
DisableInFullscreen := true
pollMs := 25                  ; slightly slower polling (more natural)

; Multi-click timing for top-left corner
multiClickWindow := 400        ; 400ms window for multi-clicks
tlClickCount := 0
tlLastClickTime := 0

; Alt-Tab pinning
altTabPinned := false          ; right-click pin state

; Visuals (hover only; no permanent guard window)
highlightTLColor := "FF0000"   ; red when hovering TL
highlightTLAlpha := 180
activeTLColor    := "FFFF00"   ; yellow when Alt+Tab is active
activeTLAlpha    := 200
highlightBLColor := "888888"   ; gray when hovering BL
highlightBLAlpha := 160

; Alt-Tab behavior (Windows-like pacing)
altTabOpenDelayMs   := 120     ; small delay after opening Alt-Tab
stepDelayMs := 80              ; delay between Tab presses for animation
; Commit rule: ONLY when leaving TL area or on click inside TL (no idle commit)
stepCooldownMs      := 120     ; throttle stepping to match Windows feel

; Watchdog
stuckKeyCheckMs     := 700     ; release Alt/Ctrl/Shift quickly if they get stuck
; =====================================================================

; ---------------------------- Internal state --------------------------
; Chording and zoom
RDown := false
RSolo := false
LDown := false
SuppressRUp := false
SuppressLUp := false
BlockNextSoloRClick := false
Sending := false
ZoomActive := false
ZoomUsed := false

; Corner state
TL_inside := false
BL_inside := false
g_IsAltTabActive := false   ; renamed for clarity
lastStepTick := 0

; Corner buttons state
LB_DownInTL := false
LB_DownInBL := false
RB_DownInTL := false

; Overlay handles/visibility
tlHoverHwnd := 0, blHoverHwnd := 0
tlHoverVisible := false, blHoverVisible := false

; Screen/work area
lScr := 0, tScr := 0, rScr := 0, bScr := 0
lWork := 0, tWork := 0, rWork := 0, bWork := 0
; =====================================================================

; ------------------------------ Metrics -------------------------------
ReadMonitorMetrics()
{
    global monitorIndex, lScr, tScr, rScr, bScr, lWork, tWork, rWork, bWork
    SysGet, Mon, Monitor, %monitorIndex%
    lScr := MonLeft, tScr := MonTop, rScr := MonRight, bScr := MonBottom
    SysGet, WA, MonitorWorkArea, %monitorIndex%
    lWork := WALeft, tWork := WATop, rWork := WARight, bWork := WABottom
}
ReadMonitorMetrics()

OnMessage(0x007E, "OnDisplayChange")
OnDisplayChange(wParam, lParam, msg, hwnd)
{
    ReadMonitorMetrics()
    RepositionOverlays()
}

; ----------------------------- Helpers --------------------------------
IsInTopLeft()
{
    global lScr, tScr, marginTL
    MouseGetPos, mx, my
    return (mx <= lScr + marginTL && my <= tScr + marginTL)
}

IsInBottomLeft()
{
    global lScr, bScr, marginBL
    MouseGetPos, mx, my
    return (mx <= lScr + marginBL && my >= bScr - marginBL)
}

IsFullscreenActive()
{
    global DisableInFullscreen, lScr, tScr, rScr, bScr
    if (!DisableInFullscreen)
        return false

    WinGet, hwnd, ID, A
    if !hwnd
        return false

    WinGet, style, Style, ahk_id %hwnd%
    ; If no caption and it covers the screen -> likely fullscreen
    if !(style & 0xC00000)  ; WS_CAPTION
    {
        WinGetPos, wx, wy, ww, wh, ahk_id %hwnd%
        if (wx <= lScr && wy <= tScr && wx + ww >= rScr && wy + wh >= bScr)
            return true
    }
    return false
}

AppIsBrowser()
{
    WinGet, pn, ProcessName, A
    StringLower, pn, pn
    if pn in chrome.exe,msedge.exe,brave.exe,opera.exe,opera_gx.exe,vivaldi.exe,firefox.exe
        return true
    return false
}

IsAltTabActive()
{
    global g_IsAltTabActive
    return g_IsAltTabActive
}

ShouldHandleRButton()
{
    return (!IsInTopLeft() && !IsAltTabActive() && !IsFullscreenActive())
}

ShouldHandleLeftChord()
{
    global RDown, SuppressLUp
    return (!IsInTopLeft() && !IsAltTabActive() && !IsFullscreenActive() && (GetKeyState("RButton","P") || RDown || SuppressLUp))
}

CanStep()
{
    global lastStepTick, stepCooldownMs
    now := A_TickCount
    if (now - lastStepTick >= stepCooldownMs)
    {
        lastStepTick := now
        return true
    }
    return false
}

NavBack()
{
    global NavMethod
    if (NavMethod = "XButtons")
        SendEvent {XButton1}
    else
    {
        SendEvent {Alt down}
        Sleep, 20
        SendEvent {Left}
        Sleep, 20
        SendEvent {Alt up}
    }
}

NavForward()
{
    global NavMethod
    if (NavMethod = "XButtons")
        SendEvent {XButton2}
    else
    {
        SendEvent {Alt down}
        Sleep, 20
        SendEvent {Right}
        Sleep, 20
        SendEvent {Alt up}
    }
}

ForceReleaseMods()
{
    if GetKeyState("Alt","P")
        SendEvent {Alt up}
    if GetKeyState("Ctrl","P")
        SendEvent {Ctrl up}
    if GetKeyState("Shift","P")
        SendEvent {Shift up}
}

; --------------------------- Overlays (hover only) ---------------------
CreateOverlays()
{
    global tlHoverHwnd, blHoverHwnd, tlHoverVisible, blHoverVisible
    global lScr, tScr, bScr, marginTL, marginBL, highlightTLColor, highlightTLAlpha
    global highlightBLColor, highlightBLAlpha

    ; Top-left hover indicator - THIN LINE (2px height like Windows Show Desktop)
    Gui, tlHover: New, +AlwaysOnTop -Caption +ToolWindow +E0x20 +HwndtlHoverHwnd
    Gui, tlHover: Color, %highlightTLColor%
    Gui, tlHover: Show, % "x" lScr " y" tScr " w" marginTL " h2 NA"  ; 2px height
    WinSet, Transparent, %highlightTLAlpha%, ahk_id %tlHoverHwnd%
    tlHoverVisible := false
    Gui, tlHover: Hide

    ; Bottom-left hover indicator - THIN LINE (2px height)
    Gui, blHover: New, +AlwaysOnTop -Caption +ToolWindow +E0x20 +HwndblHoverHwnd
    Gui, blHover: Color, %highlightBLColor%
    Gui, blHover: Show, % "x" lScr " y" (bScr - 2) " w" marginBL " h2 NA"  ; 2px height at bottom
    WinSet, Transparent, %highlightBLAlpha%, ahk_id %blHoverHwnd%
    blHoverVisible := false
    Gui, blHover: Hide
}

RepositionOverlays()
{
    global tlHoverHwnd, blHoverHwnd, lScr, tScr, bScr, marginTL, marginBL, tlHoverVisible, blHoverVisible
    if (tlHoverHwnd)
        WinMove, ahk_id %tlHoverHwnd%, , %lScr%, %tScr%, %marginTL%, 2  ; 2px height
    if (blHoverHwnd)
        WinMove, ahk_id %blHoverHwnd%, , %lScr%, % (bScr - 2), %marginBL%, 2  ; 2px height
    if (tlHoverHwnd && tlHoverVisible)
        Gui, tlHover: Show, NA
    if (blHoverHwnd && blHoverVisible)
        Gui, blHover: Show, NA
}

ShowTLHover(show := true, active := false)
{
    global tlHoverHwnd, tlHoverVisible, highlightTLColor, highlightTLAlpha, activeTLColor, activeTLAlpha
    if (!tlHoverHwnd)
        return
    if (show)
    {
        color := active ? activeTLColor : highlightTLColor
        alpha := active ? activeTLAlpha : highlightTLAlpha
        Gui, tlHover: Color, %color%
        WinSet, Transparent, %alpha%, ahk_id %tlHoverHwnd%
        Gui, tlHover: Show, NA
        tlHoverVisible := true
    }
    else
    {
        Gui, tlHover: Hide
        tlHoverVisible := false
    }
}

ShowBLHover(show := true)
{
    global blHoverHwnd, blHoverVisible
    if (!blHoverHwnd)
        return
    if (show)
    {
        Gui, blHover: Show, NA
        blHoverVisible := true
    }
    else
    {
        Gui, blHover: Hide
        blHoverVisible := false
    }
}

; ---------------------------- Alt-Tab control ---------------------------
OpenAltTabSwitcher()
{
    global g_IsAltTabActive, altTabOpenDelayMs
    if (g_IsAltTabActive)
        return
    SendEvent {Alt down}
    Sleep, 40
    SendEvent {Tab}
    Sleep, %altTabOpenDelayMs%
    SendEvent +{Tab}  ; back to current app so first scroll moves away from it
    g_IsAltTabActive := true
}

OpenAltTabWithSteps(steps := 0)
{
    global g_IsAltTabActive, altTabOpenDelayMs, stepDelayMs
    
    SendEvent {Alt down}
    Sleep, 40
    SendEvent {Tab}
    
    if (steps > 0)
    {
        Sleep, %altTabOpenDelayMs%
        Loop, %steps%
        {
            SendEvent {Tab}
            Sleep, %stepDelayMs%
        }
    }
    
    g_IsAltTabActive := true
}

StepAltTabRight()
{
    global g_IsAltTabActive
    if (!g_IsAltTabActive)
        return
    SendEvent {Right}
}

StepAltTabLeft()
{
    global g_IsAltTabActive
    if (!g_IsAltTabActive)
        return
    SendEvent {Left}
}

CloseAltTabSwitcher()
{
    global g_IsAltTabActive, altTabPinned
    if (g_IsAltTabActive && !altTabPinned)
    {
        SendEvent {Alt up}
        g_IsAltTabActive := false
    }
}

CommitAltTab()
{
    global g_IsAltTabActive, altTabPinned
    SendEvent {Alt up}
    g_IsAltTabActive := false
    altTabPinned := false
}

InstantSwitchRecent()
{
    ; Quick single Alt+Tab to previous app
    SendEvent {Alt down}
    Sleep, 40
    SendEvent {Tab}
    Sleep, 40
    SendEvent {Alt up}
}

; ---------------------- Corner detection loop --------------------------
SetTimer, CornerLoop, %pollMs%
CornerLoop:
    curTL := IsInTopLeft()
    curBL := IsInBottomLeft()

    ; TL hover visuals + commit Alt-Tab only when leaving TL (if not pinned)
    if (curTL && !TL_inside)
    {
        TL_inside := true
        ShowTLHover(true, IsAltTabActive())
    }
    else if (!curTL && TL_inside)
    {
        TL_inside := false
        ShowTLHover(false)
        CloseAltTabSwitcher()  ; commit selection when leaving TL (respects pinned state)
    }
    else if (curTL && TL_inside)
    {
        ShowTLHover(true, IsAltTabActive())
    }

    ; BL hover visuals
    if (curBL && !BL_inside)
    {
        BL_inside := true
        ShowBLHover(true)
    }
    else if (!curBL && BL_inside)
    {
        BL_inside := false
        ShowBLHover(false)
    }
    else if (curBL && BL_inside)
    {
        ShowBLHover(true)
    }
return

; --------------------- Watchdog: release stuck mods --------------------
SetTimer, CheckForStuckKeys, %stuckKeyCheckMs%
CheckForStuckKeys:
    global g_IsAltTabActive, Sending
    if (!g_IsAltTabActive && !Sending)
        ForceReleaseMods()
return

; ============================ Hotkeys ================================

; ----------------- Right button down: chording + zoom -----------------
#If ShouldHandleRButton()

$*RButton::
    if (Sending)
        return

    RDown := true
    RSolo := true
    ZoomUsed := false

    if (GetKeyState("LButton","P"))
    {
        ; L held, R click => Forward
        RSolo := false
        SuppressRUp := true
        BlockNextSoloRClick := true
        NavForward()
        return
    }

    ; Enable zoom only for supported browsers
    ZoomActive := AppIsBrowser()
return

$*RButton Up::
    if (Sending)
        return
    RDown := false
    ZoomActive := false

    if (ZoomUsed)
    {
        ZoomUsed := false
        RSolo := false
        return
    }

    if (SuppressRUp)
    {
        SuppressRUp := false
        RSolo := false
        return
    }

    if (RSolo && !BlockNextSoloRClick)
    {
        RSolo := false
        Sending := true
        Click Right
        Sending := false
    }
    BlockNextSoloRClick := false
return
#If

; ----------------- Left button for Back when R held -------------------
#If ShouldHandleLeftChord()

$*LButton::
    if (Sending)
        return
    RSolo := false
    SuppressRUp := true
    SuppressLUp := true
    BlockNextSoloRClick := true
    NavBack()
return

$*LButton Up::
    if (Sending)
        return
    if (SuppressLUp)
    {
        SuppressLUp := false
        return
    }
return
#If

; ------------------------ Zoom while R is held ------------------------
#If (ZoomActive && !IsInTopLeft() && !IsAltTabActive())

WheelUp::
    ZoomUsed := true
    SendEvent {Ctrl down}
    Sleep, 8
    SendEvent {WheelUp}
    Sleep, 8
    SendEvent {Ctrl up}
return

WheelDown::
    ZoomUsed := true
    SendEvent {Ctrl down}
    Sleep, 8
    SendEvent {WheelDown}
    Sleep, 8
    SendEvent {Ctrl up}
return
#If

; ------------------------ TL corner wheel = Alt-Tab -------------------
#If (IsInTopLeft() || IsAltTabActive())

*WheelUp::
    if (!IsAltTabActive())
    {
        OpenAltTabSwitcher()
    }
    else if (CanStep())
    {
        StepAltTabRight()
    }
return

*WheelDown::
    if (!IsAltTabActive())
    {
        OpenAltTabSwitcher()
    }
    else if (CanStep())
    {
        StepAltTabLeft()
    }
return

; Right-click to pin/unpin Alt-Tab menu (sticky mode)
*RButton::
    RB_DownInTL := true
return

*RButton Up::
    if (RB_DownInTL && (IsInTopLeft() || IsAltTabActive()))
    {
        if (IsAltTabActive())
        {
            ; Toggle pin state
            altTabPinned := !altTabPinned
        }
        else
        {
            ; If Alt-Tab not active, do original maximize/minimize
            WinGet, hwnd, ID, A
            if (hwnd)
            {
                WinGet, mm, MinMax, ahk_id %hwnd%
                if (mm = 1)
                    WinMinimize, ahk_id %hwnd%
                else
                    WinMaximize, ahk_id %hwnd%
            }
        }
    }
    RB_DownInTL := false
return
#If

; ------------------------ TL corner multi-click actions ---------------------
#If IsInTopLeft()

; Left-click for multi-click detection
*LButton::
    LB_DownInTL := true
    
    ; Multi-click detection
    currentTime := A_TickCount
    if (currentTime - tlLastClickTime <= multiClickWindow)
    {
        tlClickCount++
    }
    else
    {
        tlClickCount := 1
    }
    tlLastClickTime := currentTime
return

*LButton Up::
    if (LB_DownInTL && IsInTopLeft())
    {
        if (IsAltTabActive())
        {
            CommitAltTab()   ; commit current selection
        }
        else
        {
            ; Execute based on click count
            if (tlClickCount = 1)
            {
                ; Single click - wait to see if more clicks coming
                SetTimer, ExecuteTLSingleClick, -150
            }
            else if (tlClickCount >= 2)
            {
                ; Multi-click - navigate through multiple apps with animation
                SetTimer, ExecuteTLSingleClick, Off
                steps := tlClickCount - 1
                OpenAltTabWithSteps(steps)
                Sleep, 100
                CommitAltTab()
            }
        }
    }
    LB_DownInTL := false
return

ExecuteTLSingleClick:
    if (tlClickCount = 1)  ; Still single click
    {
        InstantSwitchRecent()
    }
return
#If

; Click anywhere when Alt-Tab is pinned to commit selection
#If (IsAltTabActive() && altTabPinned && !IsInTopLeft())

*LButton::
    CommitAltTab()
return
#If

; ------------------------ BL corner click actions ---------------------
#If (IsInBottomLeft() && !ShouldHandleLeftChord())

*LButton::
    LB_DownInBL := true
return

*LButton Up::
    if (LB_DownInBL && IsInBottomLeft())
    {
        if (IsAltTabActive())
            CloseAltTabSwitcher()
        SendEvent #{Tab}  ; Task View
    }
    LB_DownInBL := false
return
#If

; ============================ INITIALIZATION ============================
CreateOverlays()

; ============================ SAFETY & CLEANUP =========================
OnExit, Cleanup
Cleanup:
    SendEvent {Alt up}
    SendEvent {Ctrl up}
    SendEvent {Shift up}
    SendEvent {RButton up}
    SendEvent {LButton up}
    if (tlHoverHwnd)
        Gui, tlHover: Destroy
    if (blHoverHwnd)
        Gui, blHover: Destroy
    ExitApp
return

; ============================ EMERGENCY RESTART ========================
; Ctrl + Alt + Shift + R  => restart cleanly
^!+r::
    ForceReleaseMods()
    Reload
    Sleep, 1000
    ExitApp
return
