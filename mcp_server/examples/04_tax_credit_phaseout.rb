# frozen_string_literal: true

# Example 4: Tax Credit with Phase-out
#
# POLICY DESCRIPTION:
# A refundable tax credit for low-income workers. The credit amount depends
# on income and filing status, with a phase-in, plateau, and phase-out range.
#
# RULES (simplified EITC-like):
# - Phase-in: Credit increases at 34% of earned income up to $10,000
# - Plateau: Maximum credit of $3,400 for income $10,000-$15,000
# - Phase-out: Credit decreases at 16% for income above $15,000
# - Credit reaches $0 at income of $36,250
# - Different thresholds for single vs married filing jointly

module Examples
  module TaxCreditPhaseout
    POLICY_TEXT = <<~POLICY
      Refundable tax credit for workers:

      Single filers:
      - Phase-in: 34% of earned income up to $10,000 (max credit $3,400)
      - Plateau: Full $3,400 credit for income $10,000-$15,000
      - Phase-out: Reduces by 16% of income over $15,000
      - Fully phased out at $36,250

      Married filing jointly:
      - Same phase-in and plateau
      - Phase-out begins at $20,000 instead of $15,000
      - Fully phased out at $41,250
    POLICY

    FACT_GRAPH_CODE = <<~RUBY
      class TaxCreditFacts < FactGraph::Graph
        # Constants
        constant(:phase_in_rate) { 34 }
        constant(:phase_in_end) { 10_000 }
        constant(:max_credit) { 3_400 }
        constant(:phase_out_rate) { 16 }
        constant(:phase_out_start_single) { 15_000 }
        constant(:phase_out_start_married) { 20_000 }

        # Determine phase-out start based on filing status
        fact :phase_out_start do
          input :filing_status do
            Dry::Schema.Params do
              required(:filing_status).value(:string, included_in?: ["single", "married"])
            end
          end

          dependency :phase_out_start_single
          dependency :phase_out_start_married

          proc do
            data in input: { filing_status: },
                   dependencies: { phase_out_start_single:, phase_out_start_married: }
            filing_status == "married" ? phase_out_start_married : phase_out_start_single
          end
        end

        # Calculate phase-in amount
        fact :phase_in_credit do
          input :earned_income do
            Dry::Schema.Params do
              required(:earned_income).value(:integer, gteq?: 0)
            end
          end

          dependency :phase_in_rate
          dependency :phase_in_end
          dependency :max_credit

          proc do
            data in input: { earned_income: },
                   dependencies: { phase_in_rate:, phase_in_end:, max_credit: }
            income_for_phase_in = [earned_income, phase_in_end].min
            [(income_for_phase_in * phase_in_rate) / 100, max_credit].min
          end
        end

        # Calculate phase-out reduction
        fact :phase_out_reduction do
          input :earned_income do
            Dry::Schema.Params do
              required(:earned_income).value(:integer, gteq?: 0)
            end
          end

          dependency :phase_out_start
          dependency :phase_out_rate

          proc do
            data in input: { earned_income: },
                   dependencies: { phase_out_start:, phase_out_rate: }
            if earned_income <= phase_out_start
              0
            else
              ((earned_income - phase_out_start) * phase_out_rate) / 100
            end
          end
        end

        # Final credit amount
        fact :credit_amount do
          dependency :phase_in_credit
          dependency :phase_out_reduction

          proc do
            data in dependencies: { phase_in_credit:, phase_out_reduction: }
            [phase_in_credit - phase_out_reduction, 0].max
          end
        end

        # Whether any credit is available
        fact :eligible_for_credit do
          dependency :credit_amount

          proc do
            data in dependencies: { credit_amount: }
            credit_amount > 0
          end
        end
      end
    RUBY

    TEST_CASES = [
      {
        description: "Low income in phase-in range",
        input: { earned_income: 5_000, filing_status: "single" },
        expected: {
          tax_credit_facts: {
            phase_in_credit: 1_700,  # 5000 * 34% = 1700
            phase_out_reduction: 0,
            credit_amount: 1_700,
            eligible_for_credit: true
          }
        }
      },
      {
        description: "Income in plateau range (max credit)",
        input: { earned_income: 12_000, filing_status: "single" },
        expected: {
          tax_credit_facts: {
            phase_in_credit: 3_400,  # maxed out
            phase_out_reduction: 0,  # below phase-out start
            credit_amount: 3_400,
            eligible_for_credit: true
          }
        }
      },
      {
        description: "Income in phase-out range (single)",
        input: { earned_income: 25_000, filing_status: "single" },
        expected: {
          tax_credit_facts: {
            phase_in_credit: 3_400,
            phase_out_reduction: 1_600,  # (25000 - 15000) * 16% = 1600
            credit_amount: 1_800,
            eligible_for_credit: true
          }
        }
      },
      {
        description: "Income in phase-out range (married, higher threshold)",
        input: { earned_income: 25_000, filing_status: "married" },
        expected: {
          tax_credit_facts: {
            phase_out_start: 20_000,
            phase_in_credit: 3_400,
            phase_out_reduction: 800,  # (25000 - 20000) * 16% = 800
            credit_amount: 2_600,
            eligible_for_credit: true
          }
        }
      },
      {
        description: "Income fully phased out",
        input: { earned_income: 40_000, filing_status: "single" },
        expected: {
          tax_credit_facts: {
            phase_in_credit: 3_400,
            phase_out_reduction: 4_000,  # (40000 - 15000) * 16% = 4000
            credit_amount: 0,  # max(3400 - 4000, 0) = 0
            eligible_for_credit: false
          }
        }
      }
    ]
  end
end
