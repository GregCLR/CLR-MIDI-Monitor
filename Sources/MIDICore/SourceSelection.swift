/// New ports are enabled automatically. Explicit exclusions survive a reconnect
/// where CoreMIDI assigns a different endpoint reference to the same unique ID.
public struct SourceSelection {
    private var disabled: Set<Int32> = []
    public init() {}
    public mutating func setEnabled(_ enabled: Bool, for uniqueIDs: [Int32]) {
        for id in uniqueIDs { setEnabled(enabled, for: id) }
    }
    public func isEnabled(_ uniqueID: Int32) -> Bool { !disabled.contains(uniqueID) }
    public mutating func setEnabled(_ enabled: Bool, for uniqueID: Int32) {
        if enabled { disabled.remove(uniqueID) } else { disabled.insert(uniqueID) }
    }
}
