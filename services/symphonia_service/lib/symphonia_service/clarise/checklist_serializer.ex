defmodule SymphoniaService.Clarise.ChecklistSerializer do
  @moduledoc """
  Serializes Clarise-requested changes into the only text the Coding Assistant receives.
  """

  def serialize(items) when is_list(items) do
    lines =
      items
      |> Enum.map(&to_string/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&strip_checkbox/1)

    "Requested changes:\n" <> Enum.map_join(lines, "\n", &"- #{&1}")
  end

  defp strip_checkbox(item) do
    item
    |> String.replace(~r/^- \[[ xX]\]\s*/, "")
    |> String.trim()
  end
end
