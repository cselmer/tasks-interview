require "rails_helper"

RSpec.describe "Tasks", type: :request do
  def users_queries_during(&block)
    queries = []
    subscriber = lambda do |*, payload|
      queries << payload[:sql] if payload[:name] != "SCHEMA" && payload[:sql].include?('FROM "users"')
    end

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record", &block)
    queries.size
  end

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

      expect(response).to have_http_status(:ok)
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

      expect(response).to have_http_status(:ok)
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
      expect(response).to have_http_status(:ok)
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
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Could not delete task.")
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

  describe "due dates" do
    let(:user) { create(:user) }

    before do
      travel_to Time.zone.local(2026, 10, 8, 12)
      sign_in(user:)
    end

    # A due-soon task's title appears in both sections, so assertions are
    # scoped to one section's rows rather than the whole page.
    def section(id:)
      response.parsed_body.at_css("section##{id}")
    end

    def row_titles(section_id:)
      section(id: section_id).css("> div h2").map(&:text)
    end

    it "renders a labelled due date field" do
      get tasks_path

      expect(response).to have_http_status(:ok)
      assert_select "label[for=?]", "task_due_date", text: "Due date"
      assert_select "input[type=date][name=?]", "task[due_date]"
    end

    it "saves the due date on create" do
      post tasks_path, params: {task: {title: "Renew passport", due_date: "2026-10-20"}}

      expect(response).to have_http_status(:found)
      expect(Task.find_by!(title: "Renew passport").due_date).to eq(Date.new(2026, 10, 20))
    end

    it "keeps the submitted due date when create fails" do
      post tasks_path, params: {task: {title: "", due_date: "2026-10-20"}}

      expect(response).to have_http_status(:unprocessable_content)
      assert_select "input[name=?][value=?]", "task[due_date]", "2026-10-20"
    end

    it "saves the due date on update" do
      task = create(:task)

      patch task_path(task), params: {task: {due_date: "2026-10-20"}}

      expect(response).to have_http_status(:found)
      expect(task.reload.due_date).to eq(Date.new(2026, 10, 20))
    end

    it "clears the due date on update when the field is emptied" do
      task = create(:task, due_date: Date.new(2026, 10, 20))

      patch task_path(task), params: {task: {due_date: ""}}

      expect(response).to have_http_status(:found)
      expect(task.reload.due_date).to be_nil
    end

    it "shows the due date on the task's row" do
      create(:task, due_date: Date.new(2026, 10, 20))

      get tasks_path

      expect(response).to have_http_status(:ok)
      expect(section(id: "all_tasks").text).to include("Due October 20th, 2026")
      expect(section(id: "all_tasks").text).not_to include("No due date")
    end

    it "shows No due date on the row of a task without one" do
      create(:task, due_date: nil)

      get tasks_path

      expect(response).to have_http_status(:ok)
      expect(section(id: "all_tasks").text).to include("No due date")
    end

    it "does not query users once per due-soon task" do
      2.times { create(:task, assignee: user, due_date: Date.new(2026, 10, 9)) }

      queries_with_two_tasks = users_queries_during { get tasks_path }
      expect(response).to have_http_status(:ok)

      4.times { create(:task, assignee: user, due_date: Date.new(2026, 10, 9)) }

      queries_with_six_tasks = users_queries_during { get tasks_path }
      expect(response).to have_http_status(:ok)

      expect(queries_with_two_tasks).to be_positive
      expect(queries_with_six_tasks).to eq(queries_with_two_tasks)
    end

    describe "Due Soon section" do
      it "lists only the signed-in user's tasks due in the next 7 days" do
        create(:task, title: "Mine, due in 2 days", assignee: user, due_date: Date.new(2026, 10, 10))
        create(:task, title: "Someone else's, due in 2 days", assignee: create(:user), due_date: Date.new(2026, 10, 10))
        create(:task, title: "Mine, due in 8 days", assignee: user, due_date: Date.new(2026, 10, 16))

        get tasks_path

        expect(response).to have_http_status(:ok)
        expect(row_titles(section_id: "due_soon")).to eq(["Mine, due in 2 days"])
        expect(section(id: "due_soon").text).not_to include("Nothing due in the next 7 days.")
      end

      it "leaves every task in the All tasks list" do
        titles = [
          create(:task, title: "Mine, due in 2 days", assignee: user, due_date: Date.new(2026, 10, 10)),
          create(:task, title: "Someone else's, due in 2 days", assignee: create(:user), due_date: Date.new(2026, 10, 10)),
          create(:task, title: "Mine, due in 8 days", assignee: user, due_date: Date.new(2026, 10, 16)),
          create(:task, title: "Unscheduled", due_date: nil)
        ].map(&:title)

        get tasks_path

        expect(response).to have_http_status(:ok)
        expect(row_titles(section_id: "all_tasks")).to match_array(titles)
      end

      it "shows an empty state when nothing is due in the next 7 days" do
        create(:task, title: "Mine, due in 8 days", assignee: user, due_date: Date.new(2026, 10, 16))

        get tasks_path

        expect(response).to have_http_status(:ok)
        expect(row_titles(section_id: "due_soon")).to be_empty
        expect(section(id: "due_soon").text).to include("Nothing due in the next 7 days.")
      end

      it "is still rendered when create fails" do
        create(:task, title: "Mine, due tomorrow", assignee: user, due_date: Date.new(2026, 10, 9))

        post tasks_path, params: {task: {title: ""}}

        expect(response).to have_http_status(:unprocessable_content)
        expect(row_titles(section_id: "due_soon")).to eq(["Mine, due tomorrow"])
      end
    end
  end
end
