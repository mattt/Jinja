import Foundation
import OrderedCollections

public enum Global: Sendable {
    case cycler(Cycler)
    case joiner(Joiner)
    case namespace(Namespace)
    
    static var range: Value {
        .function { values, _, _ in
            switch values.count {
            case 0:
                return .array([])
            case 1:
                if case let .int(end) = values[0] {
                    return .array((0..<end).map { .int($0) })
                }
            case 2:
                if case let .int(start) = values[0],
                   case let .int(end) = values[1]
                {
                    return .array((start..<end).map { .int($0) })
                }
            case 3:
                if case let .int(start) = values[0],
                   case let .int(end) = values[1],
                   case let .int(step) = values[2]
                {
                    return .array(stride(from: start, to: end, by: step).map { .int($0) })
                }
            default:
                break
            }
            
            throw JinjaError.runtime("Invalid arguments to range function")
        }
    }
}

// MARK: - CustomStringConvertible

extension Global: CustomStringConvertible {
    public var description: String {
        switch self {
        case .cycler: return "Cycler"
        case .joiner: return "Joiner"
        case .namespace: return "Namespace"
        }
    }
}

// MARK: - Codable

extension Global: Codable {
    private enum CodingKeys: String, CodingKey {
        case cycler
        case joiner
        case namespace
    }

    private enum CyclerCodingKeys: String, CodingKey {
        case items
        case index
    }

    private enum JoinerCodingKeys: String, CodingKey {
        case separator
        case isFirst
    }

    private enum NamespaceCodingKeys: String, CodingKey {
        case attributes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let cyclerContainer = try? container.nestedContainer(
            keyedBy: CyclerCodingKeys.self, forKey: .cycler)
        {
            let items = try cyclerContainer.decode([Value].self, forKey: .items)
            let index = try cyclerContainer.decode(Int.self, forKey: .index)
            self = .cycler(Cycler(items: items, index: index))
        } else if let joinerContainer = try? container.nestedContainer(
            keyedBy: JoinerCodingKeys.self, forKey: .joiner)
        {
            let separator = try joinerContainer.decode(String.self, forKey: .separator)
            let isFirst = try joinerContainer.decode(Bool.self, forKey: .isFirst)
            let joiner = Joiner(separator: separator)
            if !isFirst {
                _ = joiner.call()  // Advance past first call
            }
            self = .joiner(joiner)
        } else if let namespaceContainer = try? container.nestedContainer(
            keyedBy: NamespaceCodingKeys.self, forKey: .namespace)
        {
            let attributes = try namespaceContainer.decode(
                [String: Value].self, forKey: .attributes)
            self = .namespace(Namespace(attributes: attributes))
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath, debugDescription: "Unable to decode Global"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .cycler(let cycler):
            var cyclerContainer = container.nestedContainer(
                keyedBy: CyclerCodingKeys.self, forKey: .cycler)
            try cyclerContainer.encode(cycler.items, forKey: .items)
            try cyclerContainer.encode(cycler.index, forKey: .index)
        case .joiner(let joiner):
            var joinerContainer = container.nestedContainer(
                keyedBy: JoinerCodingKeys.self, forKey: .joiner)
            try joinerContainer.encode(joiner.separator, forKey: .separator)
            try joinerContainer.encode(joiner.isFirst, forKey: .isFirst)
        case .namespace(let namespace):
            var namespaceContainer = container.nestedContainer(
                keyedBy: NamespaceCodingKeys.self, forKey: .namespace)
            try namespaceContainer.encode(namespace.attributes, forKey: .attributes)
        }
    }
}
