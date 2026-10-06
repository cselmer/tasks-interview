class AddDueDateAndAssigneeToTasks < ActiveRecord::Migration[8.1]
  def change
    add_column :tasks, :due_date, :date
    add_reference :tasks, :assignee, foreign_key: {to_table: :users}
  end
end
