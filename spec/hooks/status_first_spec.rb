require "spec_helper"
require "fileutils"
require "json"
require "open3"
require "tmpdir"

RSpec.describe "status-first hook" do
  let(:script) { File.expand_path("../../.claude/hooks/status-first.sh", __dir__) }
  let(:directory) { Dir.mktmpdir }

  let(:reads_body_first) do
    <<~RUBY
      RSpec.describe "Tasks", type: :request do
        it "lists tasks" do
          get tasks_path

          expect(response.body).to include("Task")
        end
      end
    RUBY
  end

  let(:asserts_status_first) do
    <<~RUBY
      RSpec.describe "Tasks", type: :request do
        it "renders the page" do
          get tasks_path

          expect(response).to have_http_status(:ok)
          expect(response.body).to include("Tasks")
        end

        it "shows the new task" do
          post tasks_path, params: {task: {title: "Pack"}}

          expect(response).to have_http_status(:found)
          follow_redirect!
          expect(response).to have_http_status(:ok)
          assert_select "h1"
        end
      end
    RUBY
  end

  after { FileUtils.remove_entry(directory) }

  def write_spec(body:, path: "spec/requests/tasks_spec.rb")
    File.join(directory, path).tap do |full_path|
      FileUtils.mkdir_p(File.dirname(full_path))
      File.write(full_path, body)
    end
  end

  def run_script(arguments: [], stdin_data: "")
    _stdout, stderr, status = Open3.capture3(script, *arguments, stdin_data:)
    [stderr, status.exitstatus]
  end

  def run_hook(tool_input:)
    run_script(stdin_data: {tool_name: "Edit", tool_input:}.to_json)
  end

  it "rejects a response.body read before any status assertion, naming the path, read line and example line" do
    path = write_spec(body: reads_body_first)

    stderr, exit_status = run_hook(tool_input: {file_path: path})

    expect(exit_status).to eq(2)
    expect(stderr).to include("#{path}:5", "(example at line 2)", "have_http_status")
  end

  it "rejects an assert_select with no status assertion" do
    path = write_spec(body: <<~RUBY)
      RSpec.describe "Tasks", type: :request do
        it "offers a form" do
          get tasks_path

          assert_select "form"
        end
      end
    RUBY

    stderr, exit_status = run_hook(tool_input: {file_path: path})

    expect(exit_status).to eq(2)
    expect(stderr).to include("#{path}:5 reads the response")
  end

  it "rejects a parsed_body read with no status assertion" do
    path = write_spec(body: <<~RUBY)
      RSpec.describe "Tasks", type: :request do
        it "lists the titles" do
          get tasks_path

          expect(response.parsed_body.css("h2")).not_to be_empty
        end
      end
    RUBY

    stderr, exit_status = run_hook(tool_input: {file_path: path})

    expect(exit_status).to eq(2)
    expect(stderr).to include("#{path}:5 reads the response")
  end

  it "rejects a response.body read after follow_redirect! with no new status assertion" do
    path = write_spec(body: <<~RUBY)
      RSpec.describe "Tasks", type: :request do
        it "shows the new task" do
          post tasks_path, params: {task: {title: "Pack"}}

          expect(response).to have_http_status(:found)
          follow_redirect!
          expect(response.body).to include("Pack")
        end
      end
    RUBY

    stderr, exit_status = run_hook(tool_input: {file_path: path})

    expect(exit_status).to eq(2)
    expect(stderr).to include("#{path}:7 reads the response")
  end

  it "accepts examples that assert the status first and again after follow_redirect!" do
    path = write_spec(body: asserts_status_first)

    stderr, exit_status = run_hook(tool_input: {file_path: path})

    expect(exit_status).to eq(0)
    expect(stderr).to be_empty
  end

  it "reports each offending example once, however many reads it has" do
    path = write_spec(body: <<~RUBY)
      RSpec.describe "Tasks", type: :request do
        it "reads twice" do
          get tasks_path

          expect(response.body).to include("Tasks")
          assert_select "h1"
        end

        it "reads once" do
          get tasks_path

          assert_select "h1"
        end
      end
    RUBY

    stderr, _exit_status = run_hook(tool_input: {file_path: path})

    expect(stderr.lines.size).to eq(2)
    expect(stderr).to include("#{path}:5", "#{path}:12")
  end

  it "does not count a commented-out status assertion" do
    path = write_spec(body: <<~RUBY)
      RSpec.describe "Tasks", type: :request do
        it "lists tasks" do
          get tasks_path

          # expect(response).to have_http_status(:ok)
          expect(response.body).to include("Task")
        end
      end
    RUBY

    stderr, exit_status = run_hook(tool_input: {file_path: path})

    expect(exit_status).to eq(2)
    expect(stderr).to include("#{path}:6 reads the response")
  end

  it "does not treat a commented-out read as a read" do
    path = write_spec(body: <<~RUBY)
      RSpec.describe "Tasks", type: :request do
        it "redirects to login when signed out" do
          get tasks_path

          # response.body would be the login page here
          expect(response).to redirect_to(new_session_path)
        end
      end
    RUBY

    stderr, exit_status = run_hook(tool_input: {file_path: path})

    expect(exit_status).to eq(0)
    expect(stderr).to be_empty
  end

  it "does not lint helper methods defined after an example" do
    path = write_spec(body: <<~RUBY)
      RSpec.describe "Tasks", type: :request do
        it "redirects to login when signed out" do
          get tasks_path

          expect(response).to redirect_to(new_session_path)
        end

        def row_titles
          response.parsed_body.css("h2").map(&:text)
        end
      end
    RUBY

    stderr, exit_status = run_hook(tool_input: {file_path: path})

    expect(exit_status).to eq(0)
    expect(stderr).to be_empty
  end

  it "ignores specs outside spec/requests" do
    path = write_spec(body: reads_body_first, path: "spec/models/task_spec.rb")

    stderr, exit_status = run_hook(tool_input: {file_path: path})

    expect(exit_status).to eq(0)
    expect(stderr).to be_empty
  end

  it "gives the same verdict when run directly on a path" do
    path = write_spec(body: reads_body_first)

    expect(run_script(arguments: [path])).to eq(run_hook(tool_input: {file_path: path}))
  end

  it "reports a violation in a later file at its own line number" do
    clean_path = write_spec(body: asserts_status_first, path: "spec/requests/clean_spec.rb")
    offending_path = write_spec(body: reads_body_first)

    stderr, exit_status = run_script(arguments: [clean_path, offending_path])

    expect(exit_status).to eq(2)
    expect(stderr.lines.size).to eq(1)
    expect(stderr).to include("#{offending_path}:5 reads the response", "(example at line 2)")
  end

  it "keeps the repository's request specs lint-clean" do
    request_specs = Dir[File.expand_path("../requests/**/*_spec.rb", __dir__)]

    stderr, exit_status = run_script(arguments: request_specs)

    expect(request_specs).not_to be_empty
    expect(stderr).to be_empty
    expect(exit_status).to eq(0)
  end
end
