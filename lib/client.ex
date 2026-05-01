defmodule Automator.Client do
  @moduledoc """
  Low-level WebSocket client for sending raw Chrome DevTools Protocol (CDP) commands.

  Connects to a Chromium WebSocket debugger URL and sends commands using the
  JSON-RPC protocol. Use this when you need direct access to CDP methods not
  exposed by `Automator.Scraper`.

  ## Example

      # Connect to a browser-level WebSocket
      {:ok, client} = Automator.Client.start_link(ws_url)

      # Send any CDP command
      {:ok, result} = Automator.Client.send_command(client, "Browser.getVersion")
      IO.inspect(result["product"])
      # => "Chrome/145.0.7632.159"

      # Connect to a page target for page-level commands
      {:ok, page_client} = Automator.Client.start_link(page_ws_url)
      {:ok, _} = Automator.Client.send_command(page_client, "Page.navigate", %{url: "https://example.com"})

  ## Protocol

  Commands follow the Chrome DevTools Protocol JSON-RPC format:

      {"id": 1, "method": "Page.navigate", "params": {"url": "https://example.com"}}

  Responses are matched to callers by the `id` field. See the
  [CDP protocol reference](https://chromedevtools.github.io/devtools-protocol/)
  for all available domains and methods.

  ## Common CDP Domains

  | Domain | Use case |
  |--------|----------|
  | `Page` | Navigation, screenshots, lifecycle events |
  | `Runtime` | JavaScript evaluation, object inspection |
  | `DOM` | DOM tree traversal, node manipulation |
  | `Network` | Request interception, cookies |
  | `Input` | Mouse/keyboard simulation |
  | `Emulation` | Device emulation, viewport, geolocation |
  | `Browser` | Browser info, window management |
  | `Target` | Tab/page management |

  ## When to Use

  Use `Client` directly when you need:

    * CDP domains not exposed by `Automator.Scraper` (e.g., `DOM`, `Network`, `Input`)
    * Fine-grained control over command parameters
    * Browser-level commands (via the browser WebSocket URL)
    * Multiple concurrent page connections to the same browser

  For most scraping tasks, `Automator.Scraper` is simpler and handles connection
  management automatically.

  """

  use TypedStruct
  use WebSockex

  typedstruct enforce: true do
    field(:next_id, non_neg_integer())
    field(:callers, %{non_neg_integer() => pid()})
  end

  @doc """
  Connects to a Chromium WebSocket debugger URL.

  Returns `{:ok, pid}` where `pid` is the client process.

  ## Parameters

    * `ws_url` - The WebSocket URL from `Automator.Chromium.spawn().ws_url` or
      from the `/json` HTTP endpoint for a specific page target.

  ## Example

      {:ok, client} = Automator.Client.start_link("ws://localhost:9222/devtools/browser/...")

  """
  def start_link(ws_url) do
    WebSockex.start_link(ws_url, __MODULE__, %__MODULE__{next_id: 1, callers: %{}})
  end

  @doc """
  Sends a Automator command and blocks until the response arrives.

  Commands follow the Automator JSON-RPC format. See the
  [Automator protocol documentation](https://chromedevtools.github.io/devtools-protocol/)
  for available methods and parameters.

  ## Parameters

    * `pid` - The client process returned by `start_link/1`
    * `method` - The Automator method name (e.g., `"Page.navigate"`, `"Runtime.evaluate"`)
    * `params` - A map of parameters for the command (defaults to `%{}`)

  ## Returns

    * `{:ok, result}` - The Automator response body
    * `{:error, error}` - If Automator returned an error response

  ## Example

      {:ok, result} = Automator.Client.send_command(client, "Page.navigate", %{url: "https://example.com"})
      # => {:ok, %{"frameId" => "...", "loaderId" => "..."}}

      {:ok, result} = Automator.Client.send_command(client, "Runtime.evaluate", %{
        expression: "document.title",
        returnByValue: true
      })
      # => {:ok, %{"result" => %{"type" => "string", "value" => "Example Domain"}}}

  """
  def send_command(pid, method, params \\ %{}) do
    send(pid, {:send_command, self(), method, params})

    receive do
      response -> response
    end
  end

  @doc false
  def handle_info({:send_command, caller, method, params}, state) do
    id = state.next_id
    message = Jason.encode!(%{id: id, method: method, params: params})

    {:reply, {:text, message},
     %{state | next_id: id + 1, callers: Map.put(state.callers, id, caller)}}
  end

  @doc false
  def handle_frame({:text, raw}, state) do
    %{"id" => id} = decoded = Jason.decode!(raw)

    case decoded do
      %{"result" => result} ->
        send(Map.get(state.callers, id), {:ok, result})

      %{"error" => error} ->
        send(Map.get(state.callers, id), {:error, error})
    end

    {:ok, %{state | callers: Map.delete(state.callers, id)}}
  end
end
