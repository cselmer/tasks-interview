require "rails_helper"

RSpec.describe TaskReminderMailer, type: :mailer do
  describe "#due_tomorrow" do
    let(:assignee) { create(:user, name: "Ada Lovelace", email: "ada@example.com") }
    let(:task) { create(:task, title: "Renew Ada's passport", assignee:, due_date: Date.new(2026, 10, 9)) }
    let(:mail) { TaskReminderMailer.with(task:).due_tomorrow }

    it "is addressed to the assignee" do
      expect(mail.to).to eq(["ada@example.com"])
    end

    it "names the task in the subject" do
      expect(mail.subject).to eq("Reminder: Renew Ada's passport is due tomorrow")
    end

    it "mentions the task's title and due date in the body" do
      expect(mail.body.to_s).to include("Renew Ada's passport", "October 9th, 2026")
    end
  end
end
