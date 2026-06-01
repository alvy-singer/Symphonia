defmodule SymphoniaService.Secrets.Redactor do
  @moduledoc """
  Allowlist-first public and audit metadata redaction.
  """

  @tokenish ~r/(sym_pair_|sym_runner_|gh[psoru]_|xox[baprs]-|token=|access_token|secret=|api[_-]?key)/i
  @absolute_path ~r/(^|[\s(])\/(?:Users|private|tmp|var|Volumes|home|opt|usr)\/[^\s),]+/
  @tokenized_url ~r/https?:\/\/[^@\s]+@/i
  @private_runtime_marker ~r/\b(provider[_ ]output|raw[_ ]logs?|transcript|thread[_ ]id|turn[_ ]id|evidence[_ ]blob)\b[^\n\r]*/i

  def sanitize_value(value) when is_binary(value) do
    value
    |> String.slice(0, 300)
    |> redact_string()
  end

  def sanitize_value(value) when is_integer(value) or is_boolean(value), do: value

  def sanitize_value(value) when is_list(value) do
    value
    |> Enum.map(&sanitize_value/1)
    |> Enum.reject(&(&1 == :drop))
  end

  def sanitize_value(value) when is_map(value), do: :drop
  def sanitize_value(_value), do: :drop

  defp redact_string(value) do
    value
    |> String.replace(@absolute_path, "\\1[local path hidden]")
    |> String.replace(@tokenized_url, "https://[credential hidden]@")
    |> String.replace(
      ~r/\b[A-Z0-9_]*(TOKEN|SECRET|KEY|PASSWORD)=\S+/i,
      "[environment value hidden]"
    )
    |> String.replace(@tokenish, "[sensitive value hidden]")
    |> String.replace(@private_runtime_marker, "[private runtime detail hidden]")
  end
end
