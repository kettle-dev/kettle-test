# frozen_string_literal: true

require "kettle/test/version_gem"

RSpec.describe Kettle::Test::Version do
  it_behaves_like "a Version module", described_class
end
