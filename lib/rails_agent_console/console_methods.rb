# frozen_string_literal: true

module RailsAgentConsole
  module ConsoleMethods
    def ai(prompt = nil)
      RailsAgentConsole.agent.run(prompt)
    end

    def ai!(prompt = nil)
      RailsAgentConsole.agent.run(prompt, write: true)
    end

    def run(prompt = nil)
      ai(prompt)
    end
    alias run_ai run

    def ask(question = nil)
      RailsAgentConsole.agent.ask(question)
    end

    def explain(code = nil, question: nil)
      RailsAgentConsole.agent.explain(code, question: question)
    end

    def ai_history
      RailsAgentConsole.configuration.out.puts(RailsAgentConsole.agent.history.to_s)
      nil
    end

    def ai_reset
      RailsAgentConsole.agent.reset!
      RailsAgentConsole::Schema.reset!
      RailsAgentConsole.configuration.out.puts("Conversation cleared.")
      nil
    end

    def ai_schema(prompt = nil)
      Schema.print(prompt)
    end

    def ai_model(target = nil)
      ModelPicker.run(target)
    end

    ALL = instance_methods(false).freeze

    def self.installable(names = RailsAgentConsole.configuration.console_helpers)
      wanted = Array(names).map(&:to_sym)
      copy = dup
      (ALL - wanted).each { |name| copy.send(:remove_method, name) }
      copy
    end
  end
end
