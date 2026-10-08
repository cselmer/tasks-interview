require "rails_helper"

RSpec.describe "Tasks", type: :request do
  describe "GET /tasks" do
    it "redirects to login when signed out" do
      get tasks_path

      expect(response).to redirect_to(new_session_path)
    end

    it "lists tasks when signed in" do
      user = create(:user)
      tasks = create_list(:task, 2)
      sign_in(user:)

      get tasks_path

      expect(response).to have_http_status(:ok)
      tasks.each do |task|
        expect(response.body).to include(task.title)
      end
    end

    it "displays the seeded tasks" do
      Rails.application.load_seed
      sign_in(user: create(:user))

      get tasks_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Book flights to Lisbon", "Renew passport")
    end

    it "lists the oldest tasks first" do
      create(:task, title: "Newer task", created_at: 1.hour.ago)
      create(:task, title: "Older task", created_at: 1.day.ago)
      sign_in(user: create(:user))

      get tasks_path

      expect(response).to have_http_status(:ok)
      expect(response.body.index("Older task")).to be < response.body.index("Newer task")
    end

    it "renders the new task form" do
      sign_in(user: create(:user))

      get tasks_path

      expect(response).to have_http_status(:ok)
      assert_select "form[action=?][method=post]", tasks_path do
        assert_select "input[name=?]", "task[title]"
        assert_select "textarea[name=?]", "task[description]"
        assert_select "input[type=submit]"
      end
    end

    it "offers to mark an incomplete task complete" do
      task = create(:task, complete: false)
      sign_in(user: create(:user))

      get tasks_path

      assert_select "form[action=?]", task_path(task) do
        assert_select "button", text: "Mark complete"
        assert_select "input[name=?][value=?]", "task[complete]", "true"
        assert_select "input[name=?][value=?]", "_method", "patch"
      end
      assert_select "h2.line-through", count: 0
    end

    it "offers to mark a complete task incomplete and strikes through its title" do
      task = create(:task, complete: true)
      sign_in(user: create(:user))

      get tasks_path

      assert_select "form[action=?]", task_path(task) do
        assert_select "button", text: "Mark incomplete"
        assert_select "input[name=?][value=?]", "task[complete]", "false"
        assert_select "input[name=?][value=?]", "_method", "patch"
      end
      assert_select "h2.line-through", text: task.title
    end
  end

  describe "POST /tasks" do
    before { sign_in(user: create(:user)) }

    it "creates the task and shows it on the index" do
      attributes = attributes_for(:task)

      expect {
        post tasks_path, params: {task: attributes}
      }.to change(Task, :count).by(1)

      expect(response).to redirect_to(tasks_path)
      follow_redirect!
      expect(response.body).to include(attributes[:title])
    end

    it "re-renders the index with the error and the submitted values when the title is blank" do
      existing_task = create(:task)

      expect {
        post tasks_path, params: {task: {title: "", description: "Pack sunscreen"}}
      }.not_to change(Task, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(ERB::Util.html_escape("Title can't be blank"))
      expect(response.body).to include("Pack sunscreen")
      expect(response.body).to include(existing_task.title)
    end
  end

  describe "PATCH /tasks/:id" do
    before { sign_in(user: create(:user)) }

    it "updates the task" do
      task = create(:task)

      patch task_path(task), params: {task: {title: "Renewed passport"}}

      expect(response).to redirect_to(tasks_path)
      expect(task.reload.title).to eq("Renewed passport")
    end

    it "re-renders the edit form with the error when the title is blank" do
      task = create(:task)

      patch task_path(task), params: {task: {title: ""}}

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(ERB::Util.html_escape("Title can't be blank"))
      expect(task.reload.title).not_to be_blank
    end

    it "marks a task complete and then incomplete again" do
      task = create(:task, complete: false)

      patch task_path(task), params: {task: {complete: true}}

      expect(response).to redirect_to(tasks_path)
      expect(task.reload).to be_complete

      patch task_path(task), params: {task: {complete: false}}

      expect(response).to redirect_to(tasks_path)
      expect(task.reload).not_to be_complete
    end
  end

  describe "DELETE /tasks/:id" do
    before { sign_in(user: create(:user)) }

    it "deletes the task" do
      task = create(:task)

      expect {
        delete task_path(task)
      }.to change(Task, :count).by(-1)

      expect(response).to redirect_to(tasks_path)
    end

    it "shows an alert on the index when the task cannot be deleted" do
      task = create(:task)
      allow(Task).to receive(:find).with(task.id.to_s).and_return(task)
      allow(task).to receive(:destroy).and_return(false)

      delete task_path(task)

      expect(response).to redirect_to(tasks_path)
      follow_redirect!
      expect(response.body).to include("Could not delete task.")
    end
  end
end
