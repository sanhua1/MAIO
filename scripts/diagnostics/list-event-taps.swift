import AppKit
import CoreGraphics

var count: UInt32 = 0
CGGetEventTapList(0, nil, &count)
var taps = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(count))
CGGetEventTapList(count, &taps, &count)
let keyMask: UInt64 = (1 << 10) | (1 << 11) | (1 << 12)
for (i, t) in taps.enumerated() where t.eventsOfInterest & keyMask != 0 {
    let name = NSRunningApplication(processIdentifier: pid_t(t.tappingProcess))?
        .localizedName ?? (try? String(contentsOfFile: "/proc/\(t.tappingProcess)")) ?? "pid \(t.tappingProcess)"
    let point = ["HID", "Session", "AnnotatedSession"][Int(t.tapPoint.rawValue)]
    print("\(i)\t\(point)\t\(t.options == .listenOnly ? "listen" : "ACTIVE")\tenabled=\(t.enabled)\t\(name)(\(t.tappingProcess))")
}
