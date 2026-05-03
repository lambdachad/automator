# Automator

Chrome DevTools Protocol (CDP) scraper for Elixir. Spawn headless Chromium, navigate pages, evaluate JavaScript, and extract data — all through a clean, idiomatic Elixir API.

## Installation

Add `:automator` to your dependencies:

```elixir
def deps do
  [
    {:automator, "~> 0.1.0"}
  ]
end
```

Requires Chromium installed and available on PATH as `chromium`.

## Quick Start

```elixir
# Start a scraper (spawns Chromium + connects automatically)
{:ok, scraper} = Automator.Scraper.start_link()

# Navigate to a page
Automator.Scraper.navigate(scraper, "https://example.com")

# Evaluate JavaScript
title = Automator.Scraper.eval(scraper, "document.title")
# => "Example Domain"

# Wait for an element to appear
Automator.Scraper.wait_for_selector(scraper, "h1")

# Click an element
Automator.Scraper.click(scraper, "a")

# Take a screenshot (returns base64)
%{"data" => base64} = Automator.Scraper.screenshot(scraper)
File.write!("page.png", Base.decode64!(base64))

# Set cookies
Automator.Scraper.set_cookie(scraper, "session", "abc123", ".example.com")

# Cleanup
Automator.Scraper.stop(scraper)
```

## Architecture

Automator has three layers, from high-level to low-level:

```
┌─────────────────────────────────────────┐
│  Automator.Scraper  (GenServer)         │  ← Primary API
│  Manages browser + page, simple fns     │
├─────────────────────────────────────────┤
│  Automator.Client   (WebSockex)         │  ← Raw CDP commands
│  WebSocket JSON-RPC client              │
├─────────────────────────────────────────┤
│  Automator.Chromium (Process mgmt)      │  ← Browser lifecycle
│  Spawns/kills headless Chromium         │
└─────────────────────────────────────────┘
```

Most users only need `Automator.Scraper`. Use `Client` when you need direct access to CDP domains not exposed by the scraper. Use `Chromium` when you want to manage the browser lifecycle yourself.

## API Reference

### Automator.Scraper

High-level scraping API. A `GenServer` that owns a Chromium instance and a page-level WebSocket connection.

#### `start_link/0`

Spawns headless Chromium and connects to a blank page.

```elixir
{:ok, scraper} = Automator.Scraper.start_link()
```

Returns `{:ok, pid}`.

#### `navigate/2`

Navigates to a URL. Waits ~1 second for the page to load before returning.

```elixir
Automator.Scraper.navigate(scraper, "https://example.com")
```

**Parameters:**

| Param | Type | Description |
|-------|------|-------------|
| `pid` | `pid` | Scraper process |
| `url` | `String.t()` | URL to navigate to |

#### `eval/2`

Evaluates JavaScript in the page context. Supports async/await — promises are awaited automatically.

```elixir
Automator.Scraper.eval(scraper, "document.title")
# => "Example Domain"

Automator.Scraper.eval(scraper, "document.querySelectorAll('a').length")
# => 1

Automator.Scraper.eval(scraper, "Array.from(document.querySelectorAll('a')).map(a => a.href)")
# => ["https://www.iana.org/domains/example"]

# Async example
Automator.Scraper.eval(scraper, """
  await fetch('/api/data').then(r => r.json())
""")
```

**Parameters:**

| Param | Type | Description |
|-------|------|-------------|
| `pid` | `pid` | Scraper process |
| `js` | `String.t()` | JavaScript expression |

**Returns:** The JavaScript result value, converted to an Elixir term.

#### `click/2`

Clicks an element matching a CSS selector.

```elixir
Automator.Scraper.click(scraper, "button.submit")
# => true

Automator.Scraper.click(scraper, ".nonexistent")
# => false
```

**Parameters:**

| Param | Type | Description |
|-------|------|-------------|
| `pid` | `pid` | Scraper process |
| `selector` | `String.t()` | CSS selector |

**Returns:** `true` if element found and clicked, `false` otherwise.

#### `wait_for_selector/3`

Waits for an element to appear in the DOM using a `MutationObserver` (not polling).

```elixir
Automator.Scraper.wait_for_selector(scraper, "h1")
# => :ok

Automator.Scraper.wait_for_selector(scraper, ".dynamic-content", 5000)
# => :ok

Automator.Scraper.wait_for_selector(scraper, ".nonexistent", 1000)
# => {:error, "selector .nonexistent not found within 1000ms"}
```

**Parameters:**

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `pid` | `pid` | — | Scraper process |
| `selector` | `String.t()` | — | CSS selector |
| `timeout` | `integer()` | `10_000` | Max wait time in ms |

**Returns:** `:ok` or `{:error, reason}`.

#### `screenshot/1`

Captures a screenshot of the current page as a base64-encoded PNG.

```elixir
%{"data" => base64} = Automator.Scraper.screenshot(scraper)
File.write!("screenshot.png", Base.decode64!(base64))
```

**Parameters:**

| Param | Type | Description |
|-------|------|-------------|
| `pid` | `pid` | Scraper process |

**Returns:** `%{"data" => base64_string}`.

#### `set_cookie/4`

Sets a cookie for the given domain.

```elixir
Automator.Scraper.set_cookie(scraper, "session", "abc123", ".example.com")
# => %{"success" => true}
```

**Parameters:**

| Param | Type | Description |
|-------|------|-------------|
| `pid` | `pid` | Scraper process |
| `name` | `String.t()` | Cookie name |
| `value` | `String.t()` | Cookie value |
| `domain` | `String.t()` | Cookie domain (e.g., `".example.com"`) |

#### `stop/1`

Stops the scraper and kills the Chromium process.

```elixir
Automator.Scraper.stop(scraper)
# => :ok
```

---

### Automator.Chromium

Low-level browser process management. Use this when you want to manage the Chromium lifecycle yourself and connect multiple clients.

#### `spawn/0`

Launches headless Chromium on an available port.

```elixir
browser = Automator.Chromium.spawn()
# => %{
#   chromium: #Port<0.5>,
#   os_pid: 12345,
#   port: 9222,
#   ws_url: "ws://localhost:9222/devtools/browser/...",
#   user_data_dir: "/tmp/automator-..."
# }
```

**Flags used:**

| Flag | Value |
|------|-------|
| `--headless` | `new` |
| `--no-sandbox` | — |
| `--disable-gpu` | — |
| `--window-size` | `1920,1080` |
| `--user-data-dir` | unique temp directory (cleaned up on `kill/1`) |
| `--remote-debugging-port` | auto-detected |

**Returns:** A struct with `:chromium` (port ref), `:os_pid`, `:port`, `:ws_url`, and `:user_data_dir`.

#### `kill/1`

Kills the Chromium process by OS PID.

```elixir
browser = Automator.Chromium.spawn()
Automator.Chromium.kill(browser)
```

**Parameters:**

| Param | Type | Description |
|-------|------|-------------|
| `browser` | `map()` | Map returned by `spawn/0` |

---

### Automator.Client

Low-level WebSocket client for sending raw CDP commands. Use this when you need access to CDP domains not exposed by `Scraper`.

#### `start_link/1`

Connects to a Chromium WebSocket debugger URL.

```elixir
{:ok, client} = Automator.Client.start_link("ws://localhost:9222/devtools/browser/...")
```

**Parameters:**

| Param | Type | Description |
|-------|------|-------------|
| `ws_url` | `String.t()` | WebSocket URL from `Chromium.spawn().ws_url` or `/json` endpoint |

#### `send_command/3`

Sends a CDP command and blocks until the response arrives.

```elixir
# Browser-level command
{:ok, result} = Automator.Client.send_command(client, "Browser.getVersion")
IO.inspect(result["product"])
# => "Chrome/145.0.7632.159"

# Page-level command
{:ok, page_client} = Automator.Client.start_link(page_ws_url)
{:ok, _} = Automator.Client.send_command(page_client, "Page.navigate", %{url: "https://example.com"})

# With parameters
{:ok, result} = Automator.Client.send_command(page_client, "Runtime.evaluate", %{
  expression: "document.title",
  returnByValue: true
})
```

**Parameters:**

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `pid` | `pid` | — | Client process |
| `method` | `String.t()` | — | CDP method name |
| `params` | `map()` | `%{}` | Command parameters |

**Returns:** `{:ok, result}` or `{:error, error}`.

See the [CDP protocol documentation](https://chromedevtools.github.io/devtools-protocol/) for all available domains and methods.

## Common Patterns

### Scraping a list of items

```elixir
{:ok, scraper} = Automator.Scraper.start_link()
Automator.Scraper.navigate(scraper, "https://example.com/products")

items = Automator.Scraper.eval(scraper, """
  Array.from(document.querySelectorAll('.product')).map(el => ({
    name: el.querySelector('.name').textContent,
    price: el.querySelector('.price').textContent,
    url: el.querySelector('a').href
  }))
""")

Automator.Scraper.stop(scraper)
```

### Waiting for dynamic content

```elixir
{:ok, scraper} = Automator.Scraper.start_link()
Automator.Scraper.navigate(scraper, "https://example.com")

# Wait for SPA to render
Automator.Scraper.wait_for_selector(scraper, ".app-root", 15_000)

# Interact
Automator.Scraper.click(scraper, "button.load-more")
Automator.Scraper.wait_for_selector(scraper, ".item:nth-child(20)", 10_000)

# Extract
data = Automator.Scraper.eval(scraper, "window.__INITIAL_STATE__")

Automator.Scraper.stop(scraper)
```

### Using cookies for authenticated sessions

```elixir
{:ok, scraper} = Automator.Scraper.start_link()

# Set auth cookie
Automator.Scraper.set_cookie(scraper, "auth_token", "secret", ".example.com")

# Navigate — already authenticated
Automator.Scraper.navigate(scraper, "https://example.com/dashboard")
profile = Automator.Scraper.eval(scraper, "document.querySelector('.profile').textContent")

Automator.Scraper.stop(scraper)
```

### Raw CDP access for advanced use cases

```elixir
# Start scraper for browser management
{:ok, scraper} = Automator.Scraper.start_link()
Automator.Scraper.navigate(scraper, "https://example.com")

# Access performance metrics via CDP
Automator.Scraper.eval(scraper, "performance.getEntriesByType('navigation')[0]")

# Or use Client directly for any CDP domain
# (e.g., Network, DOM, CSS, Accessibility, etc.)
Automator.Scraper.stop(scraper)
```

## CDP Domains

Through `Automator.Client.send_command/3`, you have access to the full Chrome DevTools Protocol. Commonly useful domains:

| Domain | Use case |
|--------|----------|
| `Page` | Navigation, screenshots, lifecycle events |
| `Runtime` | JavaScript evaluation, object inspection |
| `DOM` | DOM tree traversal, node manipulation |
| `Network` | Request/response interception, cookies |
| `CSS` | Stylesheet inspection, computed styles |
| `Input` | Mouse/keyboard simulation |
| `Emulation` | Device emulation, viewport, geolocation |
| `Browser` | Browser info, window management |
| `Target` | Tab/page management |

See the [full CDP reference](https://chromedevtools.github.io/devtools-protocol/) for every method.

## License

MIT
