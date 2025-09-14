public struct Macro: Hashable, Sendable {
    public let name: String
    public let parameters: [String]
    public let defaults: OrderedDictionary<String, Expression>
    public let body: [Node]

    public init(
        name: String,
        parameters: [String],
        defaults: OrderedDictionary<String, Expression>,
        body: [Node]
    ) {
        self.name = name
        self.parameters = parameters
        self.defaults = defaults
        self.body = body
    }
}

// MARK: - Codable

extension Macro: Codable {
    private enum CodingKeys: String, CodingKey {
        case name, parameters, defaults, body
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        parameters = try container.decode([String].self, forKey: .parameters)
        var orderedDictionary: OrderedDictionary<String, Expression> = [:]

        let decodedDefaults = try container.decode([String: Expression].self, forKey: .defaults)
        for key in decodedDefaults.keys {
            orderedDictionary[key] = decodedDefaults[key]
        }
        defaults = orderedDictionary

        body = try container.decode([Node].self, forKey: .body)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(parameters, forKey: .parameters)

        var dictionary: [String: Expression] = [:]
        for (key, value) in defaults {
            dictionary[key] = value
        }
        try container.encode(dictionary, forKey: .defaults)

        try container.encode(body, forKey: .body)
    }
}
