defmodule SymphoniaService.ClariseTest do
  use ExUnit.Case, async: true

  alias SymphoniaService.Clarise.{ChecklistSerializer, FeedbackStructurer, ReviewNotesBuilder}

  test "structures natural feedback into deterministic requested changes" do
    feedback =
      "The card is still too dense. Remove validation from the default card, make the project label smaller, and show retry only when paused."

    assert FeedbackStructurer.structure(feedback) == [
             "Make task cards less dense.",
             "Remove validation from the default card.",
             "Make the project label visually smaller.",
             "Show the retry action only when the task is paused."
           ]
  end

  test "serializes only checklist items for Coding Assistant input" do
    assert ChecklistSerializer.serialize(["Make task cards less dense.", "Remove validation."]) ==
             "Requested changes:\n- Make task cards less dense.\n- Remove validation."
  end

  test "review note preserves original feedback and checklist" do
    note =
      ReviewNotesBuilder.build(
        "Keep the nuance visible.",
        ["Keep the nuance visible."],
        "2026-05-25T10:32:00Z"
      )

    assert note["id"] =~ "review_note_2026_05_25T10_32_00Z_"
    assert note["original_feedback"] == "Keep the nuance visible."
    assert note["requested_changes"] == ["Keep the nuance visible."]
  end
end
