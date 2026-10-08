class AddNotNullToTasksTitle < ActiveRecord::Migration[8.1]
  def change
    change_column_null :tasks, :title, false
  end
end
