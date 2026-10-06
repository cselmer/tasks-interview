require "rails_helper"

RSpec.describe "Tasks", type: :request do
  let(:user) { create(:user) }

  def sign_in(user)
    post session_path, params: {session: {email: user.email, password: "abcde12345"}}
  end

  describe "GET /tasks" do
    it "renders a checked box for complete tasks and an unchecked box for incomplete tasks" do
      complete_task = create(:task, complete: true)
      incomplete_task = create(:task, complete: false)
      sign_in(user)

      get tasks_path

      expect(response).to have_http_status(:ok)
      assert_select "input[type=checkbox][name='task[complete]'][id=?][checked]", "complete_task_#{complete_task.id}"
      assert_select "input[type=checkbox][name='task[complete]'][id=?]:not([checked])", "complete_task_#{incomplete_task.id}"
    end

    it "keeps tasks in creation order after one is toggled" do
      first_task = create(:task, title: "First task")
      second_task = create(:task, title: "Second task")
      first_task.update!(complete: true)
      sign_in(user)

      get tasks_path

      expect(response.body.index(first_task.title)).to be < response.body.index(second_task.title)
    end
  end

  describe "PATCH /tasks/:id" do
    it "marks an incomplete task complete" do
      task = create(:task, complete: false)
      sign_in(user)

      patch task_path(task), params: {task: {complete: "1"}}

      expect(response).to redirect_to(tasks_path)
      expect(task.reload.complete).to be(true)
    end

    it "marks a complete task incomplete" do
      task = create(:task, complete: true)
      sign_in(user)

      patch task_path(task), params: {task: {complete: "0"}}

      expect(response).to redirect_to(tasks_path)
      expect(task.reload.complete).to be(false)
    end

    it "redirects to login and leaves the task unchanged when signed out" do
      task = create(:task, complete: false)

      patch task_path(task), params: {task: {complete: "1"}}

      expect(response).to redirect_to(new_session_path)
      expect(task.reload.complete).to be(false)
    end
  end
end
