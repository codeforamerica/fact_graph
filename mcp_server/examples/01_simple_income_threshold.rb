# frozen_string_literal: true

# Example 1: Simple Income Threshold
#
# POLICY DESCRIPTION:
# A person is eligible for assistance if their annual income is below $30,000.
#
# RULES:
# - Income must be provided as an integer (dollars)
# - If income < $30,000, they are eligible
# - If income >= $30,000, they are not eligible

module Examples
  module SimpleIncomeThreshold
    POLICY_TEXT = <<~POLICY
      A person is eligible for assistance if their annual income is below $30,000.
    POLICY

    FACT_GRAPH_CODE = <<~RUBY
      class SimpleEligibilityFacts < FactGraph::Graph
        constant(:income_threshold) { 30_000 }

        fact :eligible do
          input :income do
            Dry::Schema.Params do
              required(:income).value(:integer, gteq?: 0)
            end
          end

          dependency :income_threshold

          proc do
            data in input: { income: }, dependencies: { income_threshold: }
            income < income_threshold
          end
        end
      end
    RUBY

    TEST_CASES = [
      {
        description: "Income well below threshold",
        input: { income: 20_000 },
        expected: {
          simple_eligibility_facts: {
            income_threshold: 30_000,
            eligible: true
          }
        }
      },
      {
        description: "Income at threshold (not eligible)",
        input: { income: 30_000 },
        expected: {
          simple_eligibility_facts: {
            income_threshold: 30_000,
            eligible: false
          }
        }
      },
      {
        description: "Income above threshold",
        input: { income: 50_000 },
        expected: {
          simple_eligibility_facts: {
            income_threshold: 30_000,
            eligible: false
          }
        }
      }
    ]
  end
end
