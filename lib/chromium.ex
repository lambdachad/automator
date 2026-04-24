defmodule CDP.Chromium do
  @moduledoc """
  Low-level Chromium process management.

  Spawns a headless Chromium instance and provides the WebSocket debugger URL
  needed to connect via `CDP.Client` or `CDP.Scraper`.

  ## Example

      browser = CDP.Chromium.spawn()
      # => %{chromium: #Port<...>, os_pid: 1234, port: 9222, ws_url: "ws://..."}

      # Use the ws_url to connect...
      CDP.Chromium.kill(browser)

  ## Browser struct

  `spawn/0` returns a map with these keys:

    * `:chromium` - The Erlang port reference
    * `:os_pid` - The OS process ID, needed for `kill/1`
    * `:port` - The TCP port Chromium is listening on
    * `:ws_url` - The WebSocket debugger URL for the browser target

  """

  @doc """
  Spawns a headless Chromium instance on an available port.

  Launches Chromium with `--headless=new`, `--no-sandbox`, `--disable-gpu`,
  and `--window-size=1920,1080`. Finds an available TCP port automatically
  and sets `--remote-debugging-port` to it.

  Returns a map with `:chromium`, `:os_pid`, `:port`, and `:ws_url`.

  ## Example

      browser = CDP.Chromium.spawn()
      IO.puts(browser.ws_url)
      # => "ws://localhost:9222/devtools/browser/..."

  """
  def spawn do
    port = available_port()
    chromium_path = System.find_executable("chromium")

    chromium =
      Port.open({:spawn_executable, chromium_path},
        args: [
          "--headless=new",
          "--no-sandbox",
          "--disable-gpu",
          "--window-size=1920,1080",
          "--remote-debugging-port=#{port}"
        ]
      )

    {:os_pid, os_pid} = Port.info(chromium, :os_pid)

    version_url = "http://localhost:#{port}/json/version"

    {:ok, %{body: %{"webSocketDebuggerUrl" => ws_url}}} =
      Req.get(version_url, retry_log_level: false)

    %{chromium: chromium, os_pid: os_pid, port: port, ws_url: ws_url}
  end

  @doc """
  Kills the Chromium process by OS PID.

  ## Example

      browser = CDP.Chromium.spawn()
      CDP.Chromium.kill(browser)

  """
  def kill(%{os_pid: os_pid}) do
    System.cmd("kill", ["-9", "#{os_pid}"])
  end

  defp available_port do
    {:ok, port} = :gen_tcp.listen(0, [])
    {:ok, port_number} = :inet.port(port)
    Port.close(port)
    port_number
  end
end
