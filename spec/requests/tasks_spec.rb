require "rails_helper"

RSpec.describe "Tasks", type: :request do
  let(:user) { create(:user) }

  describe "GET /tasks" do
    it "redirects to login when signed out" do
      get tasks_path

      expect(response).to redirect_to(new_session_path)
    end

    it "lists only the current user's incomplete tasks due in the next seven days under Due Soon" do
      sign_in(user: user)
      due_later = create(:task, title: "Due in five days", assignee: user, due_date: Date.current + 5)
      due_today = create(:task, title: "Due today", assignee: user, due_date: Date.current)
      excluded = [
        create(:task, title: "Someone else's task", assignee: create(:user), due_date: Date.current + 1),
        create(:task, title: "Already complete", assignee: user, due_date: Date.current + 1, complete: true),
        create(:task, title: "Overdue task", assignee: user, due_date: Date.current - 1),
        create(:task, title: "Due next week", assignee: user, due_date: Date.current + 7),
        create(:task, title: "No date set", assignee: user, due_date: nil)
      ]

      get tasks_path

      expect(response).to have_http_status(:ok)
      due_soon_headings = css_select("#due-soon h2").map(&:text)
      expect(due_soon_headings).to eq(["Due Soon", due_today.title, due_later.title])
      expect(css_select("h2").map(&:text)).to include(*excluded.map(&:title))
    end

    it "shows an empty state when nothing is due soon" do
      sign_in(user: user)
      create(:task, assignee: user, due_date: Date.current + 10)

      get tasks_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nothing due soon.")
    end
  end

  describe "POST /tasks" do
    it "creates a task with a due date and assignee" do
      sign_in(user: user)

      post tasks_path, params: {task: {title: "Book the train", due_date: Date.current + 2, assignee_id: user.id}}

      task = Task.find_by!(title: "Book the train")
      expect(task.due_date).to eq(Date.current + 2)
      expect(task.assignee).to eq(user)
      expect(response).to redirect_to(tasks_path)
    end
  end

  describe "PATCH /tasks/:id" do
    it "updates a task's due date and assignee" do
      sign_in(user: user)
      task = create(:task)

      patch task_path(task), params: {task: {due_date: Date.current + 3, assignee_id: user.id}}

      task.reload
      expect(task.due_date).to eq(Date.current + 3)
      expect(task.assignee).to eq(user)
      expect(response).to redirect_to(tasks_path)
    end
  end
end
