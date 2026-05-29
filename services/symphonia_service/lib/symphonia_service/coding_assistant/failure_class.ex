defmodule SymphoniaService.CodingAssistant.FailureClass do
  @moduledoc """
  Normalized public-safe failure classes for coding assistant providers.
  """

  alias SymphoniaService.CodingAssistant.AppServerClient

  @classes ~w(
    setup_blocked
    transient_provider
    transient_workspace
    validation_failed
    no_reviewable_files
    user_blocked
    unknown
  )

  @retryable ~w(transient_provider transient_workspace)

  def all, do: @classes
  def retryable, do: @retryable

  def normalize(class) when class in @classes, do: class
  def normalize(_class), do: "unknown"

  def retryable?(class), do: normalize(class) in @retryable

  def classify(reason, context \\ %{}) do
    public_message = public_message(context)

    text =
      [reason, public_message]
      |> Enum.filter(&is_binary/1)
      |> Enum.join(" ")
      |> String.downcase()

    cond do
      Enum.any?([reason, public_message], &AppServerClient.setup_blocker?/1) ->
        "setup_blocked"

      text =~ "can't start" and (text =~ "disabled" or text =~ "not supported") ->
        "setup_blocked"

      text =~ "validation" and text =~ "failed" ->
        "validation_failed"

      text =~ "no reviewable" or text =~ "did not produce any files" or
          text =~ "no committable" ->
        "no_reviewable_files"

      text =~ "waiting for user" or text =~ "needs input" or text =~ "canceled" ->
        "user_blocked"

      text =~ "workspace" and
          (text =~ "temporar" or text =~ "lock" or text =~ "unavailable" or
             text =~ "missing") ->
        "transient_workspace"

      text =~ "branch" and (text =~ "lock" or text =~ "unavailable" or text =~ "missing") ->
        "transient_workspace"

      text =~ "codex app server did not respond" or text =~ "timed out" or
        text =~ "timeout" or text =~ "econn" or text =~ "connection refused" or
        text =~ "status interrupted" or text =~ "transient" or text =~ "temporar" or
          text =~ "unavailable" ->
        "transient_provider"

      true ->
        "unknown"
    end
  end

  defp public_message(%{"public_message" => message}), do: message
  defp public_message(%{public_message: message}), do: message
  defp public_message(%{"message" => message}), do: message
  defp public_message(%{message: message}), do: message
  defp public_message(_context), do: nil
end
