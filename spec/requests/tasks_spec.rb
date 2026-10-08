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
  end

  describe "POST /tasks assignment" do
    it "assigns the new task to the chosen user" do
      assignee = create(:user)
      sign_in(user: create(:user))

      post tasks_path, params: {task: {title: "Book flights", assignee_id: assignee.id}}

      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(tasks_path)
      expect(Task.find_by!(title: "Book flights").assignee).to eq(assignee)
    end

    it "creates an unassigned task when the blank option is chosen" do
      sign_in(user: create(:user))

      post tasks_path, params: {task: {title: "Book flights", assignee_id: ""}}

      expect(response).to have_http_status(:found)
      expect(Task.find_by!(title: "Book flights").assignee).to be_nil
    end
  end

  describe "PATCH /tasks/:id assignment" do
    it "assigns an unassigned task to the chosen user" do
      assignee = create(:user)
      task = create(:task)
      sign_in(user: create(:user))

      patch task_path(task), params: {task: {assignee_id: assignee.id}}

      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(tasks_path)
      expect(task.reload.assignee).to eq(assignee)
    end

    it "reassigns a task to a different user" do
      new_assignee = create(:user)
      task = create(:task, assignee: create(:user))
      sign_in(user: create(:user))

      patch task_path(task), params: {task: {assignee_id: new_assignee.id}}

      expect(response).to have_http_status(:found)
      expect(task.reload.assignee).to eq(new_assignee)
    end

    it "unassigns the task when the blank option is chosen" do
      task = create(:task, assignee: create(:user))
      sign_in(user: create(:user))

      patch task_path(task), params: {task: {assignee_id: ""}}

      expect(response).to have_http_status(:found)
      expect(task.reload.assignee).to be_nil
    end

    it "keeps the current assignee when only other fields change" do
      assignee = create(:user)
      task = create(:task, assignee:)
      sign_in(user: create(:user))

      patch task_path(task), params: {task: {description: "Updated"}}

      expect(response).to have_http_status(:found)
      expect(task.reload.assignee).to eq(assignee)
    end
  end

  describe "GET /tasks assignees" do
    # The new-task form on the same page lists every user's name and an
    # "Unassigned" option, so assertions are scoped to the task's own row.
    def row_for(task:)
      response.parsed_body.css("h2").find { |heading| heading.text == task.title }.parent
    end

    it "shows the assignee's name on the task's row" do
      assignee = create(:user, name: "Ada Lovelace")
      task = create(:task, assignee:)
      sign_in(user: create(:user))

      get tasks_path

      expect(response).to have_http_status(:ok)
      expect(row_for(task:).text).to include("Ada Lovelace")
      expect(row_for(task:).text).not_to include("Unassigned")
    end

    it "shows Unassigned on the row of a task without an assignee" do
      task = create(:task)
      sign_in(user: create(:user, name: "Grace Hopper"))

      get tasks_path

      expect(response).to have_http_status(:ok)
      expect(row_for(task:).text).to include("Unassigned")
      expect(row_for(task:).text).not_to include("Grace Hopper")
    end

    it "does not query users once per task" do
      sign_in(user: create(:user))
      2.times { create(:task, assignee: create(:user)) }

      queries_with_two_tasks = users_queries_during { get tasks_path }
      expect(response).to have_http_status(:ok)

      4.times { create(:task, assignee: create(:user)) }

      queries_with_six_tasks = users_queries_during { get tasks_path }
      expect(response).to have_http_status(:ok)

      expect(queries_with_two_tasks).to be_positive
      expect(queries_with_six_tasks).to eq(queries_with_two_tasks)
    end

    def users_queries_during(&block)
      queries = []
      subscriber = lambda do |*, payload|
        queries << payload[:sql] if payload[:name] != "SCHEMA" && payload[:sql].include?('FROM "users"')
      end

      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record", &block)
      queries.size
    end
  end

  describe "assignee select" do
    it "offers Unassigned and every user, ordered by name" do
      create(:user, name: "Zed Zebra")
      create(:user, name: "Ada Lovelace")
      sign_in(user: create(:user, name: "Grace Hopper"))

      get tasks_path

      expect(response).to have_http_status(:ok)
      options = response.parsed_body.css("select#task_assignee_id option")
      expect(options.map(&:text)).to eq(["Unassigned", "Ada Lovelace", "Grace Hopper", "Zed Zebra"])
    end

    it "preselects the current assignee when editing" do
      assignee = create(:user, name: "Ada Lovelace")
      create(:user, name: "Grace Hopper")
      task = create(:task, assignee:)
      sign_in(user: create(:user))

      get edit_task_path(task)

      expect(response).to have_http_status(:ok)
      selected = response.parsed_body.css("select#task_assignee_id option[selected]")
      expect(selected.map(&:text)).to eq(["Ada Lovelace"])
    end
  end
end
