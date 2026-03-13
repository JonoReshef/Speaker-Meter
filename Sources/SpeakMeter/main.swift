import AppKit
import SwiftUI

let segmentHeight: CGFloat = 10
let segmentSpacing: CGFloat = 3
let minSegments = 5
let maxSegments = 20

func meterHeight(for segments: Int) -> CGFloat {
    CGFloat(segments) * segmentHeight + CGFloat(segments - 1) * segmentSpacing
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow?
    var chromeHeight: CGFloat = 0
    var titleBarHeight: CGFloat = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentView = ContentView()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SpeakMeter"
        window.delegate = self
        window.contentView = NSHostingView(rootView: contentView)

        // Measure chrome (non-meter) height from SwiftUI's ideal layout.
        // GeometryReader has a default ideal height of 10, so subtract that
        // to get the height of all non-meter UI elements.
        window.layoutIfNeeded()
        titleBarHeight = window.frame.height - window.contentView!.frame.height
        let idealContentHeight = window.contentView!.fittingSize.height
        chromeHeight = idealContentHeight - 10

        let maxContentH = meterHeight(for: maxSegments) + chromeHeight
        let minContentH = meterHeight(for: minSegments) + chromeHeight
        window.minSize = NSSize(width: 140, height: minContentH + titleBarHeight)
        window.maxSize = NSSize(width: 300, height: maxContentH + titleBarHeight)

        let savedSegments = UserDefaults.standard.integer(forKey: "segmentCount")
        let initialSegments = (minSegments...maxSegments).contains(savedSegments) ? savedSegments : maxSegments
        let initialContentH = meterHeight(for: initialSegments) + chromeHeight
        window.setContentSize(NSSize(width: 160, height: initialContentH))
        window.level = .floating
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let contentH = frameSize.height - titleBarHeight
        let available = contentH - chromeHeight
        let fitCount = Int((available + segmentSpacing) / (segmentHeight + segmentSpacing))
        let clamped = max(minSegments, min(maxSegments, fitCount))
        let snappedContentH = meterHeight(for: clamped) + chromeHeight
        UserDefaults.standard.set(clamped, forKey: "segmentCount")
        return NSSize(width: frameSize.width, height: snappedContentH + titleBarHeight)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
