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

  let(:results) { FactGraph::Evaluator.evaluate(input) }

  context "with no entities in input" do
    let(:input) { {} }

    it "returns no values for per_entity facts, but does add a hash for the module despite containing no facts" do
      expected_output = {num_eligible_applicants: 0}
      expect(results[:applicant_facts]).to eq(expected_output)
    end
  end

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
        income: {0 => 48, 1 => 380},
        age: {0 => 101, 1 => 46},
        eligible: {0 => true, 1 => false},
        num_eligible_applicants: 1
      }
      expect(results[:applicant_facts]).to eq(expected_output)
    end

    it "can depend on per-entity facts across modules" do
      expected_output = {
        credit_amounts: {0 => 10100, 1 => 0}
      }
      expect(results[:credit_facts]).to match(expected_output)
    end

    describe "FactGraph.entity_map" do
      it "returns an entity map that includes a correct map of entity names and ids" do
        expect(FactGraph::Graph.entity_map(input)).to eq({applicants: [0, 1]})
      end
    end
  end

  context "with incomplete entities in input that can all still have eligibility evaluated" do
    let(:input) {
      {
        applicants: [
          {
            income: 99,
          },
          {
            age: 101
          }
        ]
      }
    }

    it "returns a value for all entities" do
      expected_output = {
        income: {0 => 99, 1 => bad_fact_matcher},
        age: {0 => bad_fact_matcher, 1 => 101},
        eligible: {0 => true, 1 => true},
        num_eligible_applicants: 2
      }
      expect(results[:applicant_facts]).to match(expected_output)
    end
  end
end
