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
end
