# frozen_string_literal: true

module RailsAgentConsole
  module SchemaDiagnostics
    def diagnostics
      models
      Array(@diagnostics).map(&:dup)
    end

    def print(prompt = nil, diagnostics: false)
      output = RailsAgentConsole.configuration.out
      output.puts(context(prompt))
      output.puts("\n#{diagnostics_text}") if diagnostics
      nil
    end

    private

    def diagnostics_text
      issues = diagnostics
      return "Schema diagnostics: no issues detected." if issues.empty?

      count = issues.size
      lines = ["Schema diagnostics: #{count} #{count == 1 ? "issue" : "issues"} detected."]
      issues.each { |issue| lines << "- #{diagnostic_line(issue)}" }
      lines.join("\n")
    end

    def record_diagnostic(scope, model, error)
      @diagnostics ||= []
      @diagnostics << { scope: scope, model: model, error: error.class.name, message: error.message.to_s }
    end

    def diagnostic_line(issue)
      subject = issue[:model] || "Application models"
      action = issue[:scope] == :associations ? "association inspection failed" : "model inspection failed"
      detail = issue[:message].empty? ? issue[:error] : "#{issue[:error]}: #{issue[:message]}"
      "#{subject}: #{action} (#{detail})"
    end
  end
end
