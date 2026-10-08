module TasksHelper
  def assignable_users
    User.order(:name)
  end

  def assignee_name(task:)
    task.assignee&.name || "Unassigned"
  end

  def due_date_label(task:)
    task.due_date ? "Due #{task.due_date.to_fs(:long_ordinal)}" : "No due date"
  end
end
