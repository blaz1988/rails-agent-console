# frozen_string_literal: true

require "irb"
require "rails_agent_console/console_installer"

RSpec.describe RailsAgentConsole::ConsoleMethods do
  let(:console) { Class.new { include RailsAgentConsole::ConsoleMethods }.new }

  before do
    stub_client json_reply("Customer.count")
    answer_with "y", "y"
  end

  describe "the helpers" do
    it "runs a read-only query with ai" do
      expect(console.ai("how many customers?")).to eq(2)
    end

    it "treats run as an alias of ai" do
      expect(console.run("how many customers?")).to eq(2)
      expect(console.run_ai("how many customers?")).to eq(2)
    end

    it "enables write mode for a single ai! call" do
      stub_client json_reply("Customer.where(plan: \"free\").delete_all")
      answer_with "execute"

      console.ai!("delete free customers")

      expect(Customer.count).to eq(1)
      expect(RailsAgentConsole.configuration).not_to be_write_mode
    end

    it "never executes for ask" do
      stub_client "Because it avoids N+1 queries."

      expect(console.ask("why use includes?")).to be_nil
      expect(printed).to include("Because it avoids N+1")
    end

    it "explains a relation" do
      stub_client "It filters unpaid invoices."

      console.explain(Invoice.where(status: "unpaid"))

      expect(printed).to include("It filters unpaid invoices.")
    end

    it "prints the schema" do
      console.ai_schema

      expect(printed).to include("Customer (customers)")
    end

    it "prints a focused schema" do
      RailsAgentConsole.configuration.max_focused_models = 1
      console.ai_schema("invoices")

      expect(printed).to include("Invoice (invoices)")
    end

    it "prints and clears the conversation" do
      console.ai("how many customers?")
      console.ai_history

      expect(printed).to include("1. how many customers?")

      console.ai_reset

      expect(RailsAgentConsole.agent.history).to be_empty
    end

    it "clears the cached schema" do
      cached_models = RailsAgentConsole::Schema.models

      console.ai_reset

      expect(RailsAgentConsole::Schema.models).not_to be(cached_models)
    end
  end

  describe ".installable" do
    it "defines every helper by default" do
      expect(described_class.installable.instance_methods(false))
        .to include(:ai, :ai!, :ask, :explain, :run, :ai_schema, :ai_history, :ai_reset)
    end

    [
      %i[ai],
      %i[ai ask],
      %i[ai ai! ask explain]
    ].each do |names|
      it "defines only #{names.inspect} when asked" do
        expect(described_class.installable(names).instance_methods(false).sort).to eq(names.sort)
      end
    end

    it "can leave out the generic run helper" do
      expect(described_class.installable(%i[ai ask]).instance_methods(false)).not_to include(:run)
    end

    it "does not modify the original module" do
      described_class.installable(%i[ai])

      expect(described_class.instance_methods(false)).to include(:run)
    end
  end

  describe RailsAgentConsole::ConsoleInstaller do
    it "registers the helpers as IRB helper methods" do
      RailsAgentConsole.configuration.console_helpers = %i[ai]
      RailsAgentConsole.configuration.auto_confirm = true

      described_class.install!
      helper = IRB::HelperMethod.helper_methods[:ai]

      expect(helper).not_to be_nil
      expect(helper.instance.execute("how many customers?")).to eq(2)
    end

    it "prefers Rails::ConsoleMethods when the Rails version provides it" do
      rails_console_methods = Module.new
      stub_const("Rails::ConsoleMethods", rails_console_methods)

      described_class.install!

      expect(rails_console_methods.instance_methods).to include(:ai, :ask)
    end
  end
end
