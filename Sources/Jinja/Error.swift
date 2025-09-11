public enum JinjaError: Error, Sendable {
    case lexer(String)
    case parser(String)
    case runtime(String)
    case syntax(String)
}
