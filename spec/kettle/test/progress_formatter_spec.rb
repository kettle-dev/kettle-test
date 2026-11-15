# frozen_string_literal: true

require "json"
require "stringio"
require "open3"
require "rbconfig"
require "kettle/test/progress_formatter"

RSpec.describe Kettle::Test::ProgressFormatter do
  let(:io) { StringIO.new }
  let(:now) { [0.0] }
  let(:progress) { Kettle::Ndjson::TestProgress.new(io: io, source: "kettle-test", interval: 1.0, clock: -> { now[0] }) }
  let(:formatter) { described_class.new(io, progress: progress) }
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

  it "maps rspec notifications onto test_progress events" do
    formatter.example_passed(nil)
    now[0] = 1.5
    formatter.example_pending(nil)
    formatter.example_failed(failed)
    formatter.close(nil)
    expect(events.map { |e| e["kind"] }).to eq(%w[tick tick failure final])
    expect(events[2]).to include("source" => "kettle-test", "location" => "./spec/a_spec.rb:3", "description" => "A fails")
    expect(events.last).to include("examples" => 3, "failures" => 1, "pending" => 1)
  end

  it "builds its own TestProgress (source kettle-test, env interval) when none is injected" do
    stub_env("KETTLE_TEST_EVENTS_INTERVAL" => "5")
    described_class.new(io).close(nil)
    expect(events.last).to include("type" => "test_progress", "source" => "kettle-test", "kind" => "final")
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
