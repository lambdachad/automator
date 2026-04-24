defmodule CDP.Scraper do
  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, [])
  end

  def init([]) do
    browser = CDP.Chromium.spawn()
    {:ok, %{body: targets}} = Req.get("http://localhost:#{browser.port}/json")

    page_ws_url =
      targets |> Enum.find(fn t -> t["type"] == "page" end) |> Map.fetch!("webSocketDebuggerUrl")

    {:ok, client} = CDP.Client.start_link(page_ws_url)
    {:ok, %{browser: browser, client: client}}
  end

  def stop(pid) do
    GenServer.call(pid, :stop)
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

  def handle_call({:set_cookie, name, value, domain}, _from, %{client: client} = state) do
    {:ok, result} =
      CDP.Client.send_command(client, "Network.setCookie", %{
        name: name,
        value: value,
        domain: domain
      })

    {:reply, result, state}
  end

  def handle_call({:screenshot}, _from, %{client: client} = state) do
    {:ok, result} = CDP.Client.send_command(client, "Page.captureScreenshot")
    {:reply, result, state}
  end

  def handle_call(:stop, _from, %{browser: browser} = state) do
    CDP.Chromium.kill(browser)
    {:stop, :normal, :ok, state}
  end

  def navigate(pid, url) do
    GenServer.call(pid, {:navigate, url})
  end

  def eval(pid, js) do
    GenServer.call(pid, {:eval, js})
  end

  def set_cookie(pid, name, value, domain) do
    GenServer.call(pid, {:set_cookie, name, value, domain})
  end

  def screenshot(pid) do
    GenServer.call(pid, {:screenshot})
  end
end
