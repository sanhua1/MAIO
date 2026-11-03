import CoreGraphics
import MAIOKit

/// CGEvent（滚轮）与 `PointerEvent` 之间的转换。
enum ScrollEventCodec {
    /// 连续滚动事件里"一行"大约对应的像素数，仅在无法按比例换算时使用。
    static let pixelsPerLine = 10.0

    static func decode(_ event: CGEvent) -> PointerEvent {
        let phase = phase(from: event.getIntegerValueField(.scrollWheelEventScrollPhase))
        let momentum = momentum(from: event.getIntegerValueField(.scrollWheelEventMomentumPhase))
        // 有手势阶段或惯性阶段的是触控板 / 妙控鼠标（参考 Mos ScrollEvent.isTrackpad 的判断思路）
        let isTrackpad = phase != .none || momentum != .none
        return PointerEvent(
            scrollY: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1),
            scrollX: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2),
            pixelY: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1),
            pixelX: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2),
            device: isTrackpad ? .trackpad : .wheel,
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
            phase: phase,
            momentumPhase: momentum,
            location: event.location,
            isSynthetic: SyntheticMarker.isMarked(event),
        )
    }

    /// 把过滤器修改后的数值写回事件。三组字段（整数行、定点行、像素）按比例同步修改。
    static func apply(_ modified: PointerEvent, original: PointerEvent, to event: CGEvent) {
        if modified.scrollY != original.scrollY {
            write(axis: 1, new: modified.scrollY, old: original.scrollY, to: event)
        }
        if modified.scrollX != original.scrollX {
            write(axis: 2, new: modified.scrollX, old: original.scrollX, to: event)
        }
    }

    private static func write(axis: Int, new: Double, old: Double, to event: CGEvent) {
        let fields: (line: CGEventField, fixed: CGEventField, point: CGEventField) = axis == 1
            ? (.scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventPointDeltaAxis1)
            : (.scrollWheelEventDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventPointDeltaAxis2)
        let oldPoint = event.getDoubleValueField(fields.point)
        let oldLine = event.getIntegerValueField(fields.line)
        let point = old != 0 ? oldPoint * (new / old) : new * pixelsPerLine
        let line: Int64 = if old != 0 {
            Int64((Double(oldLine) * (new / old)).rounded())
        } else {
            new == 0 ? 0 : Int64(new.rounded(.awayFromZero))
        }
        event.setIntegerValueField(fields.line, value: line)
        event.setDoubleValueField(fields.fixed, value: new)
        event.setDoubleValueField(fields.point, value: point)
    }

    static func phase(from raw: Int64) -> ScrollPhase {
        switch raw {
        case 1: .began
        case 2: .changed
        case 4: .ended
        case 8: .cancelled
        case 128: .mayBegin
        default: .none
        }
    }

    static func rawPhase(_ phase: ScrollPhase) -> Int64 {
        switch phase {
        case .none: 0
        case .began: 1
        case .changed: 2
        case .ended: 4
        case .cancelled: 8
        case .mayBegin: 128
        }
    }

    static func momentum(from raw: Int64) -> MomentumPhase {
        switch raw {
        case 1: .began
        case 2: .changed
        case 3: .ended
        default: .none
        }
    }

    static func rawMomentum(_ phase: MomentumPhase) -> Int64 {
        switch phase {
        case .none: 0
        case .began: 1
        case .changed: 2
        case .ended: 3
        }
    }
}
