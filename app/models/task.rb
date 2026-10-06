class Task < ApplicationRecord
  belongs_to :assignee, class_name: "User", optional: true

  scope :due_soon_for, ->(user:) {
    where(assignee: user, complete: [false, nil], due_date: Date.current..(Date.current + 6.days))
      .order(:due_date)
  }
end
