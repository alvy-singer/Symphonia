defmodule SymphoniaService.GitHub.RemoteTest do
  use ExUnit.Case

  alias SymphoniaService.GitHub.Remote

  test "parses common GitHub remote URL formats" do
    assert Remote.parse("https://github.com/agora-creations/symphonia.git") == %{
             "owner" => "agora-creations",
             "name" => "symphonia",
             "url" => "https://github.com/agora-creations/symphonia",
             "remoteUrl" => "https://github.com/agora-creations/symphonia.git",
             "defaultBranch" => nil
           }

    assert Remote.parse("git@github.com:agora-creations/symphonia.git")["owner"] ==
             "agora-creations"

    assert Remote.parse("ssh://git@github.com/agora-creations/symphonia.git")["name"] ==
             "symphonia"
  end
end
