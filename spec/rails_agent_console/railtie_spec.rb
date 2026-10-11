# frozen_string_literal: true

require "rails_agent_console/railtie"

RSpec.describe RailsAgentConsole::Railtie do
  describe "schema reload hook" do
    it "resets the cached schema from the to_prepare callback" do
      callback = described_class.config.to_prepare_blocks.find do |block|
        block.source_location&.first&.end_with?("/lib/rails_agent_console/railtie.rb")
      end
      cached_models = RailsAgentConsole::Schema.models

      expect(callback).not_to be_nil

      callback.call

      expect(RailsAgentConsole::Schema.models).not_to be(cached_models)
    end
  end
end
