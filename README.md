# 🖱️ Hot Corners for Windows (AutoHotkey v2)

This AutoHotkey v2 script adds **hot corners** to Windows: **Top-Left Corner** → App switching (Alt+Tab), **Bottom-Left Corner** → Task View, and mouse **scroll & clicks** for quick window control.

## 🚀 Setup

1.  **Install AutoHotkey v2**  
    👉 [Download here](https://www.autohotkey.com/)

2.  **Download this script**
    ```sh
    https://github.com/shubham911-dell/CornerSwitcher.git
    ```
    Or download the ZIP and extract it.

3.  **Run the script**  
    → Double-click the `.ahk` file and it will auto-run with admin rights.

## ⚙️ Quick Config

Edit values at the top of the script:
- `marginTL` (14, size of top-left area)
- `marginBL` (14, size of bottom-left area)
- `highlightTLColor` (Yellow, top-left hover color)
- `highlightBLColor` (Lime, bottom-left hover color)
- `altTabOpenDelayMs` (100, delay before Alt+Tab scroll works)

## 🖥️ How to Use

### 🔼 Top-Left (App Switcher)
- **Hover** → yellow box
- **Scroll Up** → next app
- **Scroll Down** → previous app
- **Left Click** → switch to last app
- **Right Click** → maximize/minimize window

### 🔽 Bottom-Left (Task View)
- **Hover** → green box
- **Left Click** → open Task View (`Win+Tab`)

## ▶️ Start & Stop

- **Start** → Double-click the script
- **Stop** → Right-click the green `H` tray icon → Exit
