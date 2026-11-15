# frozen_string_literal: true

require "kettle/ndjson"
require "rspec/core"
require "rspec/core/formatters"

module Kettle
  module Test
    # Plain-rspec formatter emitting throttled NDJSON `test_progress` events
    # (the same schema turbo_tests2 emits for parallel runs; see README
    # "Live test progress events"). A thin adapter over Kettle::Ndjson::TestProgress.
    #
    # Opt-in: set KETTLE_TEST_EVENTS=1 (auto-registered by kettle/test/rspec),
    # or pass `--format Kettle::Test::ProgressFormatter` explicitly.
    class ProgressFormatter
      ::RSpec::Core::Formatters.register(self, :example_passed, :example_pending, :example_failed, :close)

      def self.enabled?(env = ENV)
        Kettle::Ndjson::TestProgress.enabled?(env)
      end

      # Workers spawned by turbo_tests2 must not emit; the parent aggregates.
      def self.turbo_worker?(env = ENV)
        env.key?("RSPEC_FORMATTER_OUTPUT_ID")
      end

      def initialize(output, progress: nil)
        @progress = progress || Kettle::Ndjson::TestProgress.new(
          io: output,
          source: "kettle-test",
          interval: Kettle::Ndjson::TestProgress.interval_from_env
        )
      end

      def example_passed(_notification)
        @progress.record(:passed)
      end

      def example_pending(_notification)
        @progress.record(:pending)
      end

      def example_failed(notification)
        example = notification.example
        @progress.record(:failed, location: example.location, description: example.full_description)
      end

      def close(_notification)
        @progress.finish
      end
    end
  end
end
