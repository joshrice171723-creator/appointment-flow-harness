require "ripper"

module ActiveRecordQueryCheck
  RAW_QUERY_METHODS = %w[find_by_sql count_by_sql async_find_by_sql async_count_by_sql exec_query exec_update
    exec_delete exec_insert select_all select_rows select_value select_values select_one raw_connection].freeze
  RELATION_METHODS = %w[where having joins left_joins left_outer_joins from order reorder group select reselect
    pluck pick calculate lock update_all].freeze
  COLUMN_METHODS = %w[group order reorder select reselect pluck pick calculate].freeze
  COLUMN_NAME = /\A[a-z_]\w*(?:\.[a-z_]\w*){0,2}\z/i
  SQL_COMMAND = /\b(?:SELECT|INSERT|UPDATE|DELETE|WITH|TRUNCATE)\b/i
  IGNORED_TOKENS = %i[on_sp on_nl on_ignored_nl on_comment].freeze

  def self.source_findings(path)
    tokens = Ripper.lex(path.read).reject { |_, type, _| IGNORED_TOKENS.include?(type) }
    tokens.each_with_index.filter_map do |((line, _), type, method), index|
      next unless %i[on_ident on_const].include?(type)

      previous = index.positive? ? tokens[index - 1] : nil
      next if previous && (previous[1] == :on_symbeg || previous[2] == "def")

      following = tokens[index + 1]
      argument_index = following&.[](2) == "(" ? index + 2 : index + 1
      argument = tokens[argument_index]
      content = tokens[argument_index + 1]
      literal = %i[on_tstring_beg on_heredoc_beg].include?(argument&.[](1))
      arel = method == "Arel" && following&.[](2) == "." && tokens[index + 2]&.[](2) == "sql"
      query_string = RELATION_METHODS.include?(method) && literal &&
        !(COLUMN_METHODS.include?(method) && content&.[](2).to_s.match?(COLUMN_NAME) && tokens[argument_index + 2]&.[](1) == :on_tstring_end)
      execution = method == "execute" && literal && content&.[](2).to_s.match?(SQL_COMMAND)
      "#{path.relative_path_from(Rails.root)}:#{line} (#{method})" if arel || query_string || execution || RAW_QUERY_METHODS.include?(method)
    end
  end

  def self.model_findings
    Rails.application.eager_load!
    ActiveRecord::Base.descendants.reject(&:abstract_class?).filter_map do |model|
      next unless model.table_name

      model.with_connection do |connection|
        source = model.table_name
        if connection.data_source_exists?(source) && !connection.table_exists?(source)
          "#{model.name} reads from #{source}, a view. Verify the query logic at its source."
        elsif !connection.data_source_exists?(source)
          "#{model.name} has no migrated data source #{source} to check."
        end
      end
    end.uniq
  end
end

paths = %w[app lib].flat_map { |directory| Rails.root.glob("#{directory}/**/*.rb") }
findings = paths.flat_map { |path| ActiveRecordQueryCheck.source_findings(path) } + ActiveRecordQueryCheck.model_findings
if findings.empty?
  puts "Active Record query check passed. Review still traces material query logic to its data source."
else
  warn "Active Record query check requires revision:"
  findings.each { |finding| warn "  #{finding}" }
  exit 1
end
