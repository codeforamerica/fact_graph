#!/usr/bin/env ruby
# frozen_string_literal: true

# Test the validation pipeline with various error cases

require "bundler/setup"
require "json"
require "fact_graph"

require_relative "lib/code_validator"

def test_validation(name, code, test_input: nil)
  puts "=" * 60
  puts "TEST: #{name}"
  puts "=" * 60
  puts "Code:"
  puts code
  puts "-" * 40

  validator = CodeValidator.new(code).validate
  result = validator.to_h
  validator.cleanup

  puts "Result:"
  puts JSON.pretty_generate(result)
  puts
end

# Test 1: Valid code
test_validation("Valid code", <<~RUBY)
  class EligibilityFacts < FactGraph::Graph
    constant(:threshold) { 1000 }

    fact :is_eligible do
      input :income do
        Dry::Schema.Params { required(:income).value(:integer) }
      end
      dependency :threshold

      proc do
        data in input: { income: }, dependencies: { threshold: }
        income < threshold
      end
    end
  end
RUBY

# Test 2: Syntax error
test_validation("Syntax error - missing end", <<~RUBY)
  class BrokenFacts < FactGraph::Graph
    fact :broken do
      proc do
        true
      # missing end
    end
  end
RUBY

# Test 3: Missing dependency
test_validation("Missing dependency", <<~RUBY)
  class MissingDepFacts < FactGraph::Graph
    fact :needs_something do
      dependency :nonexistent_fact

      proc do
        data[:dependencies][:nonexistent_fact]
      end
    end
  end
RUBY

# Test 4: Valid code with test input
test_validation("Valid code with test evaluation", <<~RUBY, test_input: { "income" => 500 })
  class TestEvalFacts < FactGraph::Graph
    constant(:threshold) { 1000 }

    fact :is_eligible do
      input :income do
        Dry::Schema.Params { required(:income).value(:integer) }
      end
      dependency :threshold

      proc do
        data in input: { income: }, dependencies: { threshold: }
        income < threshold
      end
    end
  end
RUBY

# Test 5: Valid code with bad test input
test_validation("Valid code with invalid test input", <<~RUBY, test_input: { "income" => "not_a_number" })
  class BadInputFacts < FactGraph::Graph
    fact :needs_integer do
      input :income do
        Dry::Schema.Params { required(:income).value(:integer) }
      end

      proc do
        data in input: { income: }
        income * 2
      end
    end
  end
RUBY

# Test 6: No facts defined
test_validation("No facts defined", <<~RUBY)
  class EmptyFacts < FactGraph::Graph
    # Nothing here
  end
RUBY

# Test 7: Name error (undefined constant)
test_validation("Undefined constant", <<~RUBY)
  class BadRefFacts < FactGraph::Graph
    fact :uses_undefined do
      proc do
        UndefinedConstant.do_something
      end
    end
  end
RUBY

puts "=" * 60
puts "All validation tests completed!"
puts "=" * 60
