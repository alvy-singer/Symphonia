defmodule SymphoniaService.Validation.Evidence do
  @moduledoc """
  Converts private validation results into review-safe public evidence.
  """

  alias SymphoniaService.Secrets.Redactor

  @not_configured_detail "No machine validation command was configured."

  def not_configured_result do
    %{
      "id" => "validation_not_configured",
      "label" => "Machine validation",
      "command" => nil,
      "required" => false,
      "source" => "not_configured",
      "status" => "not_configured",
      "exit_status" => nil,
      "duration_ms" => 0,
      "output" => "",
      "output_truncated" => false,
      "public_detail" => @not_configured_detail
    }
  end

  def public(results) do
    results
    |> List.wrap()
    |> Enum.filter(&is_map/1)
    |> Enum.map(&public_one/1)
    |> Enum.reject(&blank?(&1["label"]))
  end

  def markdown_list(results) do
    results
    |> public()
    |> case do
      [] ->
        "- No validation evidence recorded."

      evidence ->
        Enum.map_join(evidence, "\n", fn item ->
          "- #{item["label"]}: #{status_label(item["status"])} - #{item["detail"]}"
        end)
    end
  end

  def has_failed_required?(results) do
    results
    |> List.wrap()
    |> Enum.any?(fn result ->
      result["required"] == true and result["status"] in ["failed", "timed_out"]
    end)
  end

  def sanitize_public_text(value) do
    case Redactor.sanitize_value(to_string(value)) do
      :drop -> ""
      text -> text |> String.trim() |> String.slice(0, 300)
    end
  end

  defp public_one(result) do
    status = public_status(result["status"])

    %{
      "label" => sanitize_public_text(result["label"]),
      "status" => status,
      "detail" =>
        sanitize_public_text(
          result["public_detail"] || result["detail"] || detail_for(result, status)
        )
    }
  end

  defp public_status("passed"), do: "passed"
  defp public_status("failed"), do: "failed"
  defp public_status("timed_out"), do: "failed"
  defp public_status("skipped"), do: "not_run"
  defp public_status("not_configured"), do: "not_run"
  defp public_status("not_run"), do: "not_run"
  defp public_status(_status), do: "not_run"

  defp detail_for(%{"status" => "passed", "label" => label}, _status), do: "#{label} passed."

  defp detail_for(%{"status" => "failed", "label" => label}, _status),
    do: "#{label} failed. Review the private run output locally."

  defp detail_for(%{"status" => "timed_out", "label" => label}, _status),
    do: "#{label} timed out. Review the private run output locally."

  defp detail_for(%{"status" => "not_configured"}, _status), do: @not_configured_detail
  defp detail_for(%{"label" => label}, _status), do: "#{label} was not run."
  defp detail_for(_result, _status), do: @not_configured_detail

  defp status_label("passed"), do: "Passed"
  defp status_label("failed"), do: "Failed"
  defp status_label(_status), do: "Not run"

  defp blank?(value), do: is_nil(value) or (is_binary(value) and String.trim(value) == "")
end
