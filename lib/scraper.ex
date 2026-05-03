defmodule Automator.Scraper do
  @moduledoc """
  High-level scraping API that manages a Chromium instance and page connection.

  This is the primary interface for web scraping. It spawns a headless Chromium
  browser, connects to a page, and provides simple functions for navigation,
  JavaScript evaluation, and interaction.

  ## Example

      {:ok, scraper} = Automator.Scraper.start_link()

      Automator.Scraper.navigate(scraper, "https://example.com")
      title = Automator.Scraper.eval(scraper, "document.title")
      # => "Example Domain"

      Automator.Scraper.wait_for_selector(scraper, "h1")
      Automator.Scraper.click(scraper, "a")
      Automator.Scraper.screenshot(scraper, "page.png")

      Automator.Scraper.stop(scraper)

  ## Architecture

  `Scraper` is a `GenServer` that owns:

    1. A headless Chromium process (via `Automator.Chromium.spawn/0`)
    2. A WebSocket connection to a page target (via `Automator.Client`)

  When you call `stop/1`, the Chromium process is killed and the GenServer
  terminates.

  ## CDP Commands Used

  | Function | CDP Method |
  |----------|------------|
  | `navigate/2` | `Page.navigate` |
  | `eval/2` | `Runtime.evaluate` |
  | `click/2` | `Runtime.evaluate` (with `document.querySelector`) |
  | `wait_for_selector/3` | `Runtime.evaluate` (with `MutationObserver`) |
  | `screenshot/1`, `screenshot/2` | `Page.captureScreenshot` |
  | `set_cookie/4` | `Network.setCookie` |

  For raw CDP access beyond these methods, use `Automator.Client` directly.

  """

  use TypedStruct
  use GenServer

  typedstruct enforce: true do
    field(:browser, Automator.Chromium.t())
    field(:client, pid())
  end

  @default_navigate_wait_ms 1_000
  @navigate_call_buffer_ms 30_000

  @doc """
  Starts a new scraper by spawning Chromium and connecting to a page.

  Returns `{:ok, pid}` where `pid` is the scraper process.

  ## Example

      {:ok, scraper} = Automator.Scraper.start_link()

  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    cookies = Keyword.get(opts, :cookies, [])
    GenServer.start_link(__MODULE__, %{cookies: cookies}, name: name)
  end

  @doc """
  Navigates to the given URL.

  Waits briefly for the page to load before returning.

  ## Parameters

    * `pid` - The scraper process
    * `url` - The URL to navigate to
    * `opts` - Options:
      * `:wait_ms` - milliseconds to wait after `Page.navigate` before returning.
        Defaults to `1_000`. Increase for SPA hydration, lazy images, or sites
        with heavy async rendering.

  ## Example

      Automator.Scraper.navigate(scraper, "https://example.com")
      Automator.Scraper.navigate(scraper, "https://app.example.com", wait_ms: 4_000)

  """
  def navigate(pid, url, opts \\ []) do
    wait_ms = validate_wait_ms!(Keyword.get(opts, :wait_ms, @default_navigate_wait_ms))
    GenServer.call(pid, {:navigate, url, wait_ms}, wait_ms + @navigate_call_buffer_ms)
  end

  defp validate_wait_ms!(wait_ms) when is_integer(wait_ms) and wait_ms >= 0, do: wait_ms

  defp validate_wait_ms!(other) do
    raise ArgumentError, "wait_ms must be a non-negative integer, got: #{inspect(other)}"
  end

  @doc """
  Evaluates JavaScript in the page context and returns the result value.

  Uses `Runtime.evaluate` with `awaitPromise: true` and `returnByValue: true`,
  so async functions and promises are awaited, and the actual value is returned
  (not a RemoteObject reference).

  ## Parameters

    * `pid` - The scraper process
    * `js` - The JavaScript expression to evaluate

  ## Returns

    The JavaScript result value, converted to an Elixir term.

  ## Example

      Automator.Scraper.eval(scraper, "document.title")
      # => "Example Domain"

      Automator.Scraper.eval(scraper, "document.querySelectorAll('a').length")
      # => 1

      Automator.Scraper.eval(scraper, "Array.from(document.querySelectorAll('a')).map(a => a.href)")
      # => ["https://www.iana.org/domains/example"]

  """
  def eval(pid, js) do
    GenServer.call(pid, {:eval, js})
  end

  @doc """
  Clicks an element matching the CSS selector.

  Uses `document.querySelector` to find the element and calls `.click()` on it.

  ## Parameters

    * `pid` - The scraper process
    * `selector` - A CSS selector string

  ## Returns

    `true` if the element was found and clicked, `false` otherwise.

  ## Example

      Automator.Scraper.click(scraper, "button.submit")
      # => true

      Automator.Scraper.click(scraper, "a[href='/next']")
      # => true

  """
  def click(pid, selector) do
    GenServer.call(pid, {:click, selector})
  end

  @doc """
  Waits for an element matching the CSS selector to appear in the DOM.

  Uses a `MutationObserver` to react immediately when the element is added,
  rather than polling. Times out after the given milliseconds.

  ## Parameters

    * `pid` - The scraper process
    * `selector` - A CSS selector string
    * `timeout` - Maximum wait time in milliseconds (default: 10,000)

  ## Returns

    * `:ok` - The element was found
    * `{:error, reason}` - The element was not found within the timeout

  ## Example

      Automator.Scraper.wait_for_selector(scraper, "h1")
      # => :ok

      Automator.Scraper.wait_for_selector(scraper, ".dynamic-content", 5000)
      # => :ok

      Automator.Scraper.wait_for_selector(scraper, ".nonexistent", 1000)
      # => {:error, "selector .nonexistent not found within 1000ms"}

  """
  def wait_for_selector(pid, selector, timeout \\ 10_000) do
    GenServer.call(pid, {:wait_for_selector, selector, timeout})
  end

  @doc """
  Captures a screenshot of the current page.

  Returns a map with a `"data"` key containing the base64-encoded PNG image.
  See also `screenshot/2` to write directly to a file.

  ## Parameters

    * `pid` - The scraper process

  ## Example

      %{"data" => base64} = Automator.Scraper.screenshot(scraper)
      File.write!("screenshot.png", Base.decode64!(base64))

  """
  def screenshot(pid) do
    GenServer.call(pid, {:screenshot})
  end

  @doc """
  Captures a screenshot and writes it to the given file path.

  Decodes the base64 PNG data and writes it directly to disk.

  ## Parameters

    * `pid` - The scraper process
    * `path` - File path to write the PNG to

  ## Example

      Automator.Scraper.screenshot(scraper, "screenshot.png")
      # => :ok

  """
  def screenshot(pid, path) do
    GenServer.call(pid, {:screenshot, path})
  end

  @doc """
  Sets a cookie for the given domain.

  ## Parameters

    * `pid` - The scraper process
    * `name` - The cookie name
    * `value` - The cookie value
    * `domain` - The cookie domain (e.g., `".example.com"`)

  ## Example

      Automator.Scraper.set_cookie(scraper, "session", "abc123", ".example.com")
      # => %{"success" => true}

  """
  def set_cookie(pid, name, value, domain) do
    GenServer.call(pid, {:set_cookie, name, value, domain})
  end

  @doc """
  Stops the scraper, killing the Chromium process.

  ## Example

      Automator.Scraper.stop(scraper)

  """
  def stop(pid) do
    GenServer.call(pid, :stop)
  end

  def init(args) do
    browser = Automator.Chromium.spawn()
    {:ok, %{body: targets}} = Req.get("http://127.0.0.1:#{browser.port}/json")

    page_ws_url =
      targets |> Enum.find(fn t -> t["type"] == "page" end) |> Map.fetch!("webSocketDebuggerUrl")

    {:ok, client} = Automator.Client.start_link(page_ws_url)

    for {name, value, domain} <- args.cookies do
      Automator.Client.send_command(client, "Network.setCookie", %{
        name: name,
        value: value,
        domain: domain
      })
    end

    {:ok, %__MODULE__{browser: browser, client: client}}
  end

  def handle_call({:navigate, url, wait_ms}, _from, %__MODULE__{client: client} = state) do
    {:ok, result} = Automator.Client.send_command(client, "Page.navigate", %{url: url})
    :timer.sleep(wait_ms)
    {:reply, result, state}
  end

  def handle_call({:eval, js}, _from, %__MODULE__{client: client} = state) do
    {:ok, result} =
      Automator.Client.send_command(client, "Runtime.evaluate", %{
        expression: js,
        awaitPromise: true,
        returnByValue: true
      })

    value = result["result"]["value"]
    {:reply, value, state}
  end

  def handle_call({:click, selector}, _from, %__MODULE__{client: client} = state) do
    {:ok, %{"result" => %{"value" => coords}}} =
      Automator.Client.send_command(client, "Runtime.evaluate", %{
        expression: """
        (() => {
          const el = document.querySelector('#{selector}');
          if (!el) return null;
          const r = el.getBoundingClientRect();
          return {x: r.x + r.width / 2, y: r.y + r.height / 2};
        })()
        """,
        returnByValue: true
      })

    if coords do
      for type <- ["mousePressed", "mouseReleased"] do
        Automator.Client.send_command(client, "Input.dispatchMouseEvent", %{
          type: type,
          x: coords["x"],
          y: coords["y"],
          button: "left",
          clickCount: 1
        })
      end

      {:reply, true, state}
    else
      {:reply, false, state}
    end
  end

  def handle_call(
        {:wait_for_selector, selector, timeout},
        _from,
        %__MODULE__{client: client} = state
      ) do
    {:ok, result} =
      Automator.Client.send_command(client, "Runtime.evaluate", %{
        expression: """
        new Promise((resolve, reject) => {
          const el = document.querySelector('#{selector}');
          if (el) return resolve(true);
          const observer = new MutationObserver(() => {
            if (document.querySelector('#{selector}')) {
              observer.disconnect();
              resolve(true);
            }
          });
          observer.observe(document, {childList: true, subtree: true});
          setTimeout(() => { observer.disconnect(); reject(new Error('timeout')); }, #{timeout});
        })
        """,
        awaitPromise: true,
        returnByValue: true
      })

    case result["result"]["type"] do
      "boolean" -> {:reply, :ok, state}
      "object" -> {:reply, {:error, "selector #{selector} not found within #{timeout}ms"}, state}
    end
  end

  def handle_call({:screenshot}, _from, %__MODULE__{client: client} = state) do
    {:ok, result} = Automator.Client.send_command(client, "Page.captureScreenshot")
    {:reply, result, state}
  end

  def handle_call({:screenshot, path}, _from, %__MODULE__{client: client} = state) do
    {:ok, %{"data" => base64}} = Automator.Client.send_command(client, "Page.captureScreenshot")
    File.write!(path, Base.decode64!(base64))
    {:reply, :ok, state}
  end

  def handle_call({:set_cookie, name, value, domain}, _from, %__MODULE__{client: client} = state) do
    {:ok, result} =
      Automator.Client.send_command(client, "Network.setCookie", %{
        name: name,
        value: value,
        domain: domain
      })

    {:reply, result, state}
  end

  def handle_call(:stop, _from, %__MODULE__{browser: browser} = state) do
    Automator.Chromium.kill(browser)
    {:stop, :normal, :ok, state}
  end
end
