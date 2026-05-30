defmodule SymphoniaService.Runners.Heartbeat do
  @moduledoc """
  Runner heartbeat status derivation.
  """

  @stale_after_seconds 90
  @offline_after_seconds 300

  def stale_after_seconds, do: @stale_after_seconds
  def offline_after_seconds, do: @offline_after_seconds

  def status(runner, now \\ DateTime.utc_now())

  def status(%{"enabled" => false}, _now), do: "disabled"

  def status(runner, now) when is_map(runner) do
    case heartbeat_age_seconds(runner["lastHeartbeatAt"] || runner["last_heartbeat_at"], now) do
      {:ok, age} when age <= @stale_after_seconds -> "online"
      {:ok, age} when age <= @offline_after_seconds -> "stale"
      {:ok, _age} -> "offline"
      :error -> "offline"
    end
  end

  def status(_runner, _now), do: "offline"

  def transition?(before_status, after_status) do
    before_status != after_status and after_status in ["stale", "offline", "disabled", "online"]
  end

  defp heartbeat_age_seconds(nil, _now), do: :error

  defp heartbeat_age_seconds(value, now) when is_binary(value) do
    with {:ok, heartbeat, _offset} <- DateTime.from_iso8601(value) do
      {:ok, max(DateTime.diff(now, heartbeat, :second), 0)}
    else
      _ -> :error
    end
  end

  defp heartbeat_age_seconds(_value, _now), do: :error
end
