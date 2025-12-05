def bad_fact_matcher
  {
    fact_bad_inputs: anything,
    fact_dependency_unmet: anything
  }
end

RSpec.describe "Entity Facts" do
  before do
    FactGraph::Graph.graph_registry = []
    load "spec/fixtures/entities.rb"
  end

  let(:evaluator) { FactGraph::Evaluator.new }
  let(:results) { evaluator.evaluate(input) }

  context "with complete entities in input" do
    let(:input) {
      {
        applicants: [
          {
            income: 48,
            age: 101
          },
          {
            income: 380,
            age: 46
          }
        ]
      }
    }

    it "returns a value for all entities" do
      expected_output = {
        age_threshold: 100,
        income_threshold: 100,
        income: [48, 380],
        age: [101, 46],
        num_applicants: 2,
        eligible: [true, false]
      }
      expect(results[:applicant_facts]).to eq(expected_output)
    end
  end

  context "with incomplete entities in input that can all still have eligibility evaluated" do
    let(:input) {
      {
        applicants: [
          {
            income: 101,
          },
          {
            age: 101
          }
        ]
      }
    }

    it "returns a value for all entities" do
      expected_output = {
        age_threshold: 100,
        income_threshold: 100,
        income: [48, bad_fact_matcher],
        age: [bad_fact_matcher, 46],
        num_applicants: 2,
        eligible: [true, true]
      }
      expect(results[:applicant_facts]).to match(expected_output)
    end
  end
end
