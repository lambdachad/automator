defmodule Automator.ScraperTest do
  use ExUnit.Case, async: false

  test "navigate and eval" do
    {:ok, scraper} = Automator.Scraper.start_link()
    Automator.Scraper.navigate(scraper, "https://example.com")
    title = Automator.Scraper.eval(scraper, "document.title")
    assert title =~ "Example Domain"
    Automator.Scraper.stop(scraper)
  end

  test "set_cookie" do
    {:ok, scraper} = Automator.Scraper.start_link()
    result = Automator.Scraper.set_cookie(scraper, "test", "value", ".example.com")
    assert result["success"] == true
    Automator.Scraper.stop(scraper)
  end

  test "screenshot returns base64 data" do
    {:ok, scraper} = Automator.Scraper.start_link()
    Automator.Scraper.navigate(scraper, "https://example.com")
    result = Automator.Scraper.screenshot(scraper)
    assert is_binary(result["data"])
    assert String.length(result["data"]) > 0
    Automator.Scraper.stop(scraper)
  end

  test "wait_for_selector returns ok when element exists" do
    {:ok, scraper} = Automator.Scraper.start_link()
    Automator.Scraper.navigate(scraper, "https://example.com")
    assert :ok == Automator.Scraper.wait_for_selector(scraper, "h1")
    Automator.Scraper.stop(scraper)
  end

  test "click returns true when element exists" do
    {:ok, scraper} = Automator.Scraper.start_link()
    Automator.Scraper.navigate(scraper, "https://example.com")
    assert true == Automator.Scraper.click(scraper, "a")
    Automator.Scraper.stop(scraper)
  end
end

defmodule Automator.ChromiumTest do
  use ExUnit.Case, async: false

  test "spawn returns chromium port and ws_url" do
    browser = Automator.Chromium.spawn()
    on_exit(fn -> Automator.Chromium.kill(browser) end)

    assert is_port(browser.chromium)
    assert is_integer(browser.port)
    assert String.starts_with?(browser.ws_url, "ws://")
  end
end

defmodule Automator.ClientTest do
  use ExUnit.Case, async: false

  setup do
    browser = Automator.Chromium.spawn()
    {:ok, client} = Automator.Client.start_link(browser.ws_url)
    on_exit(fn -> Automator.Chromium.kill(browser) end)
    %{browser: browser, client: client}
  end

  test "send_command returns browser version", %{client: client} do
    {:ok, result} = Automator.Client.send_command(client, "Browser.getVersion")

    assert result["product"] =~ "Chrome"
    assert result["protocolVersion"]
  end

  test "send_command with params works", %{client: client} do
    {:ok, result} =
      Automator.Client.send_command(client, "Browser.setDownloadBehavior", %{
        behavior: "allow",
        downloadPath: "/tmp"
      })

    assert result == %{}
  end
end
