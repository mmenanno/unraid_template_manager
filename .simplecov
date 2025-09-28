# frozen_string_literal: true

FileUtils.rm_f("coverage/.resultset.json")

SimpleCov.start("rails") do
  enable_coverage :branch
  primary_coverage :branch

  at_exit do
    SimpleCov.formatter = SimpleCov::Formatter::SimpleFormatter
    SimpleCov.result.format!
  end
end
