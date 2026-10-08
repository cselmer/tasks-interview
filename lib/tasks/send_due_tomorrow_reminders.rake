namespace :tasks do
  desc "Email each assignee a reminder for their incomplete tasks due tomorrow"
  task send_due_tomorrow_reminders: :environment do
    sent = Tasks::SendDueTomorrowReminders.call

    puts "Sent #{sent} reminder(s)."
  end
end
