require "rails_helper"

RSpec.describe Task, type: :model do
  it "has a valid factory" do
    expect(build(:task)).to be_valid
  end

  it "is valid without an assignee or a due date" do
    expect(build(:task, assignee: nil, due_date: nil)).to be_valid
  end

  describe ".due_soon_for" do
    let(:user) { create(:user) }

    around do |example|
      travel_to(Time.zone.local(2026, 3, 10, 12)) { example.run }
    end

    it "includes tasks due today through six days from now" do
      due_today = create(:task, assignee: user, due_date: Date.current)
      due_in_six_days = create(:task, assignee: user, due_date: Date.current + 6)

      expect(Task.due_soon_for(user: user)).to contain_exactly(due_today, due_in_six_days)
    end

    it "excludes overdue tasks" do
      create(:task, assignee: user, due_date: Date.current - 1)

      expect(Task.due_soon_for(user: user)).to be_empty
    end

    it "excludes tasks due seven or more days from now" do
      create(:task, assignee: user, due_date: Date.current + 7)

      expect(Task.due_soon_for(user: user)).to be_empty
    end

    it "excludes tasks without a due date" do
      create(:task, assignee: user, due_date: nil)

      expect(Task.due_soon_for(user: user)).to be_empty
    end

    it "excludes completed tasks" do
      create(:task, assignee: user, due_date: Date.current + 1, complete: true)

      expect(Task.due_soon_for(user: user)).to be_empty
    end

    it "treats a nil completion flag as incomplete" do
      task = create(:task, assignee: user, due_date: Date.current + 1, complete: nil)

      expect(Task.due_soon_for(user: user)).to contain_exactly(task)
    end

    it "excludes tasks assigned to someone else or to no one" do
      create(:task, assignee: create(:user), due_date: Date.current + 1)
      create(:task, assignee: nil, due_date: Date.current + 1)

      expect(Task.due_soon_for(user: user)).to be_empty
    end

    it "orders tasks by due date" do
      later = create(:task, assignee: user, due_date: Date.current + 5)
      sooner = create(:task, assignee: user, due_date: Date.current + 2)

      expect(Task.due_soon_for(user: user)).to eq([sooner, later])
    end
  end
end
