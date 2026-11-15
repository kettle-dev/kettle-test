# frozen_string_literal: true

require "kettle/ndjson"
require "rspec/core"
require "rspec/core/formatters"

module Kettle
  module Test
    # Plain-rspec formatter emitting throttled NDJSON `test_progress` events
    # (the same schema turbo_tests2 emits for parallel runs; see README
    # "Live test progress events"): a `tick` at most once per interval
    # (default 1s), an immediate `failure` per failed example, and one `final`.
    # Never one event per example.
    #
    # Opt-in: set KETTLE_TEST_EVENTS=1 (auto-registered by kettle/test/rspec),
    # or pass `--format Kettle::Test::ProgressFormatter` explicitly.
    class ProgressFormatter
      ENV_KEY = "KETTLE_TEST_EVENTS"
      INTERVAL_ENV_KEY = "KETTLE_TEST_EVENTS_INTERVAL"
      EVENT_TYPE = "test_progress"
      DEFAULT_INTERVAL = 1.0
      TRUTHY = %w[1 true yes on].freeze

      ::RSpec::Core::Formatters.register(self, :example_passed, :example_pending, :example_failed, :close)

      def self.enabled?(env = ENV)
        TRUTHY.include?(env[ENV_KEY].to_s.strip.downcase)
      end

      # Workers spawned by turbo_tests2 must not emit; the parent aggregates.
      def self.turbo_worker?(env = ENV)
        env.key?("RSPEC_FORMATTER_OUTPUT_ID")
      end

      attr_reader :examples, :failures, :pending

      def initialize(output, interval: nil, clock: nil)
        @output = output
        @interval = interval || interval_from_env
        @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
        @events = Kettle::Ndjson.event_stream(output, types: EVENT_TYPE, event_types: [EVENT_TYPE])
        @examples = 0
        @failures = 0
        @pending = 0
        @started_at = @clock.call
        @last_tick = nil
      end

      def example_passed(_notification)
        count
        tick_if_due
      end

      def example_pending(_notification)
        @pending += 1
        count
        tick_if_due
      end

      def example_failed(notification)
        @failures += 1
        count
        example = notification.example
        emit("failure", location: example.location, description: example.full_description)
        @last_tick = @clock.call
      end

      def close(_notification)
        emit("final")
      end

      private

      def count
        @examples += 1
      end

      def tick_if_due
        now = @clock.call
        return if @last_tick && now - @last_tick < @interval

        @last_tick = now
        emit("tick")
      end

      def interval_from_env
        value = Float(ENV.fetch(INTERVAL_ENV_KEY, DEFAULT_INTERVAL.to_s))
        value.negative? ? DEFAULT_INTERVAL : value
      rescue ArgumentError
        DEFAULT_INTERVAL
      end

      def emit(kind, extra = {})
        # Leading newline: progress dots share stdout and would prefix the JSON.
        @output.write("\n")
        Kettle::Ndjson.emit_event(
          @events,
          EVENT_TYPE,
          {
            kind: kind,
            source: "kettle-test",
            examples: @examples,
            failures: @failures,
            pending: @pending,
            elapsed: (@clock.call - @started_at).round(2)
          }.merge(extra)
        )
      end
    end
  end
end
