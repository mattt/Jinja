public final class Cycler: @unchecked Sendable {
    public let items: [Value]
    public private(set) var index: Int

    public init(items: [Value], index: Int = 0) {
        self.items = items
        self.index = index
    }

    public func next() -> Value {
        guard !items.isEmpty else { return .undefined }
        let item = items[index]
        index = (index + 1) % items.count
        return item
    }

    public func reset() {
        index = 0
    }

    public var current: Value {
        guard !items.isEmpty else { return .undefined }
        return items[index]
    }
}
