class Tasks::SendDueTomorrowReminders
  def self.call
    new.call
  end

  def call
    tasks = Task.due_tomorrow.includes(:assignee)

    tasks.each do |task|
      TaskReminderMailer.with(task:).due_tomorrow.deliver_now
    end

    tasks.size
  end
end
