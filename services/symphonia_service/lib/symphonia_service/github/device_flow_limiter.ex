defmodule SymphoniaService.GitHub.DeviceFlowLimiter do
  @moduledoc """
  In-process guard for GitHub device-flow polling intervals.
  """

  @table :symphonia_github_device_flows

  def record(device_code, interval) do
    ensure_table()
    now = monotonic_seconds()
    interval = normalize_interval(interval)
    :ets.insert(@table, {device_code, interval, now + interval})
    :ok
  end

  def allow_poll(device_code, interval) do
    ensure_table()
    now = monotonic_seconds()

    case :ets.lookup(@table, device_code) do
      [{^device_code, _stored_interval, next_at}] when now < next_at ->
        {:error, next_at - now}

      [{^device_code, stored_interval, _next_at}] ->
        next_interval = max(stored_interval, normalize_interval(interval))
        :ets.insert(@table, {device_code, next_interval, now + next_interval})
        :ok

      [] ->
        record(device_code, interval)
        {:error, normalize_interval(interval)}
    end
  end

  def slow_down(device_code) do
    ensure_table()
    now = monotonic_seconds()

    case :ets.lookup(@table, device_code) do
      [{^device_code, interval, _next_at}] ->
        interval = interval + 5
        :ets.insert(@table, {device_code, interval, now + interval})
        interval

      [] ->
        interval = 10
        :ets.insert(@table, {device_code, interval, now + interval})
        interval
    end
  end

  def clear(device_code) do
    ensure_table()
    :ets.delete(@table, device_code)
    :ok
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:named_table, :public, read_concurrency: true])
      _ -> :ok
    end
  rescue
    ArgumentError -> :ok
  end

  defp normalize_interval(value) when is_integer(value) and value > 0, do: value

  defp normalize_interval(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> integer
      _ -> 5
    end
  end

  defp normalize_interval(_value), do: 5
  defp monotonic_seconds, do: System.monotonic_time(:second)
end
