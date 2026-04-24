defmodule Automator.Client do
  @moduledoc """
  Low-level Automator WebSocket client.

  Connects to a Chromium WebSocket debugger URL and sends Automator commands
  using the JSON-RPC protocol. Use this when you need direct access to
  Automator methods not exposed by `Automator.Scraper`.

  For most use cases, prefer `Automator.Scraper` which manages the browser
  and page connection automatically.

  ## Example

      # Connect to a browser-level WebSocket
      {:ok, client} = Automator.Client.start_link(ws_url)

      # Send any Automator command
      {:ok, result} = Automator.Client.send_command(client, "Browser.getVersion")
      IO.inspect(result["product"])
      # => "Chrome/145.0.7632.159"

      # Connect to a page target for page-level commands
      {:ok, page_client} = Automator.Client.start_link(page_ws_url)
      {:ok, _} = Automator.Client.send_command(page_client, "Page.navigate", %{url: "https://example.com"})

  """

  use WebSockex

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
    WebSockex.start_link(ws_url, __MODULE__, %{next_id: 1, callers: %{}})
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
