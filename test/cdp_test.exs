defmodule CDP.ScraperTest do
  use ExUnit.Case, async: false

  test "navigate and eval" do
    {:ok, scraper} = CDP.Scraper.start_link()
    CDP.Scraper.navigate(scraper, "https://example.com")
    title = CDP.Scraper.eval(scraper, "document.title")
    assert title =~ "Example Domain"
    CDP.Scraper.stop(scraper)
  end

  test "set_cookie" do
    {:ok, scraper} = CDP.Scraper.start_link()
    result = CDP.Scraper.set_cookie(scraper, "test", "value", ".example.com")
    assert result["success"] == true
    CDP.Scraper.stop(scraper)
  end

  test "screenshot returns base64 data" do
    {:ok, scraper} = CDP.Scraper.start_link()
    CDP.Scraper.navigate(scraper, "https://example.com")
    result = CDP.Scraper.screenshot(scraper)
    assert is_binary(result["data"])
    assert String.length(result["data"]) > 0
    CDP.Scraper.stop(scraper)
  end
end

defmodule CDP.ChromiumTest do
  use ExUnit.Case, async: false

  test "spawn returns chromium port and ws_url" do
    browser = CDP.Chromium.spawn()
    on_exit(fn -> CDP.Chromium.kill(browser) end)

    assert is_port(browser.chromium)
    assert is_integer(browser.port)
    assert String.starts_with?(browser.ws_url, "ws://")
  end
end

defmodule CDP.ClientTest do
  use ExUnit.Case, async: false

  setup do
    browser = CDP.Chromium.spawn()
    {:ok, client} = CDP.Client.start_link(browser.ws_url)
    on_exit(fn -> CDP.Chromium.kill(browser) end)
    %{browser: browser, client: client}
  end

  test "send_command returns browser version", %{client: client} do
    {:ok, result} = CDP.Client.send_command(client, "Browser.getVersion")

    assert result["product"] =~ "Chrome"
    assert result["protocolVersion"]
  end

  test "send_command with params works", %{client: client} do
    {:ok, result} =
      CDP.Client.send_command(client, "Browser.setDownloadBehavior", %{
        behavior: "allow",
        downloadPath: "/tmp"
      })

    assert result == %{}
  end
end
