import Cocoa
import AVFoundation

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel!
    var captureSession: AVCaptureSession!
    var previewLayer: AVCaptureVideoPreviewLayer!
    var containerView: CameraView!
    var statusItem: NSStatusItem!
    var isVisible = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupStatusBar()
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveWindowFrame()
        captureSession?.stopRunning()
    }

    private func saveWindowFrame() {
        let frame = panel.frame
        UserDefaults.standard.set(frame.origin.x, forKey: "windowX")
        UserDefaults.standard.set(frame.origin.y, forKey: "windowY")
        UserDefaults.standard.set(frame.size.width, forKey: "windowW")
        UserDefaults.standard.set(frame.size.height, forKey: "windowH")
    }

    private func savedWindowFrame() -> NSRect? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "windowW") != nil else { return nil }
        return NSRect(
            x: defaults.double(forKey: "windowX"),
            y: defaults.double(forKey: "windowY"),
            width: defaults.double(forKey: "windowW"),
            height: defaults.double(forKey: "windowH")
        )
    }

    // MARK: - Status Bar

    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "web.camera.fill", accessibilityDescription: "SthPiP")
            button.image?.isTemplate = true
            button.action = #selector(statusBarClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc func statusBarClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            showStatusMenu()
        } else {
            toggleCamera()
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        menu.addItem(NSMenuItem(title: "SthPiP v\(version)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = isLaunchAgentInstalled() ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit SthPiP", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil  // Remove so left click works again
    }

    @objc func toggleCamera() {
        if isVisible {
            saveWindowFrame()
            captureSession?.stopRunning()
            panel.orderOut(nil)
        } else {
            if panel == nil {
                setupWindow()
                setupCamera()
            }
            panel.orderFrontRegardless()
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.captureSession?.startRunning()
            }
        }
        isVisible = !isVisible
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Launch Agent

    private var launchAgentPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.sth.pip.plist")
    }

    private func isLaunchAgentInstalled() -> Bool {
        FileManager.default.fileExists(atPath: launchAgentPath.path)
    }

    @objc func toggleLaunchAtLogin() {
        if isLaunchAgentInstalled() {
            try? FileManager.default.removeItem(at: launchAgentPath)
        } else {
            let appPath = Bundle.main.executablePath ?? "/Applications/SthPiP.app/Contents/MacOS/SthPiP"
            let plist = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.sth.pip</string>
    <key>ProgramArguments</key>
    <array>
        <string>\(appPath)</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
"""
            let dir = launchAgentPath.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? plist.write(to: launchAgentPath, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Window Setup

    func setupWindow() {
        let frame: NSRect
        if let saved = savedWindowFrame() {
            frame = saved
        } else {
            let defaultSize = NSSize(width: 240, height: 180)
            let screenFrame = NSScreen.main?.visibleFrame ?? .zero
            let origin = NSPoint(
                x: screenFrame.maxX - defaultSize.width - 20,
                y: screenFrame.minY + 20
            )
            frame = NSRect(origin: origin, size: defaultSize)
        }

        panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.title = "SthPiP"
        panel.minSize = NSSize(width: 120, height: 90)
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true

        // Maintain 4:3 aspect ratio
        panel.aspectRatio = NSSize(width: 4, height: 3)

        containerView = CameraView(frame: panel.contentView!.bounds)
        containerView.autoresizingMask = [.width, .height]
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 10
        containerView.layer?.masksToBounds = true
        containerView.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        containerView.layer?.borderWidth = 1

        panel.contentView?.addSubview(containerView)
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in self?.saveWindowFrame() }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: panel, queue: .main
        ) { [weak self] _ in self?.saveWindowFrame() }
    }

    // MARK: - Camera Setup

    func setupCamera() {
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .medium

        guard let camera = AVCaptureDevice.default(for: .video) else {
            showError("No camera found")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            }
        } catch {
            showError("Camera access failed: \(error.localizedDescription)")
            return
        }

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = containerView.bounds
        // Mirror the preview so it looks natural (like a mirror)
        previewLayer.connection?.automaticallyAdjustsVideoMirroring = false
        previewLayer.connection?.isVideoMirrored = true
        containerView.layer?.addSublayer(previewLayer)
        containerView.previewLayer = previewLayer

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "SthPiP"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.runModal()
        NSApp.terminate(nil)
    }
}

// MARK: - Camera View (handles preview layer resizing + resize handle)

class CameraView: NSView {
    var previewLayer: AVCaptureVideoPreviewLayer?

    override func layout() {
        super.layout()
        previewLayer?.frame = bounds
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
