# Runs the review-rails agent prompt (.claude/agents/review-rails.md) against the
# fixture diffs in evals/cases.yml, then grades each review twice: regex
# assertions from the case metadata, and a Claude Haiku judge.
#
#   ruby evals/run.rb              # needs ANTHROPIC_API_KEY
#   ruby evals/run.rb --dry-run    # prints the prompts, calls nothing
#   EVAL_REPETITIONS=3 ruby evals/run.rb
require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "ruby_llm", "~> 2.1"
  gem "minitest"
end

require "fileutils"
require "json"

ROOT = File.expand_path("..", __dir__)
AGENT = "review-rails"
SUBJECT = {model: "claude-sonnet-5-5", provider: :anthropic}
# claude-haiku-5-5 is newer than the model registry bundled with ruby_llm 2.1.0,
# so skip the registry lookup rather than raise ModelNotFoundError.
JUDGE = {model: "claude-haiku-5-5", provider: :anthropic, assume_model_exists: true}

RubyLLM.configure do |config|
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
  config.request_timeout = 180
  config.max_retries = 2
end

class ReviewRailsEvaluation < RubyLLM::Evaluation
  dataset File.join(__dir__, "cases.yml")
  evaluator(**JUDGE)

  evaluation :planted_issue, <<~CRITERION
    When metadata.planted_issue is set, actual.output (the review) reports that
    problem as 🔴 or 🟠 and gives its location as file:line. When it is null, the
    review raises no 🔴 or 🟠 finding about missing or empty failure handling.
  CRITERION

  evaluation :grounded, <<~CRITERION
    Every finding in actual.output points at code in the diff that the user message
    in actual.messages supplied, and describes a problem that code really has.
    No finding is invented or padded.
  CRITERION

  def self.read(*path)
    File.read(File.join(ROOT, *path), encoding: "UTF-8")
  end

  def self.system_prompt
    read(".claude/agents/#{AGENT}.md").sub(/\A---\n.*?\n---\n/m, "").strip
  end

  def self.user_message(input)
    <<~MESSAGE
      Review this change: #{input["title"]}

      Files changed: #{input["files_changed"].join(", ")}

      You have no file access in this run, so the repo's CLAUDE.md and the diff are below.

      <claude_md>
      #{read("CLAUDE.md")}
      </claude_md>

      <diff>
      #{read("evals", input["diff"])}
      </diff>
    MESSAGE
  end

  def perform(input)
    chat = RubyLLM.chat(**SUBJECT)
      .with_instructions(self.class.system_prompt)
      .with_thinking(effort: :high)
      .with_max_output_tokens(16_000)
    chat.ask(self.class.user_message(input))
    chat
  end

  def assertions
    metadata.fetch("must_match", []).each do |pattern|
      assert Regexp.new(pattern).match?(output), "review should match /#{pattern}/"
    end
    metadata.fetch("must_not_match", []).each do |pattern|
      refute Regexp.new(pattern).match?(output), "review should not match /#{pattern}/"
    end
  end
end

if ARGV.include?("--dry-run")
  puts "subject: #{SUBJECT}", "judge: #{JUDGE}", ""
  puts "== system prompt (.claude/agents/#{AGENT}.md)", ReviewRailsEvaluation.system_prompt
  ReviewRailsEvaluation.cases.each do |test_case|
    puts "", "== user message: #{test_case.name}", ReviewRailsEvaluation.user_message(test_case.inputs)
  end
  exit
end

abort "Set ANTHROPIC_API_KEY, or pass --dry-run." unless ENV["ANTHROPIC_API_KEY"]

# Evaluation.run works through its cases one at a time, so give each case a thread.
repetitions = Integer(ENV.fetch("EVAL_REPETITIONS", "1"))
reports = ReviewRailsEvaluation.cases.map do |test_case|
  Thread.new { ReviewRailsEvaluation.run(only: test_case.name, repetitions:) }
end.map(&:value)
trials = reports.flat_map(&:trials)

row = "%-24s %3s  %-7s %-10s %-13s %-9s %13s %13s %9s %8s"
puts format(row, "case", "rep", "status", "assertions", "planted_issue", "grounded",
  "review in/out", "judge in/out", "review $", "judge $")
trials.each do |trial|
  verdicts = trial.evaluations.to_h { |evaluation| [evaluation.name, evaluation.status] }
  tokens = [trial.task_tokens, trial.evaluator_tokens].map { |used| "#{used.input.to_i}/#{used.output.to_i}" }
  costs = [trial.task_cost.total, trial.evaluator_cost.total].map { |cost| cost ? format("$%.4f", cost) : "n/a" }
  puts format(row, trial.test_case.name, trial.repetition, trial.status,
    trial.assertion_failure ? "failed" : "#{trial.assertion_count} ok",
    verdicts[:planted_issue], verdicts[:grounded], *tokens, *costs)
end
reports.reject(&:passed?).each { |report| puts "", report }

output_dir = ENV.fetch("EVAL_OUTPUT", File.join(ROOT, "tmp", "evaluations"))
FileUtils.mkdir_p(output_dir)
path = File.join(output_dir, "#{AGENT}-#{Time.now.utc.strftime("%Y%m%dT%H%M%SZ")}.json")
File.write(path, JSON.pretty_generate(reports.map(&:to_h)))
puts "", "#{trials.count(&:passed?)}/#{trials.size} trials passed. Report: #{path}"
exit reports.all?(&:passed?)
