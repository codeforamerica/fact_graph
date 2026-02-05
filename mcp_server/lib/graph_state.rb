# frozen_string_literal: true

class GraphState
  attr_reader :facts, :test_cases, :graph_contexts

  def initialize
    @facts = []           # Structured fact definitions
    @test_cases = []      # Test cases for validation
    @graph_contexts = []  # Graph contexts for multi-graph support
  end

  # Add a graph context (e.g., "co_2025" or "nj_2024")
  # Facts can be assigned to a context, or left as shared
  def add_graph_context(name, base_class_name: nil)
    base_class_name ||= name.to_s.split("_").map(&:capitalize).join + "Graph"
    context = { name: name.to_s, base_class_name: base_class_name }
    @graph_contexts << context unless @graph_contexts.any? { |c| c[:name] == name.to_s }
    context
  end

  def remove_graph_context(name)
    @graph_contexts.reject! { |c| c[:name] == name.to_s }
  end

  def shared_facts
    @facts.select { |f| f[:graph_context].nil? }
  end

  def facts_for_context(context_name)
    @facts.select { |f| f[:graph_context] == context_name.to_s }
  end

  def add_fact(fact_def)
    @facts << fact_def
  end

  def update_fact(name, module_name, updates)
    fact = @facts.find { |f| f[:name] == name && f[:module_name] == module_name }
    return false unless fact

    fact.merge!(updates)
    true
  end

  def remove_fact(name, module_name)
    @facts.reject! { |f| f[:name] == name && f[:module_name] == module_name }
  end

  def get_fact(name, module_name = nil)
    if module_name
      @facts.find { |f| f[:name] == name && f[:module_name] == module_name }
    else
      @facts.find { |f| f[:name] == name }
    end
  end

  def modules
    @facts.map { |f| f[:module_name] }.uniq
  end

  def facts_in_module(module_name)
    @facts.select { |f| f[:module_name] == module_name }
  end

  def export_code(format: "single_file")
    return nil if @facts.empty?

    case format
    when "single_file"
      export_single_file
    when "per_module"
      export_per_module
    else
      export_single_file
    end
  end

  def clear(keep_test_cases: false)
    @facts = []
    @graph_contexts = []
    @test_cases = [] unless keep_test_cases
  end

  def add_test_case(test_case)
    @test_cases << test_case
  end

  def remove_test_case(index)
    @test_cases.delete_at(index)
  end

  def clear_test_cases
    @test_cases = []
  end

  private

  def export_single_file
    output = ["# frozen_string_literal: true", ""]

    # If no graph contexts defined, use legacy single-class-per-module approach
    if @graph_contexts.empty?
      modules.each do |mod_name|
        output << generate_legacy_module_code(mod_name)
        output << ""
      end
    else
      # Multi-graph approach: shared concerns + context-specific classes
      output << generate_multi_graph_code
    end

    output.join("\n")
  end

  def export_per_module
    if @graph_contexts.empty?
      # Legacy format
      modules.map do |mod_name|
        {
          module_name: mod_name,
          code: generate_legacy_module_code(mod_name)
        }
      end.to_json
    else
      # Multi-graph format: return shared modules and context-specific files
      result = []

      # Shared modules (concerns)
      shared_modules.each do |mod_name|
        result << {
          module_name: "shared/#{mod_name}_facts",
          code: generate_shared_module_code(mod_name)
        }
      end

      # Context-specific files
      @graph_contexts.each do |context|
        result << {
          module_name: "#{context[:name]}/base",
          code: generate_context_base_class(context)
        }
        result << {
          module_name: "#{context[:name]}/facts",
          code: generate_context_facts_code(context)
        }
      end

      result.to_json
    end
  end

  # Modules that have shared facts (no graph_context)
  def shared_modules
    shared_facts.map { |f| f[:module_name] }.uniq
  end

  # Modules that have context-specific facts
  def context_modules(context_name)
    facts_for_context(context_name).map { |f| f[:module_name] }.uniq
  end

  def generate_multi_graph_code
    lines = []

    # Generate shared modules as ActiveSupport::Concern
    shared_modules.each do |mod_name|
      lines << generate_shared_module_code(mod_name)
      lines << ""
    end

    # Generate context-specific classes
    @graph_contexts.each do |context|
      lines << generate_context_base_class(context)
      lines << ""
      lines << generate_context_facts_code(context)
      lines << ""
    end

    lines.join("\n")
  end

  def generate_shared_module_code(module_name)
    # Capitalize each word and add "Facts" suffix for concern name
    concern_name = module_name.to_s.split("_").map(&:capitalize).join + "Facts"
    mod_facts = shared_facts.select { |f| f[:module_name] == module_name }

    lines = []
    lines << "module #{concern_name}"
    lines << "  extend ActiveSupport::Concern"
    lines << ""
    lines << "  included do"
    lines << "    in_module :#{module_name} do"

    mod_facts.each do |fact|
      lines << generate_fact_code(fact, base_indent: 3)
    end

    lines << "    end"
    lines << "  end"
    lines << "end"
    lines.join("\n")
  end

  def generate_context_base_class(context)
    "class #{context[:base_class_name]} < FactGraph::Graph; end"
  end

  def generate_context_facts_code(context)
    context_name = context[:name]
    base_class = context[:base_class_name]

    # Create a class name from context: "co_2025" -> "Co2025Facts"
    class_name = context_name.to_s.split("_").map(&:capitalize).join + "Facts"

    lines = []
    lines << "class #{class_name} < #{base_class}"

    # Include shared modules
    shared_modules.each do |mod_name|
      concern_name = mod_name.to_s.split("_").map(&:capitalize).join + "Facts"
      lines << "  include #{concern_name}"
    end
    lines << "" if shared_modules.any?

    # Group context-specific facts by module
    context_modules(context_name).each do |mod_name|
      mod_facts = facts_for_context(context_name).select { |f| f[:module_name] == mod_name }
      next if mod_facts.empty?

      lines << "  in_module :#{mod_name} do"
      mod_facts.each do |fact|
        lines << generate_fact_code(fact, base_indent: 2)
      end
      lines << "  end"
      lines << ""
    end

    lines << "end"
    lines.join("\n")
  end

  # Legacy single-class-per-module (backward compatible)
  def generate_legacy_module_code(module_name)
    # Capitalize each word but don't add "Facts" suffix so module name matches
    class_name = module_name.to_s.split("_").map(&:capitalize).join
    mod_facts = facts_in_module(module_name)

    lines = ["class #{class_name} < FactGraph::Graph"]

    mod_facts.each do |fact|
      lines << generate_fact_code(fact)
    end

    lines << "end"
    lines.join("\n")
  end

  def generate_fact_code(fact, base_indent: 1)
    lines = []
    indent = "  " * base_indent

    # Handle constants
    if fact[:constant_value]
      lines << "#{indent}constant(:#{fact[:name]}) { #{fact[:constant_value]} }"
      return lines.join("\n")
    end

    # Build fact definition
    fact_args = []
    fact_args << "per_entity: :#{fact[:per_entity]}" if fact[:per_entity]
    fact_args << "allow_unmet_dependencies: true" if fact[:allow_unmet_dependencies]

    fact_line = "#{indent}fact :#{fact[:name]}"
    fact_line += ", #{fact_args.join(", ")}" if fact_args.any?
    fact_line += " do"
    lines << fact_line

    # Inputs
    (fact[:inputs] || []).each do |input|
      input_args = []
      input_args << "per_entity: true" if input[:per_entity]
      input_line = "#{"  " * (base_indent + 1)}input :#{input[:name]}"
      input_line += ", #{input_args.join(", ")}" if input_args.any?
      input_line += " do"
      lines << input_line
      lines << "#{"  " * (base_indent + 2)}Dry::Schema.Params do"
      lines << "#{"  " * (base_indent + 3)}#{input[:schema]}"
      lines << "#{"  " * (base_indent + 2)}end"
      lines << "#{"  " * (base_indent + 1)}end"
    end

    # Dependencies
    (fact[:dependencies] || []).each do |dep|
      dep_line = "#{"  " * (base_indent + 1)}dependency :#{dep[:name]}"
      dep_line += ", from: :#{dep[:from]}" if dep[:from]
      lines << dep_line
    end

    # Resolver
    if fact[:resolver]
      lines << ""
      lines << "#{"  " * (base_indent + 1)}proc do"

      # Build pattern match to extract inputs and dependencies
      # Skip if resolver already contains a pattern match
      unless fact[:resolver].include?("data in")
        input_names = (fact[:inputs] || []).map { |i| i[:name] }
        dep_names = (fact[:dependencies] || []).map { |d| d[:name] }

        if input_names.any? || dep_names.any?
          pattern_parts = []
          pattern_parts << "input: { #{input_names.map { |n| "#{n}:" }.join(", ")} }" if input_names.any?
          pattern_parts << "dependencies: { #{dep_names.map { |n| "#{n}:" }.join(", ")} }" if dep_names.any?
          lines << "#{"  " * (base_indent + 2)}data in #{pattern_parts.join(", ")}"
        end
      end

      fact[:resolver].each_line do |line|
        lines << "#{"  " * (base_indent + 2)}#{line.rstrip}"
      end
      lines << "#{"  " * (base_indent + 1)}end"
    end

    lines << "#{indent}end"
    lines.join("\n")
  end
end
