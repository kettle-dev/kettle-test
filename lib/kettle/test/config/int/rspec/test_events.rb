# frozen_string_literal: true

# Opt-in live test_progress events: KETTLE_TEST_EVENTS=1 registers the formatter
# on stdout. Skipped inside turbo_tests2 workers (the parent process emits).
require_relative "../../../progress_formatter"

if Kettle::Test::ProgressFormatter.enabled? && !Kettle::Test::ProgressFormatter.turbo_worker?
  RSpec.configure do |config|
    config.add_formatter(Kettle::Test::ProgressFormatter, $stdout)
  end
end
