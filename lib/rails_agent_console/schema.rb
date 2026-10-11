# frozen_string_literal: true

require_relative "schema_diagnostics"

module RailsAgentConsole
  module Schema
    extend SchemaDiagnostics

    INTERNAL_PREFIXES = %w[
      ActiveRecord:: ActiveStorage:: ActionText:: ActionMailbox::
      SolidQueue:: SolidCache:: SolidCable:: Delayed:: PgSearch::
    ].freeze

    Model = Struct.new(:name, :table, :columns, :associations, :referenced_by, :abstract,
                       keyword_init: true) do
      def column_names
        columns.map(&:first)
      end

      def association_names
        associations.map { |association| association[:name].to_s }
      end

      def keywords
        [name.downcase, *name.gsub(/([a-z])([A-Z])/, '\1 \2').downcase.split, table.to_s,
         *column_names, *association_names].uniq
      end

      def to_context(columns: true)
        lines = ["#{name} (#{table})"]
        lines << "  columns: #{column_list}" if columns
        associations.each { |association| lines << "  #{association_line(association)}" }
        lines += inbound_lines.map { |line| "  #{line}" } if inbound.any?
        lines.join("\n")
      end

      def inbound
        Array(referenced_by)
      end

      def inbound_lines
        ["#{missing_joins} all raise: no such association exists here.",
         "query from the other side instead -- #{inbound_list} -- " \
         "or filter with a subquery: #{subquery_example}"]
      end

      def missing_joins
        inbound.map { |reference| "#{name}.joins(:#{reference[:table]})" }.join(" and ")
      end

      def inbound_list
        inbound.map do |reference|
          "#{reference[:model]}.joins(:#{reference[:association]}) (#{reference[:foreign_key]})"
        end.join(", ")
      end

      def subquery_example
        reference = inbound.first
        "#{name}.where(id: #{reference[:model]}.select(:#{reference[:foreign_key]}))"
      end

      def column_list
        columns.map { |name, type, extra| extra ? "#{name}:#{type} #{extra}" : "#{name}:#{type}" }.join(", ")
      end

      def association_line(association)
        line = "#{association[:macro]} :#{association[:name]}"
        line += " (#{association[:class_name]})" if association[:class_name] != default_class_name(association)
        line += " through: :#{association[:through]}" if association[:through]
        line
      end

      private

      def default_class_name(association)
        base = association[:name].to_s
        base = base.sub(/s\z/, "") if %i[has_many has_and_belongs_to_many].include?(association[:macro])
        base.split("_").map(&:capitalize).join
      end
    end

    class << self
      def models
        @models ||= load_models
      end

      def model_names
        models.map(&:name)
      end

      def find(name)
        models.find { |model| model.name == name.to_s }
      end

      def reset!
        @models = nil
        @diagnostics = nil
        self
      end

      def context(prompt = nil)
        return "No ActiveRecord models found." if models.empty?

        focused, rest = split_by_relevance(prompt)
        sections = [header]
        sections << focused.map(&:to_context).join("\n\n")
        sections << "Other models: #{rest.map(&:name).sort.join(", ")}" if rest.any?
        sections << RailsAgentConsole.configuration.extra_context if RailsAgentConsole.configuration.extra_context
        sections.compact.join("\n\n")
      end

      def tree(names)
        Array(names).flat_map do |name|
          model = find(name)
          next [] unless model

          lines = [model.name]
          model.associations.each_with_index do |association, index|
            last = index == model.associations.size - 1
            lines << " #{last ? "\u2514\u2500\u2500" : "\u251C\u2500\u2500"} #{model.association_line(association)}"
          end
          lines
        end
      end

      def inspect
        context
      end

      private

      def header
        parts = []
        parts << "Rails #{Rails.version}" if defined?(Rails) && Rails.respond_to?(:version)
        parts << "adapter: #{adapter_name}" if adapter_name
        parts.empty? ? "Application schema:" : parts.join(", ").to_s
      end

      def adapter_name
        return unless active_record?

        ActiveRecord::Base.connection_db_config.adapter
      rescue StandardError
        nil
      end

      def split_by_relevance(prompt)
        config = RailsAgentConsole.configuration
        all = models.first(config.max_models)
        return [all, models.drop(config.max_models)] if prompt.nil? || all.size <= config.max_focused_models

        scored = all.sort_by { |model| [-relevance(model, prompt), model.name] }
        focused = scored.first(config.max_focused_models)
        focused = focused.sort_by(&:name)
        [focused, all - focused]
      end

      def relevance(model, prompt)
        tokens = prompt.to_s.downcase.scan(/[a-z_]{3,}/).map { |token| token.sub(/(ies|es|s)\z/, "") }
        return 0 if tokens.empty?

        model.keywords.sum do |keyword|
          stem = keyword.sub(/(ies|es|s)\z/, "")
          tokens.count { |token| stem.include?(token) || token.include?(stem) }
        end
      end

      def load_models
        return [] unless active_record?

        @diagnostics = []
        eager_load!
        candidates = ActiveRecord::Base.descendants.reject do |klass|
          klass.name.nil? || klass.abstract_class? || internal?(klass.name) || excluded?(klass.name)
        end

        described = candidates.uniq(&:name).sort_by(&:name).filter_map { |klass| describe(klass) }
        link_inbound(described)
      end

      def link_inbound(described)
        by_name = described.to_h { |model| [model.name, model] }

        described.each do |model|
          model.associations.select { |association| association[:macro] == :belongs_to }.each do |association|
            target = by_name[association[:class_name]]
            next if target.nil? || target.name == model.name
            next if target.associations.any? { |inverse| inverse[:class_name] == model.name }

            target.referenced_by << inbound_reference(model, association)
          end
        end

        described
      end

      def inbound_reference(model, association)
        { model: model.name, association: association[:name],
          foreign_key: association[:foreign_key], table: model.table }
      end

      def describe(klass)
        return unless klass.table_exists?

        Model.new(
          name: klass.name,
          table: klass.table_name,
          columns: columns_for(klass),
          associations: associations_for(klass),
          referenced_by: [],
          abstract: false
        )
      rescue StandardError => e
        record_diagnostic(:model, klass.name, e)
        nil
      end

      def columns_for(klass)
        klass.columns.map do |column|
          extra = []
          extra << "pk" if column.name == klass.primary_key
          extra << "null" if column.null && column.name != klass.primary_key
          [column.name, column.type, extra.empty? ? nil : "(#{extra.join(",")})"]
        end
      end

      def associations_for(klass)
        klass.reflect_on_all_associations.map do |reflection|
          {
            macro: reflection.macro,
            name: reflection.name,
            class_name: safe_class_name(reflection),
            foreign_key: safe_foreign_key(reflection),
            through: reflection.options[:through]
          }
        end
      rescue StandardError => e
        record_diagnostic(:associations, klass.name, e)
        []
      end

      def safe_class_name(reflection)
        reflection.options[:class_name]&.to_s || reflection.class_name
      rescue StandardError
        nil
      end

      def safe_foreign_key(reflection)
        reflection.foreign_key.to_s
      rescue StandardError
        nil
      end

      def internal?(name)
        return false if RailsAgentConsole.configuration.include_internal_models

        INTERNAL_PREFIXES.any? { |prefix| name.start_with?(prefix) }
      end

      def excluded?(name)
        RailsAgentConsole.configuration.excluded_models.map(&:to_s).include?(name)
      end

      def eager_load!
        return unless defined?(Rails) && Rails.respond_to?(:application) && Rails.application
        return if Rails.application.config.eager_load

        Rails.application.eager_load!
      rescue StandardError => e
        record_diagnostic(:model, nil, e)
        nil
      end

      def active_record?
        defined?(ActiveRecord::Base) && ActiveRecord::Base.respond_to?(:descendants)
      end
    end
  end
end
