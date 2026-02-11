import Cocoa

// MARK: - Configuration
let kGridRows = 26
let kGridCols = 26
let kLineWidth: CGFloat = 1.0
let kLineColor = NSColor(calibratedRed: 0, green: 1, blue: 1, alpha: 0.3)
let kTextColor = NSColor.yellow
let kBackgroundColor = NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0.1)
let kLabelBgColor = NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0.7)
let kFocusColor = NSColor(calibratedRed: 0, green: 1, blue: 0, alpha: 0.3)
let kCursorStep: CGFloat = 15.0

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var hintView: HintView!
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?
    
    var cmdDownTime: TimeInterval = 0
    var isPotentialTap = false
    let kTapThreshold: TimeInterval = 0.3
    
    var isDragging: Bool = false
    var firstChar: String? = nil
    
    enum AppState {
        case hidden
        case gridSelection
        case fineTuning
        case scrolling
    }
    
    var state: AppState = .hidden {
        didSet {
            updateWindowVisibility()
        }
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        checkAccessibilityPermissions()
        setupWindow()
        setupGlobalKeyTap()
        
        print("GridClicker Daemon Started (Overlay Mode).")
        print(">> TAP Left Cmd to toggle.")
        state = .hidden
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { return false }
    
    func checkAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    func setupWindow() {
        // Create a passive overlay window
        let screen = NSScreen.main!
        window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        // CRITICAL: Ignore all mouse events. Pass clicks through.
        window.ignoresMouseEvents = true 
        // CRITICAL: Do not participate in window cycle. Do not become Key.
        window.styleMask.insert(.nonactivatingPanel)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        
        hintView = HintView(frame: CGRect(origin: .zero, size: screen.frame.size))
        hintView.appDelegate = self
        window.contentView = hintView
    }
    
    func updateWindowVisibility() {
        if state == .hidden {
            window.orderOut(nil)
            firstChar = nil
            hintView?.needsDisplay = true
            isDragging = false // Safety reset
        } else {
            // Move to correct screen
            let mouseLoc = NSEvent.mouseLocation
            if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) }) {
                window.setFrame(screen.frame, display: true)
                hintView.frame = CGRect(origin: .zero, size: screen.frame.size)
            }
            // Show NO ACTIVATION. Focus stays on original app.
            window.orderFront(nil)
        }
    }
    
    // MARK: - Global Event Tap (Handles EVERYTHING)
    func setupGlobalKeyTap() {
        let eventMask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap, // Catch before other apps
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let mySelf = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
                
                if mySelf.handleGlobalEvent(type: type, event: event) {
                    return nil // Swallow event (don't send to focused app)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: observer
        ) else { return }
        
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
    }
    
    func handleGlobalEvent(type: CGEventType, event: CGEvent) -> Bool {
        // --- Logic for HIDDEN state (Only detect Cmd Tap) ---
        if state == .hidden {
            if type == .flagsChanged {
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                if keyCode == 55 { // Left Cmd
                    if flags.contains(.maskCommand) {
                        cmdDownTime = Date().timeIntervalSince1970
                        isPotentialTap = true
                    } else {
                        if isPotentialTap {
                            let diff = Date().timeIntervalSince1970 - cmdDownTime
                            if diff < kTapThreshold {
                                DispatchQueue.main.async { self.toggleGrid() }
                            }
                        }
                        isPotentialTap = false
                    }
                } else { isPotentialTap = false }
            } else if type == .keyDown { isPotentialTap = false }
            return false // Pass everything through
        }
        
        // --- Logic for ACTIVE states (Intercept Keys) ---
        
        // Always pass through modifier flags (Shift, Cmd, etc.) to avoid sticking
        if type == .flagsChanged { return false }
        
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isKeyDown = (type == .keyDown)
        
        // 1. Global ESC handling
        if isKeyDown && keyCode == 53 { // ESC
            if isDragging { toggleDrag(enable: false) }
            DispatchQueue.main.async { self.state = .hidden }
            return true
        }
        
        // 2. Mode Specific Handling
        switch state {
        case .scrolling:
            if isKeyDown {
                if keyCode == 38 { scrollMouse(dy: -5); return true } // J
                if keyCode == 40 { scrollMouse(dy: 5); return true } // K
            }
            return true // Swallow all keys in scroll mode to be safe
            
        case .gridSelection:
            if isKeyDown {
                if keyCode == 51 { // Backspace
                    firstChar = nil
                    DispatchQueue.main.async { self.hintView.needsDisplay = true }
                    return true
                }
                if let char = keyCodeToChar(keyCode) {
                    if firstChar == nil {
                        firstChar = char
                        DispatchQueue.main.async { self.hintView.needsDisplay = true }
                    } else {
                        let label = firstChar! + char
                        DispatchQueue.main.async { self.selectGrid(label: label) }
                    }
                    return true
                }
            }
            return true // Swallow keys in grid selection
            
        case .fineTuning:
            // Handle V Key specially (it has a KeyUp action)
            if keyCode == 9 { // V
                if isKeyDown {
                    if !isDragging { toggleDrag(enable: true) }
                } else if type == .keyUp {
                    if isDragging { toggleDrag(enable: false) }
                }
                return true
            }
            
            // Other Fine Tuning keys (KeyDown only)
            if isKeyDown {
                switch keyCode {
                case 36, 76: performCopyAndExit(); return true // Enter
                case 31: enterScrollMode(); return true         // O
                case 46: performClick(rightClick: true); return true // M
                case 49: performClick(rightClick: false); return true // Space
                case 4: moveCursor(dx: -kCursorStep, dy: 0); return true // H
                case 37: moveCursor(dx: kCursorStep, dy: 0); return true // L
                case 38: moveCursor(dx: 0, dy: kCursorStep); return true // J
                case 40: moveCursor(dx: 0, dy: -kCursorStep); return true // K
                case 51: // Backspace
                    DispatchQueue.main.async {
                        self.state = .gridSelection
                        self.firstChar = nil
                        self.hintView.needsDisplay = true
                    }
                    return true
                default: break
                }
            }
            
            // CRITICAL: Only swallow KeyDown/KeyUp if they are likely intended for us.
            // In fine-tuning, we generally want to swallow all letter/nav keys.
            return true
            
        case .hidden:
            return false
        }
    }
    
    // Simple QWERTY mapping for A-Z
    func keyCodeToChar(_ code: Int64) -> String? {
        // Map common codes. A=0, S=1, D=2, F=3, H=4, G=5, Z=6, X=7, C=8, V=9 ...
        // This is tedious but robust for US layout.
        let map: [Int64: String] = [
            0:"A", 1:"S", 2:"D", 3:"F", 4:"H", 5:"G", 6:"Z", 7:"X", 8:"C", 9:"V", 11:"B",
            12:"Q", 13:"W", 14:"E", 15:"R", 16:"Y", 17:"T", 31:"O", 32:"U", 34:"I", 35:"P",
            37:"L", 38:"J", 40:"K", 45:"N", 46:"M"
        ]
        return map[code]
    }
    
    func toggleGrid() {
        if state == .hidden || state == .scrolling { state = .gridSelection }
        else { state = .hidden }
        // Force immediate redraw
        DispatchQueue.main.async {
            self.hintView.needsDisplay = true
        }
    }
    
    func toggleDrag(enable: Bool) {
        let pos = CGEvent(source: nil)?.location ?? .zero
        let src = CGEventSource(stateID: .combinedSessionState)
        let type: CGEventType = enable ? .leftMouseDown : .leftMouseUp
        CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: pos, mouseButton: .left)?.post(tap: .cghidEventTap)
        isDragging = enable
    }
    
    func performCopyAndExit() {
        if isDragging { toggleDrag(enable: false) }
        
        state = .hidden
        NSApp.hide(nil) // Just to be sure
        
        // Send Cmd+C
        let src = CGEventSource(stateID: .hidSystemState)
        let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: 55, keyDown: true)
        cmdDown?.flags = .maskCommand
        cmdDown?.post(tap: .cghidEventTap)
        
        let cDown = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: true)
        cDown?.flags = .maskCommand
        cDown?.post(tap: .cghidEventTap)
        
        usleep(10000)
        
        let cUp = CGEvent(keyboardEventSource: src, virtualKey: 8, keyDown: false)
        cUp?.flags = .maskCommand
        cUp?.post(tap: .cghidEventTap)
        
        let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: 55, keyDown: false)
        cmdUp?.flags = []
        cmdUp?.post(tap: .cghidEventTap)
    }
    
    func enterScrollMode() {
        // No click needed anymore because focus never left the app!
        state = .scrolling
        print("Scroll Mode.")
    }
    
    func selectGrid(label: String) {
        let chars = Array(label)
        let row = Int(chars[0].asciiValue! - 65)
        let col = Int(chars[1].asciiValue! - 65)
        guard row >= 0 && row < kGridRows && col >= 0 && col < kGridCols else { firstChar = nil; hintView.needsDisplay = true; return }
        
        guard let screen = window.screen else { return }
        let deviceDescription = screen.deviceDescription
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return }
        let displayID = CGDirectDisplayID(screenNumber.uint32Value)
        let displayBounds = CGDisplayBounds(displayID)
        
        let cellW = displayBounds.width / CGFloat(kGridCols)
        let cellH = displayBounds.height / CGFloat(kGridRows)
        let globalX = displayBounds.origin.x + CGFloat(col) * cellW + (cellW / 2)
        let globalY = displayBounds.origin.y + CGFloat(row) * cellH + (cellH / 2)
        
        moveMouseAbsolute(to: CGPoint(x: globalX, y: globalY))
        state = .fineTuning
        hintView.needsDisplay = true
    }
    
    func moveCursor(dx: CGFloat, dy: CGFloat) {
        var pos = CGEvent(source: nil)?.location ?? .zero
        pos.x += dx; pos.y += dy
        moveMouseAbsolute(to: pos)
    }
    
    func moveMouseAbsolute(to point: CGPoint) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let type: CGEventType = isDragging ? .leftMouseDragged : .mouseMoved
        CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    }
    
    func scrollMouse(dy: Int32) {
        let src = CGEventSource(stateID: .hidSystemState)
        let pos = CGEvent(source: nil)?.location ?? .zero
        let pixelDelta = dy * 8
        if let scroll = CGEvent(scrollWheelEvent2Source: src, units: .pixel, wheelCount: 1, wheel1: pixelDelta, wheel2: 0, wheel3: 0) {
            scroll.location = pos
            scroll.post(tap: .cghidEventTap)
        }
    }
    
    func performClick(rightClick: Bool) {
        let pos = CGEvent(source: nil)?.location ?? .zero
        // Keep active for continuous control until ESC is pressed
        
        let src = CGEventSource(stateID: .combinedSessionState)
        
        if rightClick {
            let down = CGEvent(mouseEventSource: src, mouseType: .rightMouseDown, mouseCursorPosition: pos, mouseButton: .right)
            let up = CGEvent(mouseEventSource: src, mouseType: .rightMouseUp, mouseCursorPosition: pos, mouseButton: .right)
            down?.post(tap: .cghidEventTap); usleep(100000); up?.post(tap: .cghidEventTap)
        } else {
            let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: pos, mouseButton: .left)
            let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: pos, mouseButton: .left)
            down?.setIntegerValueField(.mouseEventClickState, value: 1)
            up?.setIntegerValueField(.mouseEventClickState, value: 1)
            down?.post(tap: .cghidEventTap); usleep(60000); up?.post(tap: .cghidEventTap)
        }
    }
}

// MARK: - View (Minimal changes)
class HintView: NSView {
    weak var appDelegate: AppDelegate?
    override var isFlipped: Bool { return true }
    
    override func draw(_ dirtyRect: NSRect) {
        guard let app = appDelegate else { return }
        if app.state == .hidden { return }
        
        let bounds = self.bounds
        
        // Always draw status hint if not hidden
        drawStatusHint(in: bounds, state: app.state)
        
        // Only draw grid during selection phase
        if app.state == .gridSelection {
            drawGrid(in: bounds, app: app)
        }
    }
    
    private func drawStatusHint(in bounds: NSRect, state: AppDelegate.AppState) {
        let text: String
        switch state {
        case .gridSelection: text = "网格定位 | ESC: 隐藏"
        case .fineTuning: text = "微调模式 | HJKL: 移动 | Space: 点击 | M: 右键 | ESC: 退出"
        case .scrolling: text = "滚动模式 | J/K: 滚动 | ESC: 退出"
        case .hidden: return
        }
        
        let fontSize: CGFloat = 12
        let font = NSFont.systemFont(ofSize: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        
        let size = text.size(withAttributes: attrs)
        let padding: CGFloat = 8
        let margin: CGFloat = 20
        let rect = NSRect(x: bounds.width - size.width - padding * 2 - margin,
                          y: margin,
                          width: size.width + padding * 2,
                          height: size.height + padding * 2)
        
        NSColor(calibratedWhite: 0, alpha: 0.6).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        
        text.draw(at: NSPoint(x: rect.origin.x + padding, y: rect.origin.y + padding), withAttributes: attrs)
    }
    
    private func drawGrid(in bounds: NSRect, app: AppDelegate) {
        let cellW = bounds.width / CGFloat(kGridCols)
        let cellH = bounds.height / CGFloat(kGridRows)
        let path = NSBezierPath()
        path.lineWidth = kLineWidth
        kLineColor.setStroke()
        for i in 1..<kGridCols {
            let x = CGFloat(i) * cellW; path.move(to: CGPoint(x: x, y: 0)); path.line(to: CGPoint(x: x, y: bounds.height))
        }
        for i in 1..<kGridRows {
            let y = CGFloat(i) * cellH; path.move(to: CGPoint(x: 0, y: y)); path.line(to: CGPoint(x: bounds.width, y: y))
        }
        path.stroke()
        
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map { String($0) }
        let fontSize: CGFloat = 14
        let font = NSFont(name: "Menlo-Bold", size: fontSize) ?? NSFont.boldSystemFont(ofSize: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: kTextColor]
        
        for row in 0..<kGridRows {
            // If we have a firstChar, only draw that specific row
            if let first = app.firstChar, letters[row] != first { continue }
            
            for col in 0..<kGridCols {
                let label = letters[row] + letters[col]
                let x = CGFloat(col) * cellW; let y = CGFloat(row) * cellH
                
                // Highlight the cell if it's part of a narrowed selection
                if app.firstChar != nil {
                    kFocusColor.setFill()
                    CGRect(x: x, y: y, width: cellW, height: cellH).fill()
                }
                
                let labelSize = label.size(withAttributes: attrs)
                let boxRect = CGRect(x: x + (cellW-labelSize.width-8)/2, y: y + (cellH-labelSize.height-4)/2, width: labelSize.width+8, height: labelSize.height+4)
                kLabelBgColor.setFill()
                NSBezierPath(roundedRect: boxRect, xRadius: 4, yRadius: 4).fill()
                NSString(string: label).draw(in: CGRect(x: boxRect.origin.x+4, y: boxRect.origin.y+2, width: labelSize.width, height: labelSize.height), withAttributes: attrs)
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
