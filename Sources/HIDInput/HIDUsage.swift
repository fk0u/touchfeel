/// HID usage constants (HID Usage Tables 1.4).
public enum HIDUsage {
    public static let pageGenericDesktop: UInt32 = 0x01
    public static let pageDigitizer: UInt32 = 0x0D

    public static let x: UInt32 = 0x30
    public static let y: UInt32 = 0x31

    public static let touchScreen: UInt32 = 0x04
    public static let tipSwitch: UInt32 = 0x42
    public static let width: UInt32 = 0x48
    public static let height: UInt32 = 0x49
    public static let contactID: UInt32 = 0x51
    public static let contactCount: UInt32 = 0x54
    public static let scanTime: UInt32 = 0x56

    public static func name(page: UInt32, usage: UInt32) -> String {
        switch (page, usage) {
        case (0x01, 0x01): return "Pointer"
        case (0x01, 0x02): return "Mouse"
        case (0x01, 0x06): return "Keyboard"
        case (0x01, 0x30): return "X"
        case (0x01, 0x31): return "Y"
        case (0x0D, 0x01): return "Digitizer"
        case (0x0D, 0x02): return "Pen"
        case (0x0D, 0x04): return "Touch Screen"
        case (0x0D, 0x05): return "Touch Pad"
        case (0x0D, 0x0E): return "Device Configuration"
        case (0x0D, 0x22): return "Finger"
        case (0x0D, 0x42): return "Tip Switch"
        case (0x0D, 0x47): return "Confidence"
        case (0x0D, 0x48): return "Width"
        case (0x0D, 0x49): return "Height"
        case (0x0D, 0x51): return "Contact ID"
        case (0x0D, 0x52): return "Device Mode"
        case (0x0D, 0x54): return "Contact Count"
        case (0x0D, 0x55): return "Contact Count Max"
        case (0x0D, 0x56): return "Scan Time"
        default: return ""
        }
    }
}
