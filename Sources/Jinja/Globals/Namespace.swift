public final class Namespace: @unchecked Sendable {
    public private(set) var attributes: [String: Value] = [:]

    public init(attributes: [String: Value] = [:]) {
        self.attributes = attributes
    }

    public subscript(attribute: String) -> Value {
        get {
            return attributes[attribute] ?? .undefined
        }
        set {
            attributes[attribute] = newValue
        }
    }
}
