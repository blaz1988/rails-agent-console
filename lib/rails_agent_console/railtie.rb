# frozen_string_literal: true

require "rails/railtie"

module RailsAgentConsole
  class Railtie < ::Rails::Railtie
    config.rails_agent_console = ActiveSupport::OrderedOptions.new

    initializer "rails_agent_console.configure" do |app|
      app.config.rails_agent_console.each do |key, value|
        setter = "#{key}="
        configuration = RailsAgentConsole.configuration
        configuration.public_send(setter, value) if configuration.respond_to?(setter)
      end
    end

    config.to_prepare do
      RailsAgentConsole::Schema.reset!
    end

    console do
      require "irb"
      require "rails_agent_console/console_installer"
      require "rails_agent_console/console_session"

      RailsAgentConsole::ConsoleInstaller.install!
      RailsAgentConsole::ConsoleSession.start
    end
  end
end
