defmodule CDP.Chromium do
  def spawn do
    # Spawn Chromium in headless mode on available port
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

    # Get WebSocket debugger URL
    version_url = "http://localhost:#{port}/json/version"
    {:ok, %{body: %{"webSocketDebuggerUrl" => ws_url}}} = Req.get(version_url, retry_log_level: false)
    %{chromium: chromium, os_pid: os_pid, ws_url: ws_url}
  end

  def kill(%{os_pid: os_pid}) do
    System.cmd("kill", ["-9", "#{os_pid}"])
  end

  defp available_port do
    # Create TCP socket then close it to get available port
    {:ok, port} = :gen_tcp.listen(0, [])
    {:ok, port_number} = :inet.port(port)
    Port.close(port)
    port_number
  end
end
