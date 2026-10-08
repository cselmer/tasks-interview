require "rails_helper"

RSpec.describe Task, type: :model do
  it "has a valid factory" do
    expect(build(:task)).to be_valid
  end

  it "requires a title" do
    task = build(:task, title: nil)

    expect(task).not_to be_valid
    expect(task.errors[:title]).to include("can't be blank")
  end

  it "rejects a whitespace-only title" do
    expect(build(:task, title: "  ")).not_to be_valid
  end

  it "has a database NOT NULL constraint on title" do
    task = build(:task, title: nil)

    expect { task.save(validate: false) }.to raise_error(ActiveRecord::NotNullViolation)
  end

  it "has a database foreign key on assignee_id" do
    expect { create(:task, assignee_id: 0) }.to raise_error(ActiveRecord::InvalidForeignKey)
  end

  describe ".due_soon_for" do
    let(:user) { create(:user) }

    before { travel_to Time.zone.local(2026, 10, 8, 12) }

    it "includes a task due today" do
      task = create(:task, assignee: user, due_date: Date.new(2026, 10, 8))

      expect(Task.due_soon_for(user:)).to eq([task])
    end

    it "includes a task due exactly 7 days out" do
      task = create(:task, assignee: user, due_date: Date.new(2026, 10, 15))

      expect(Task.due_soon_for(user:)).to eq([task])
    end

    it "excludes a task due 8 days out" do
      create(:task, assignee: user, due_date: Date.new(2026, 10, 16))

      expect(Task.due_soon_for(user:)).to be_empty
    end

    it "excludes an overdue task" do
      create(:task, assignee: user, due_date: Date.new(2026, 10, 7))

      expect(Task.due_soon_for(user:)).to be_empty
    end

    it "excludes a task without a due date" do
      create(:task, assignee: user, due_date: nil)

      expect(Task.due_soon_for(user:)).to be_empty
    end

    it "excludes a complete task" do
      create(:task, assignee: user, due_date: Date.new(2026, 10, 9), complete: true)

      expect(Task.due_soon_for(user:)).to be_empty
    end

    it "includes a task whose complete flag was never set" do
      task = create(:task, assignee: user, due_date: Date.new(2026, 10, 9), complete: nil)

      expect(Task.due_soon_for(user:)).to eq([task])
    end

    it "excludes a task assigned to someone else" do
      create(:task, assignee: create(:user), due_date: Date.new(2026, 10, 9))

      expect(Task.due_soon_for(user:)).to be_empty
    end

    it "excludes an unassigned task" do
      create(:task, assignee: nil, due_date: Date.new(2026, 10, 9))

      expect(Task.due_soon_for(user:)).to be_empty
    end

    it "orders tasks by due date, soonest first" do
      in_seven_days = create(:task, assignee: user, due_date: Date.new(2026, 10, 15))
      today = create(:task, assignee: user, due_date: Date.new(2026, 10, 8))
      in_three_days = create(:task, assignee: user, due_date: Date.new(2026, 10, 11))

      expect(Task.due_soon_for(user:)).to eq([today, in_three_days, in_seven_days])
    end

    context "when the app's date is ahead of the server's" do
      around { |example| Time.use_zone("Pacific/Auckland") { example.run } }
      before { travel_to Time.utc(2026, 10, 8, 23, 30) } # already October 9 in Auckland

      it "counts a task due 7 days after the app's today" do
        task = create(:task, assignee: user, due_date: Date.new(2026, 10, 16))

        expect(Task.due_soon_for(user:)).to eq([task])
      end
    end
  end

  describe ".due_tomorrow" do
    let(:assignee) { create(:user) }

    before { travel_to Time.zone.local(2026, 10, 8, 12) }

    it "includes an incomplete, assigned task due tomorrow" do
      task = create(:task, assignee:, due_date: Date.new(2026, 10, 9))

      expect(Task.due_tomorrow).to eq([task])
    end

    it "includes a task whose complete flag was never set" do
      task = create(:task, assignee:, due_date: Date.new(2026, 10, 9), complete: nil)

      expect(Task.due_tomorrow).to eq([task])
    end

    it "excludes a task due today" do
      create(:task, assignee:, due_date: Date.new(2026, 10, 8))

      expect(Task.due_tomorrow).to be_empty
    end

    it "excludes a task due the day after tomorrow" do
      create(:task, assignee:, due_date: Date.new(2026, 10, 10))

      expect(Task.due_tomorrow).to be_empty
    end

    it "excludes a complete task" do
      create(:task, assignee:, due_date: Date.new(2026, 10, 9), complete: true)

      expect(Task.due_tomorrow).to be_empty
    end

    it "excludes an unassigned task" do
      create(:task, assignee: nil, due_date: Date.new(2026, 10, 9))

      expect(Task.due_tomorrow).to be_empty
    end

    context "when the app's date is ahead of the server's" do
      around { |example| Time.use_zone("Pacific/Auckland") { example.run } }
      before { travel_to Time.utc(2026, 10, 8, 23, 30) } # already October 9 in Auckland

      it "counts a task due the day after the app's today" do
        task = create(:task, assignee:, due_date: Date.new(2026, 10, 10))

        expect(Task.due_tomorrow).to eq([task])
      end
    end
  end
end
