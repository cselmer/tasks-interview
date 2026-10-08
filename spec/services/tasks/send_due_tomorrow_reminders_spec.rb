require "rails_helper"

RSpec.describe Tasks::SendDueTomorrowReminders do
  before do
    travel_to Time.zone.local(2026, 10, 8, 12)
    ActionMailer::Base.deliveries.clear
  end

  it "emails the assignee of each incomplete task due tomorrow and returns the count" do
    ada = create(:user, email: "ada@example.com")
    grace = create(:user, email: "grace@example.com")
    create(:task, title: "Renew passport", assignee: ada, due_date: Date.new(2026, 10, 9))
    create(:task, title: "Book hotel", assignee: grace, due_date: Date.new(2026, 10, 9))

    sent = described_class.call

    expect(sent).to eq(2)
    expect(ActionMailer::Base.deliveries.map { |mail| [mail.to, mail.subject] }).to contain_exactly(
      [["ada@example.com"], "Reminder: Renew passport is due tomorrow"],
      [["grace@example.com"], "Reminder: Book hotel is due tomorrow"]
    )
  end

  it "skips overdue, due-today, complete, and unassigned tasks" do
    due_tomorrow_assignee = create(:user, email: "due-tomorrow@example.com")
    create(:task, assignee: due_tomorrow_assignee, due_date: Date.new(2026, 10, 9))
    create(:task, assignee: create(:user, email: "overdue@example.com"), due_date: Date.new(2026, 10, 7))
    create(:task, assignee: create(:user, email: "due-today@example.com"), due_date: Date.new(2026, 10, 8))
    create(:task, assignee: create(:user, email: "complete@example.com"), due_date: Date.new(2026, 10, 9), complete: true)
    create(:task, assignee: nil, due_date: Date.new(2026, 10, 9))

    sent = described_class.call

    expect(sent).to eq(1)
    expect(ActionMailer::Base.deliveries.map(&:to)).to eq([["due-tomorrow@example.com"]])
  end

  it "sends nothing and returns zero when no task is due tomorrow" do
    create(:task, assignee: create(:user), due_date: Date.new(2026, 10, 10))

    expect(described_class.call).to eq(0)
    expect(ActionMailer::Base.deliveries).to be_empty
  end
end
