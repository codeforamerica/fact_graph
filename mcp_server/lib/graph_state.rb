# frozen_string_literal: true

class GraphState
  attr_reader :facts, :code, :test_cases

  def initialize
    @facts = []       # Structured fact definitions
    @code = nil       # Raw code (from generate_fact_graph or manual)
    @test_cases = []  # Test cases for validation
  end

  def set_code(code)
    @code = code
    @facts = []  # Clear structured facts when setting raw code
  end

  def add_fact(fact_def)
    @facts << fact_def
    @code = nil  # Invalidate raw code cache when adding structured facts
  end

  def update_fact(name, module_name, updates)
    fact = @facts.find { |f| f[:name] == name && f[:module_name] == module_name }
    return false unless fact

    fact.merge!(updates)
    @code = nil
    true
  end

  def remove_fact(name, module_name)
    @facts.reject! { |f| f[:name] == name && f[:module_name] == module_name }
    @code = nil
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
    return @code if @code && @facts.empty?
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

  def clear
    @facts = []
    @code = nil
    @test_cases = []
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

    modules.each do |mod_name|
      output << generate_module_code(mod_name)
      output << ""
    end

    output.join("\n")
  end

  def export_per_module
    modules.map do |mod_name|
      {
        module_name: mod_name,
        code: generate_module_code(mod_name)
      }
    end.to_json
  end

  def generate_module_code(module_name)
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

  def generate_fact_code(fact)
    lines = []
    indent = "  "

    # Handle constants
    if fact[:constant_value]
      lines << "#{indent}constant(:#{fact[:name]}) { #{fact[:constant_value]} }"
      return lines.join("\n")
    end

    # Build fact definition
    fact_args = []
    fact_args << "per_entity: :#{fact[:per_entity]}" if fact[:per_entity]

    fact_line = "#{indent}fact :#{fact[:name]}"
    fact_line += ", #{fact_args.join(", ")}" if fact_args.any?
    fact_line += " do"
    lines << fact_line

    # Inputs
    (fact[:inputs] || []).each do |input|
      input_args = []
      input_args << "per_entity: true" if input[:per_entity]
      input_line = "#{indent * 2}input :#{input[:name]}"
      input_line += ", #{input_args.join(", ")}" if input_args.any?
      input_line += " do"
      lines << input_line
      lines << "#{indent * 3}Dry::Schema.Params do"
      lines << "#{indent * 4}#{input[:schema]}"
      lines << "#{indent * 3}end"
      lines << "#{indent * 2}end"
    end

    # Dependencies
    (fact[:dependencies] || []).each do |dep|
      dep_line = "#{indent * 2}dependency :#{dep[:name]}"
      dep_line += ", from: :#{dep[:from]}" if dep[:from]
      lines << dep_line
    end

    # Resolver
    if fact[:resolver]
      lines << ""
      lines << "#{indent * 2}proc do"

      # Build pattern match to extract inputs and dependencies
      # Skip if resolver already contains a pattern match
      unless fact[:resolver].include?("data in")
        input_names = (fact[:inputs] || []).map { |i| i[:name] }
        dep_names = (fact[:dependencies] || []).map { |d| d[:name] }

        if input_names.any? || dep_names.any?
          pattern_parts = []
          pattern_parts << "input: { #{input_names.map { |n| "#{n}:" }.join(", ")} }" if input_names.any?
          pattern_parts << "dependencies: { #{dep_names.map { |n| "#{n}:" }.join(", ")} }" if dep_names.any?
          lines << "#{indent * 3}data in #{pattern_parts.join(", ")}"
        end
      end

      fact[:resolver].each_line do |line|
        lines << "#{indent * 3}#{line.rstrip}"
      end
      lines << "#{indent * 2}end"
    end

    lines << "#{indent}end"
    lines.join("\n")
  end
end
