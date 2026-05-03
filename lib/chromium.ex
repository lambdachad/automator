defmodule Automator.Chromium do
  @moduledoc """
  Low-level Chromium process management.

  Spawns a headless Chromium instance and provides the WebSocket debugger URL
  needed to connect via `Automator.Client` or `Automator.Scraper`.

  ## Example

      browser = Automator.Chromium.spawn()
      # => %Automator.Chromium{chromium: #Port<...>, os_pid: 1234, port: 9222, ws_url: \"ws://...\", user_data_dir: \"/tmp/...\"}

      # Connect to the browser target
      {:ok, client} = Automator.Client.start_link(browser.ws_url)
      {:ok, result} = Automator.Client.send_command(client, \"Browser.getVersion\")

      Automator.Chromium.kill(browser)

  ## Browser Flags

  Chromium is launched with these flags:

  | Flag | Value |
  |------|-------|
  | `--headless` | `new` |
  | `--no-sandbox` | — |
  | `--disable-gpu` | — |
  | `--window-size` | `1920,1080` |
  | `--user-data-dir` | unique temp directory (cleaned up on `kill/1`) |
  | `--remote-debugging-port` | auto-detected (available TCP port) |

  Each invocation gets a fresh `--user-data-dir` so concurrent spawns don't
  contend over the default profile. Without it, Chrome for Testing silently
  exits on macOS.

  ## When to Use

  Use `Chromium` directly when you want to:

    * Connect multiple `Automator.Client` instances to the same browser
    * Manage the browser lifecycle independently of scraping sessions
    * Access the browser-level WebSocket target (not a page target)

  For most use cases, prefer `Automator.Scraper` which handles this automatically.

  """

  use TypedStruct

  typedstruct enforce: true do
    field(:chromium, port())
    field(:os_pid, non_neg_integer())
    field(:port, :inet.port_number())
    field(:ws_url, String.t())
    field(:user_data_dir, String.t() | nil, default: nil, enforce: false)
  end

  @doc """
  Spawns a headless Chromium instance on an available port.

  Launches Chromium with `--headless=new`, `--no-sandbox`, `--disable-gpu`,
  `--window-size=1920,1080`, and a unique `--user-data-dir` under the system
  temp directory. Finds an available TCP port automatically and sets
  `--remote-debugging-port` to it.

  Returns an `%Automator.Chromium{}` struct with `:chromium`, `:os_pid`,
  `:port`, `:ws_url`, and `:user_data_dir`.

  ## Example

      browser = Automator.Chromium.spawn()
      IO.puts(browser.ws_url)
      # => "ws://localhost:9222/devtools/browser/..."

  """
  def spawn do
    port = available_port()
    user_data_dir = mk_user_data_dir()
    chromium_path = System.find_executable("chromium")

    chromium =
      Port.open({:spawn_executable, chromium_path},
        args: [
          "--headless=new",
          "--no-sandbox",
          "--disable-gpu",
          "--window-size=1920,1080",
          "--user-data-dir=#{user_data_dir}",
          "--remote-debugging-port=#{port}"
        ]
      )

    {:os_pid, os_pid} = Port.info(chromium, :os_pid)

    version_url = "http://127.0.0.1:#{port}/json/version"

    {:ok, %{body: %{"webSocketDebuggerUrl" => ws_url}}} =
      Req.get(version_url, retry_log_level: false)

    %__MODULE__{
      chromium: chromium,
      os_pid: os_pid,
      port: port,
      ws_url: ws_url,
      user_data_dir: user_data_dir
    }
  end

  @doc """
  Kills the Chromium process by OS PID and removes its `--user-data-dir`.

  ## Example

      browser = Automator.Chromium.spawn()
      Automator.Chromium.kill(browser)

  """
  def kill(%__MODULE__{os_pid: os_pid, user_data_dir: user_data_dir}) do
    _ = best_effort_kill(os_pid)
    if is_binary(user_data_dir), do: File.rm_rf(user_data_dir)
    :ok
  end

  defp best_effort_kill(os_pid) do
    System.cmd("kill", ["-9", "#{os_pid}"], stderr_to_stdout: true)
    :ok
  rescue
    _ -> :ok
  end

  defp available_port do
    {:ok, port} = :gen_tcp.listen(0, [])
    {:ok, port_number} = :inet.port(port)
    Port.close(port)
    port_number
  end

  defp mk_user_data_dir do
    path = Path.join(System.tmp_dir!(), "automator-#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(path)
    path
  end
end
