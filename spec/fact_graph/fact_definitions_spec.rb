# frozen_string_literal: true

RSpec.describe "FactGraph::Graph.fact_definitions" do
  before do
    FactGraph::Graph.graph_registry = []
  end

  context "with math fixtures" do
    before do
      load "spec/fixtures/math.rb"
    end

    it "returns a nested hash of {module_name => {fact_name => Fact}}" do
      defs = FactGraph::Graph.fact_definitions

      expect(defs).to be_a(Hash)
      expect(defs.keys).to contain_exactly(:simple_facts, :math_facts, :circle_facts)

      defs.each_value do |module_facts|
        expect(module_facts).to be_a(Hash)
        module_facts.each_value do |fact|
          expect(fact).to be_a(FactGraph::Fact)
        end
      end
    end

    it "includes all facts from the registry" do
      defs = FactGraph::Graph.fact_definitions

      expect(defs[:simple_facts].keys).to eq([:two])
      expect(defs[:math_facts].keys).to contain_exactly(:pi, :squared_scale)
      expect(defs[:circle_facts].keys).to eq([:areas])
    end

    it "creates Fact objects with correct dependencies" do
      defs = FactGraph::Graph.fact_definitions

      areas = defs[:circle_facts][:areas]
      expect(areas.dependencies).to eq({pi: :math_facts, squared_scale: :math_facts})
    end

    it "creates Fact objects with correct input_definitions" do
      defs = FactGraph::Graph.fact_definitions

      squared_scale = defs[:math_facts][:squared_scale]
      expect(squared_scale.input_definitions.keys).to eq([:scale])
    end

    it "filters by module when module_filter is provided" do
      defs = FactGraph::Graph.fact_definitions([:math_facts])

      expect(defs.keys).to eq([:math_facts])
      expect(defs[:math_facts].keys).to contain_exactly(:pi, :squared_scale)
    end
  end

  context "with entity fixtures" do
    before do
      load "spec/fixtures/entities.rb"
    end

    it "represents per-entity facts as single Fact objects (not expanded)" do
      defs = FactGraph::Graph.fact_definitions

      income = defs[:applicant_facts][:income]
      expect(income).to be_a(FactGraph::Fact)
      expect(income.per_entity).to eq(:applicants)
    end

    it "sets per_entity to nil for non-entity facts" do
      defs = FactGraph::Graph.fact_definitions

      num_eligible = defs[:applicant_facts][:num_eligible_applicants]
      expect(num_eligible.per_entity).to be_nil
    end

    it "preserves per_entity input definitions on entity facts" do
      defs = FactGraph::Graph.fact_definitions

      income = defs[:applicant_facts][:income]
      expect(income.input_definitions[:income][:per_entity]).to eq(true)
    end

    it "includes cross-module entity facts" do
      defs = FactGraph::Graph.fact_definitions

      credit = defs[:credit_facts][:credit_amounts]
      expect(credit.per_entity).to eq(:applicants)
      expect(credit.dependencies).to eq({age: :applicant_facts, eligible: :applicant_facts})
    end
  end
end
