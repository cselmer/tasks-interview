class TaskReminderMailer < ApplicationMailer
  def due_tomorrow
    @task = params[:task]

    mail to: @task.assignee.email, subject: "Reminder: #{@task.title} is due tomorrow"
  end
end
