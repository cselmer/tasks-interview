require "rails_helper"

RSpec.describe Task, type: :model do
  it "has a valid factory" do
    expect(build(:task)).to be_valid
  end

  describe "assignee" do
    it "must be an existing user" do
      expect { create(:task, assignee_id: 0) }.to raise_error(ActiveRecord::InvalidForeignKey)
    end
  end
end
