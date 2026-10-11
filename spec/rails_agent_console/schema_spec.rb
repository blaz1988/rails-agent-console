# frozen_string_literal: true

RSpec.describe RailsAgentConsole::Schema do
  describe ".models" do
    it "lists the application models that have a table" do
      expect(described_class.model_names).to eq(%w[Customer Invoice PageView SupportTicket])
    end

    it "skips abstract classes" do
      expect(described_class.model_names).not_to include("ApplicationRecord")
    end

    it "skips models whose table is missing" do
      expect(described_class.model_names).not_to include("LegacyThing")
    end

    it "skips framework-owned models" do
      expect(described_class.model_names).not_to include("ActiveStorage::Attachment")
    end

    it "includes framework-owned models when asked to" do
      RailsAgentConsole.configuration.include_internal_models = true
      described_class.reset!

      expect(described_class.model_names).to include("ActiveStorage::Attachment")
    end

    it "honours excluded_models" do
      RailsAgentConsole.configuration.excluded_models = %w[PageView SupportTicket]
      described_class.reset!

      expect(described_class.model_names).to eq(%w[Customer Invoice])
    end

    it "caches until reset" do
      first = described_class.models

      expect(described_class.models).to be(first)
      expect(described_class.reset!.models).not_to be(first)
    end
  end

  describe ".diagnostics" do
    it "is empty when schema inspection succeeds" do
      expect(described_class.diagnostics).to be_empty
    end

    it "reports a model that could not be inspected" do
      allow(Invoice).to receive(:table_exists?).and_raise(RuntimeError, "metadata unavailable")
      described_class.reset!

      expect(described_class.model_names).not_to include("Invoice")
      expect(described_class.diagnostics).to include(
        scope: :model,
        model: "Invoice",
        error: "RuntimeError",
        message: "metadata unavailable"
      )
    end

    it "keeps a model but reports association inspection failures" do
      allow(Customer).to receive(:reflect_on_all_associations).and_raise(RuntimeError, "reflection unavailable")
      described_class.reset!

      expect(described_class.model_names).to include("Customer")
      expect(described_class.find("Customer").associations).to be_empty
      expect(described_class.diagnostics).to include(
        scope: :associations,
        model: "Customer",
        error: "RuntimeError",
        message: "reflection unavailable"
      )
    end
  end

  describe ".context" do
    subject(:context) { described_class.context }

    it "names the table of every model" do
      expect(context).to include("Customer (customers)", "Invoice (invoices)", "SupportTicket (support_tickets)")
    end

    it "lists columns with their types, primary key and nullability" do
      expect(context).to include("columns: id:integer (pk), name:string, country:string (null)")
    end

    it "lists associations with their macro" do
      expect(context).to include("has_many :invoices", "has_many :support_tickets", "belongs_to :customer")
    end

    it "names the models that point here without an inverse association" do
      expect(context).to include(
        "Customer.joins(:page_views) all raise: no such association exists here.",
        "PageView.joins(:customer) (customer_id)",
        "Customer.where(id: PageView.select(:customer_id))"
      )
    end

    it "says nothing about references that do have an inverse" do
      expect(context).not_to include("Invoice.joins(:customer)", "SupportTicket.joins(:customer)")
    end

    it "mentions the Rails-visible environment" do
      expect(context).to include("adapter: sqlite3")
    end

    it "appends extra context" do
      RailsAgentConsole.configuration.extra_context = "Revenue lives on Invoice#amount."

      expect(described_class.context).to end_with("Revenue lives on Invoice#amount.")
    end
  end

  describe "focusing on the relevant models" do
    before { RailsAgentConsole.configuration.max_focused_models = 1 }

    {
      "which invoices are unpaid?" => "Invoice",
      "list the support tickets" => "SupportTicket",
      "how many customers signed up?" => "Customer"
    }.each do |prompt, expected_model|
      it "describes #{expected_model} in full for #{prompt.inspect}" do
        context = described_class.context(prompt)

        expect(context).to include("#{expected_model} (")
        expect(context).to match(/Other models: /)
      end
    end

    it "lists the models it left out by name" do
      expect(described_class.context("unpaid invoices")).to include("Other models: Customer, PageView, SupportTicket")
    end

    it "describes everything when no prompt is given" do
      RailsAgentConsole.configuration.max_focused_models = 8

      expect(described_class.context).not_to include("Other models:")
    end

    it "respects max_models" do
      RailsAgentConsole.configuration.max_models = 1
      RailsAgentConsole.configuration.max_focused_models = 8

      expect(described_class.context).to include("Other models: Invoice, PageView, SupportTicket")
    end
  end

  describe ".tree" do
    it "renders a model with its associations" do
      expect(described_class.tree(%w[Customer])).to eq(
        ["Customer", " ├── has_many :invoices", " └── has_many :support_tickets"]
      )
    end

    it "renders several models" do
      expect(described_class.tree(%w[Customer Invoice])).to include("Customer", "Invoice")
    end

    it "ignores unknown models" do
      expect(described_class.tree(%w[Nope])).to be_empty
    end
  end

  describe ".inspect and .print" do
    it "returns the context" do
      expect(described_class.inspect).to eq(described_class.context)
    end

    it "prints the context to the configured output" do
      described_class.print

      expect(printed).to include("Customer (customers)")
    end

    it "prints a focused context when given a prompt" do
      RailsAgentConsole.configuration.max_focused_models = 1
      described_class.print("invoices")

      expect(printed).to include("Invoice (invoices)", "Other models:")
    end
  end

  describe ".find" do
    it "finds a model by name" do
      expect(described_class.find("Invoice").table).to eq("invoices")
    end

    it "returns nil for an unknown name" do
      expect(described_class.find("Nope")).to be_nil
    end

    it "exposes columns and associations" do
      model = described_class.find("Invoice")

      expect(model.column_names).to include("amount", "paid_at", "status")
      expect(model.association_names).to eq(%w[customer])
    end
  end
end
