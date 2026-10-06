module TasksHelper
  def due_date_label(task:)
    task.due_date ? l(task.due_date, format: :short) : "No due date"
  end

  def assignable_users
    User.order(:name)
  end
end
