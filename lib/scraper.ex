defmodule CDP.Scraper do
  @moduledoc """
  High-level scraping API that manages a Chromium instance and page connection.

  This is the primary interface for web scraping. It spawns a headless Chromium
  browser, connects to a page, and provides simple functions for navigation,
  JavaScript evaluation, and interaction.

  ## Example

      {:ok, scraper} = CDP.Scraper.start_link()

      CDP.Scraper.navigate(scraper, "https://example.com")
      title = CDP.Scraper.eval(scraper, "document.title")
      # => "Example Domain"

      CDP.Scraper.wait_for_selector(scraper, "h1")
      CDP.Scraper.click(scraper, "a")

      %{"data" => base64} = CDP.Scraper.screenshot(scraper)

      CDP.Scraper.stop(scraper)

  """

  use GenServer

  @doc """
  Starts a new scraper by spawning Chromium and connecting to a page.

  Returns `{:ok, pid}` where `pid` is the scraper process.

  ## Example

      {:ok, scraper} = CDP.Scraper.start_link()

  """
  def start_link do
    GenServer.start_link(__MODULE__, [])
  end

  @doc """
  Navigates to the given URL.

  Waits briefly for the page to load before returning.

  ## Parameters

    * `pid` - The scraper process
    * `url` - The URL to navigate to

  ## Example

      CDP.Scraper.navigate(scraper, "https://example.com")

  """
  def navigate(pid, url) do
    GenServer.call(pid, {:navigate, url})
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

      CDP.Scraper.eval(scraper, "document.title")
      # => "Example Domain"

      CDP.Scraper.eval(scraper, "document.querySelectorAll('a').length")
      # => 1

      CDP.Scraper.eval(scraper, "Array.from(document.querySelectorAll('a')).map(a => a.href)")
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

      CDP.Scraper.click(scraper, "button.submit")
      # => true

      CDP.Scraper.click(scraper, "a[href='/next']")
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

      CDP.Scraper.wait_for_selector(scraper, "h1")
      # => :ok

      CDP.Scraper.wait_for_selector(scraper, ".dynamic-content", 5000)
      # => :ok

      CDP.Scraper.wait_for_selector(scraper, ".nonexistent", 1000)
      # => {:error, "selector .nonexistent not found within 1000ms"}

  """
  def wait_for_selector(pid, selector, timeout \\ 10_000) do
    GenServer.call(pid, {:wait_for_selector, selector, timeout})
  end

  @doc """
  Captures a screenshot of the current page.

  Returns a map with a `"data"` key containing the base64-encoded PNG image.

  ## Parameters

    * `pid` - The scraper process

  ## Example

      %{"data" => base64} = CDP.Scraper.screenshot(scraper)
      File.write!("screenshot.png", Base.decode64!(base64))

  """
  def screenshot(pid) do
    GenServer.call(pid, {:screenshot})
  end

  @doc """
  Sets a cookie for the given domain.

  ## Parameters

    * `pid` - The scraper process
    * `name` - The cookie name
    * `value` - The cookie value
    * `domain` - The cookie domain (e.g., `".example.com"`)

  ## Example

      CDP.Scraper.set_cookie(scraper, "session", "abc123", ".example.com")
      # => %{"success" => true}

  """
  def set_cookie(pid, name, value, domain) do
    GenServer.call(pid, {:set_cookie, name, value, domain})
  end

  @doc """
  Stops the scraper, killing the Chromium process.

  ## Example

      CDP.Scraper.stop(scraper)

  """
  def stop(pid) do
    GenServer.call(pid, :stop)
  end

  def init([]) do
    browser = CDP.Chromium.spawn()
    {:ok, %{body: targets}} = Req.get("http://localhost:#{browser.port}/json")

    page_ws_url =
      targets |> Enum.find(fn t -> t["type"] == "page" end) |> Map.fetch!("webSocketDebuggerUrl")

    {:ok, client} = CDP.Client.start_link(page_ws_url)
    {:ok, %{browser: browser, client: client}}
  end

  def handle_call({:navigate, url}, _from, %{client: client} = state) do
    {:ok, result} = CDP.Client.send_command(client, "Page.navigate", %{url: url})
    :timer.sleep(1000)
    {:reply, result, state}
  end

  def handle_call({:eval, js}, _from, %{client: client} = state) do
    {:ok, result} =
      CDP.Client.send_command(client, "Runtime.evaluate", %{
        expression: js,
        awaitPromise: true,
        returnByValue: true
      })

    value = result["result"]["value"]
    {:reply, value, state}
  end

  def handle_call({:click, selector}, _from, %{client: client} = state) do
    {:ok, result} =
      CDP.Client.send_command(client, "Runtime.evaluate", %{
        expression: """
        (() => {
          const el = document.querySelector('#{selector}');
          if (el) { el.click(); return true; }
          return false;
        })()
        """,
        returnByValue: true
      })

    {:reply, result["result"]["value"], state}
  end

  def handle_call({:wait_for_selector, selector, timeout}, _from, %{client: client} = state) do
    {:ok, result} =
      CDP.Client.send_command(client, "Runtime.evaluate", %{
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

  def handle_call({:screenshot}, _from, %{client: client} = state) do
    {:ok, result} = CDP.Client.send_command(client, "Page.captureScreenshot")
    {:reply, result, state}
  end

  def handle_call({:set_cookie, name, value, domain}, _from, %{client: client} = state) do
    {:ok, result} =
      CDP.Client.send_command(client, "Network.setCookie", %{
        name: name,
        value: value,
        domain: domain
      })

    {:reply, result, state}
  end

  def handle_call(:stop, _from, %{browser: browser} = state) do
    CDP.Chromium.kill(browser)
    {:stop, :normal, :ok, state}
  end
end
