# 🖱️ Hot Corners for Windows (AutoHotkey v1)

This AutoHotkey v1 script adds **hot corners** to Windows: **Top-Left Corner** → App switching (Alt+Tab), **Bottom-Left Corner** → Task View, and mouse **scroll & clicks** for quick window control.

## 🚀 Setup

1.  **Install AutoHotkey v1**  
    👉 [Download here](https://www.autohotkey.com/)
    
3.  **Click ` ctrl ` `shift` `s` after clicking the link below ↙️ to Download this script**
  
    👉🏻 [CornerSwitcher.ahk](https://github.com/shubham911-dell/CornerSwitcher/blob/main/CornerSwitcher.ahk)
   
5.  **Run the script**  
    → Double-click the `.ahk` file, and it will auto-run with admin rights.

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
-  **Left-Click (multi-click supported):**
    - **1× click** → switch to previous app  
    - **2× clicks** → switch to 2nd most recent app  
    - **3× clicks** → switch to 3rd most recent app  
      *(and so on)*

- **Right Click** → maximize/minimize window

### 🔽 Bottom-Left (Task View)
- **Hover** → green box
- **Left Click** → open Task View (`Win+Tab`)

## ▶️ Start & Stop

- **Start** → Double-click the script
- **Stop** → Right-click the green `H` tray icon → Exit

   **OR**
  
    → Click `ctrl` `shift` `esc` and search for <ins>***AutoHotKey 64-bit***</ins> and ****Right click**** on it and click ****End task****
