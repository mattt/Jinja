public final class Joiner: @unchecked Sendable {
    public let separator: String
    public private(set) var isFirst: Bool = true

    public init(separator: String = ", ") {
        self.separator = separator
    }

    public func call() -> String {
        if isFirst {
            isFirst = false
            return ""
        } else {
            return separator
        }
    }
}
