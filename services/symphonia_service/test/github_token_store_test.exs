defmodule SymphoniaService.GitHub.TokenStoreTest do
  use ExUnit.Case

  alias SymphoniaService.GitHub.TokenStore

  test "stores tokens encrypted outside repository files and exposes only public connection data" do
    home =
      Path.join(System.tmp_dir!(), "symphonia-token-test-#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf(home) end)

    TokenStore.save_token_response(
      %{
        "access_token" => "ghu_secret",
        "refresh_token" => "ghr_secret",
        "token_type" => "bearer",
        "expires_in" => 28_800,
        "refresh_token_expires_in" => 15_552_000
      },
      %{"id" => 123, "login" => "alvy", "avatar_url" => "https://example.test/a.png"},
      home: home
    )

    encrypted = File.read!(Path.join(home, "github_tokens.enc"))

    refute encrypted =~ "ghu_secret"
    refute encrypted =~ "ghr_secret"

    assert {:ok, connection} = TokenStore.load(home: home)
    assert connection["token"]["access_token"] == "ghu_secret"
    assert connection["token"]["refresh_token"] == "ghr_secret"

    public = TokenStore.public_connection(home: home)
    assert public["connected"]
    assert public["user"]["login"] == "alvy"
    refute inspect(public) =~ "ghu_secret"
  end
end
