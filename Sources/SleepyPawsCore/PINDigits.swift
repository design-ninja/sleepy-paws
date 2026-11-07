public struct PINDigits: Equatable {
    public private(set) var slots = Array(repeating: "", count: ParentPIN.length)

    public init() {}

    public var value: String { slots.joined() }
    public var count: Int { slots.firstIndex(of: "") ?? slots.count }
    public var isComplete: Bool { ParentPIN.isValid(value) }

    /// Appends ASCII digits from typed or pasted text; anything else is ignored.
    public mutating func type(_ text: String) {
        for byte in text.utf8 where (48...57).contains(byte) && count < slots.count {
            slots[count] = String(UnicodeScalar(byte))
        }
    }

    public mutating func deleteLast() {
        guard count > 0 else { return }
        slots[count - 1] = ""
    }
}
