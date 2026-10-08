class TaskReminderMailerPreview < ActionMailer::Preview
  def due_tomorrow
    # Falls back to an unsaved task so the preview renders on an empty database.
    task = Task.due_tomorrow.first || Task.new(
      title: "Renew passport",
      due_date: Date.tomorrow,
      assignee: User.new(name: "Ada Lovelace", email: "user1@tern.travel")
    )

    TaskReminderMailer.with(task:).due_tomorrow
  end
end
