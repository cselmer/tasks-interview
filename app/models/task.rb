class Task < ApplicationRecord
  belongs_to :assignee, class_name: "User", optional: true

  validates :title, presence: true

  # The new-task form has no complete field, so tasks created there store NULL.
  scope :incomplete, -> { where(complete: [false, nil]) }

  scope :due_soon_for, ->(user:) {
    incomplete
      .where(assignee: user, due_date: Date.current..(Date.current + 7.days))
      .order(:due_date)
  }

  scope :due_tomorrow, -> { incomplete.where(due_date: Date.tomorrow).where.not(assignee: nil) }
end
