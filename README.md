# Jinja

A Swift implementation of the [Jinja2 template engine](https://jinja.palletsprojects.com/en/3.1.x/).

Jinja templates are widely used for generating HTML, configuration files, code generation, and text processing. 
This implementation is focused primarily on the features needed to generate LLM chat templates.

## Requirements

* Swift 6.0+ / Xcode 16+

## Installation

### Swift Package Manager

Add the following dependency to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mattt/Jinja.git", from: "1.0.0")
]
```

## Usage

### Basic Template Rendering

```swift
import Jinja

// Create and render a simple template
let template = try Template("Hello, {{ name }}!")
let result = try template.render(["name": "World"])
print(result) // "Hello, World!"
```

### Template with Context Variables

```swift
// Template with multiple variables
let template = try Template("""
    Welcome, {{ user.name }}!
    You have {{ messages | length }} new messages.
    """)

let context: [String: Value] = [
    "user": ["name": "Alice",
    "messages": [
        "Hello",
        "How are you?",
        "See you later"
    ]
]

let result = try template.render(context)
// "Welcome, Alice!\nYou have 3 new messages."
```

### Control Flow

```swift
// Conditional rendering
let template = try Template("""
    {% for item in items %}
        {% if item.active %}
            * {{ item.name }} ({{ item.price }})
        {% endif %}
    {% endfor %}
    """)

let context: [String: Value] = [
    "items": [
        [
            "name": "Coffee",
            "price": 4.50,
            "active": true
        ],
        [
            "name": "Tea",
            "price": 3.25,
            "active": false
        ]
    ]
]

let result = try template.render(context)
// "    * Coffee (4.5)\n"
```

### Built-in Filters

```swift
// String manipulation filters
let template = try Template("""
    {{ name | upper }}
    {{ description | truncate(50) }}
    {{ tags | join(", ") }}
    """)

let context: [String: Value] = [
    "name": "swift package",
    "description": "A powerful template engine for Swift applications",
    "tags": ["swift", "templates", "web"]
]

let result = try template.render(context)
```

### Template Options

```swift
// Configure template behavior
let options = Template.Options(
    lstripBlocks: true,  // Strip leading whitespace from blocks
    trimBlocks: true     // Remove trailing newlines from blocks
)

let template = try Template("""
    {% for item in items %}
        {{ item }}
    {% endfor %}
    """, with: options)
```

### Value Types

The `Value` enum represents all possible template values:

```swift
// Creating values directly
let context: [String: Value] = [
    "text": "Hello",
    "number": 42,
    "decimal": 3.14,
    "flag": true,
    "items": ["a", "b"],
    "user": ["name": "John", "age": 30],
    "missing": .null
]

// ...or from Swift types
let swiftValue: Any? = ["name": "John", "items": [1, 2, 3]]
let jinjaValue = try Value(any: swiftValue)
```

## Examples

### HTML Generation

```swift
import Jinja

// Generate HTML from template
let htmlTemplate = try Template("""
    <!DOCTYPE html>
    <html>
    <head>
        <title>{{ page.title }}</title>
    </head>
    <body>
        <h1>{{ page.heading }}</h1>
        <ul>
        {% for item in page.items %}
            <li><a href="{{ item.url }}">{{ item.title }}</a></li>
        {% endfor %}
        </ul>
    </body>
    </html>
    """)

let context: [String: Value] = [
    "page": [
        "title": "My Website",
        "heading": "Welcome",
        "items": .array([
            ["title": "Home", "url": "/"),
            ["title": "About", "url": "/about"],
            ["title": "Contact", "url": "/contact"]
        ]
    ]
]

let html = try htmlTemplate.render(context)
```

### Configuration File Generation

```swift
// Generate configuration files
let configTemplate = try Template("""
    # {{ app.name }} Configuration
    
    [server]
    host = "{{ server.host }}"
    port = {{ server.port }}
    debug = {{ server.debug | lower }}
    
    [database]
    {% for db in databases %}
    [database.{{ db.name }}]
    url = "{{ db.url }}"
    pool_size = {{ db.pool_size }}
    {% endfor %}
    """)

let context: [String: Value] = [
    "app": ["name": "MyApp"],
    "server": [
        "host": "localhost",
        "port": 8080,
        "debug": true
    ],
    "databases": [
        [
            "name": "primary",
            "url": "postgresql://localhost/myapp",
            "pool_size": 10
        ]
    ]
]

let config = try configTemplate.render(context)
```

### Chat Message Formatting

```swift
// Format chat messages (useful for AI/LLM applications)
let chatTemplate = try Template("""
    {% for message in messages %}
        {% if message.role == "system" %}
            System: {{ message.content }}
        {% elif message.role == "user" %}
            User: {{ message.content }}
        {% elif message.role == "assistant" %}
            Assistant: {{ message.content }}
        {% endif %}
    {% endfor %}
    """, with: Template.Options(lstripBlocks: true, trimBlocks: true))

let messages: [String: Value] = [
    "messages": [
        [
            "role": "system",
            "content": "You are a helpful assistant."
        ],
        [
            "role": "user",
            "content": "What's the weather like?"
        ],
        [
            "role": "assistant",
            "content": "I'd be happy to help with weather information!"
        ]
    ]
]

let formatted = try chatTemplate.render(messages)
```

## License

Jinja is available under the MIT license. 
See the [LICENSE](LICENSE) file for more info.
