# frozen_string_literal: true

require "json"
require "stringio"
require "open3"
require "rbconfig"
require "kettle/test/progress_formatter"

RSpec.describe Kettle::Test::ProgressFormatter do
  let(:io) { StringIO.new }
  let(:now) { [0.0] }
  let(:formatter) { described_class.new(io, interval: 1.0, clock: -> { now[0] }) }
  let(:example) { double("example", location: "./spec/a_spec.rb:3", full_description: "A fails") }
  let(:failed) { double("notification", example: example) }

  def events
    io.string.lines.map(&:strip).reject(&:empty?).map { |l| JSON.parse(l) }
  end

  it "is off unless KETTLE_TEST_EVENTS is truthy" do
    expect(described_class.enabled?({})).to be(false)
    expect(described_class.enabled?({"KETTLE_TEST_EVENTS" => "1"})).to be(true)
  end

  it "detects turbo workers" do
    expect(described_class.turbo_worker?({"RSPEC_FORMATTER_OUTPUT_ID" => "x"})).to be(true)
    expect(described_class.turbo_worker?({})).to be(false)
  end

  it "throttles ticks" do
    5.times { formatter.example_passed(nil) }
    expect(events.size).to eq(1)
    now[0] = 1.5
    formatter.example_pending(nil)
    expect(events.last).to include(
      "type" => "test_progress", "event_version" => 1, "kind" => "tick", "source" => "kettle-test",
      "examples" => 6, "failures" => 0, "pending" => 1, "elapsed" => 1.5
    )
    expect(events.size).to eq(2)
  end

  it "emits failures immediately and a final event" do
    formatter.example_passed(nil)
    formatter.example_failed(failed)
    formatter.close(nil)
    expect(events[1]).to include("kind" => "failure", "failures" => 1, "location" => "./spec/a_spec.rb:3", "description" => "A fails")
    expect(events.last).to include("kind" => "final", "examples" => 2, "failures" => 1)
  end

  describe "interval from env" do
    it "uses KETTLE_TEST_EVENTS_INTERVAL, falling back on garbage or negatives" do
      stub_env("KETTLE_TEST_EVENTS_INTERVAL" => "5")
      expect(described_class.new(io).instance_variable_get(:@interval)).to eq(5.0)
      stub_env("KETTLE_TEST_EVENTS_INTERVAL" => "abc")
      expect(described_class.new(io).instance_variable_get(:@interval)).to eq(1.0)
      stub_env("KETTLE_TEST_EVENTS_INTERVAL" => "-2")
      expect(described_class.new(io).instance_variable_get(:@interval)).to eq(1.0)
    end
  end

  describe "opt-in wiring (real rspec subprocess)" do
    def run_rspec(env)
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "a_spec.rb"), <<~RUBY)
          require "kettle/test/rspec"
          RSpec.describe("a") { it("passes") { expect(1).to eq(1) }; it("fails") { expect(1).to eq(2) } }
        RUBY
        out, = Open3.capture2(env, RbConfig.ruby, "-I", File.expand_path("../../../lib", __dir__), "-S", "rspec", File.join(dir, "a_spec.rb"), chdir: dir)
        out.lines.map(&:strip).select { |l| l.include?('"type":"test_progress"') }.map { |l| JSON.parse(l[l.index("{"), l.size]) }
      end
    end

    it "emits nothing by default" do
      expect(run_rspec({"KETTLE_TEST_EVENTS" => nil})).to be_empty
    end

    it "emits failure and final events when opted in" do
      kinds = run_rspec({"KETTLE_TEST_EVENTS" => "1"}).map { |e| e["kind"] }
      expect(kinds).to include("failure", "final")
    end
  end
end
