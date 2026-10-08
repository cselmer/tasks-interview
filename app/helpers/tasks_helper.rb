module TasksHelper
  def assignable_users
    User.order(:name)
  end

  def assignee_name(task:)
    task.assignee&.name || "Unassigned"
  end
end
