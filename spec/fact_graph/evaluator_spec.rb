# frozen_string_literal: true

RSpec.describe FactGraph::Evaluator do
  before do
    FactGraph::Graph.graph_registry = []
    load "spec/fixtures/math.rb"
  end

  describe "#key_matches_key_path" do
    context "when passed a key that includes keymaps, hashes and arrays" do
      let(:key) { Dry::Schema::KeyMap["title", "artist", ["tags", ["name"]]] }

      it "returns true for a matching simple key path" do
        expect(described_class.key_matches_key_path?(key, [:title])).to be_truthy
      end

      it "returns true for a matching complex key path" do
        expect(described_class.key_matches_key_path?(key, [:tags, 0, :name])).to be_truthy
      end

      it "returns false for a non-matching simple key path" do
        expect(described_class.key_matches_key_path?(key, [:release_year])).to be_falsey
      end

      it "returns false for a non-matching complex key path" do
        expect(described_class.key_matches_key_path?(key, [:tags, 0, :creator])).to be_falsey
      end
    end
  end

  describe "#facts_using_input" do
    let(:results) { described_class.facts_using_input(query_input) }

    context "when you query for an unused input" do
      let(:query_input) { [:foo] }

      it "returns an empty array" do
        expect(results).to eq []
      end
    end

    context "when you query for a top-level simple input" do
      let(:query_input) { [:scale] }

      it "returns the correct set of facts" do
        expect(results.count).to eq 1
        expect(results[0].module_name).to eq :math_facts
        expect(results[0].name).to eq :squared_scale
      end
    end

    context "when you query for a sub-path of a structured input" do
      let(:query_input) { [:circles] }

      it "returns the correct set of facts" do
        expect(results.count).to eq 1
        expect(results[0].module_name).to eq :circle_facts
        expect(results[0].name).to eq :areas
      end
    end

    context "when you query for a fully-qualified structured input" do
      let(:query_input) { [:circles, 0, :radius] }

      it "returns the correct set of facts" do
        expect(results.count).to eq 1
        expect(results[0].module_name).to eq :circle_facts
        expect(results[0].name).to eq :areas
      end
    end
  end

  describe "#facts_with_dependency" do
    let(:results) { described_class.facts_with_dependency(query_dependency_module_name, query_dependency_fact_name) }

    context "when you query for a nonexistent module" do
      let(:query_dependency_module_name) { :foo }
      let(:query_dependency_fact_name) { :bar }

      it "returns an empty array" do
        expect(results).to eq []
      end
    end

    context "when you query for a nonexistent fact" do
      let(:query_dependency_module_name) { :math_facts }
      let(:query_dependency_fact_name) { :bar }

      it "returns an empty array" do
        expect(results).to eq []
      end
    end

    context "when you query for a fact that's not used as a dependency" do
      let(:query_dependency_module_name) { :simple_facts }
      let(:query_dependency_fact_name) { :two }

      it "returns an empty array" do
        expect(results).to eq []
      end
    end

    context "when you query for a fact that is used as a dependency" do
      let(:query_dependency_module_name) { :math_facts }
      let(:query_dependency_fact_name) { :pi }

      it "returns an empty array" do
        expect(results.count).to eq 1
        expect(results[0].module_name).to eq :circle_facts
        expect(results[0].name).to eq :areas
      end
    end
  end

  describe "#leaf_facts_depending_on_input" do
    let(:results) { described_class.leaf_facts_depending_on_input(query_input) }

    context "when you query for an unused input" do
      let(:query_input) { [:foo] }

      it "returns an empty array" do
        expect(results).to eq []
      end
    end

    context "when you query for an input used directly by a leaf fact" do
      let(:query_input) { [:circles, 0, :radius] }

      it "returns that fact" do
        expect(results.count).to eq 1
        expect(results[0].module_name).to eq :circle_facts
        expect(results[0].name).to eq :areas
      end
    end

    context "when you query for an input used transitively by a leaf fact" do
      let(:query_input) { [:scale] }

      it "returns that fact" do
        expect(results.count).to eq 1
        expect(results[0].module_name).to eq :circle_facts
        expect(results[0].name).to eq :areas
      end
    end
  end

  describe ".evaluate" do
    context "deep freezes results" do
      let(:input) { {scale: 5, circles: [{radius: 1}, {radius: 2}]} }
      let(:results) { described_class.evaluate(input) }

      it "freezes the top-level hash and all nested module hashes" do
        expect(results).to be_frozen
        results.each_value do |module_results|
          expect(module_results).to be_frozen
        end
      end

      it "freezes array fact values and their elements" do
        areas = results[:circle_facts][:areas]
        expect(areas).to be_frozen
        areas.each { |v| expect(v).to be_frozen }
      end

      it "freezes error result hashes deeply" do
        error_results = described_class.evaluate({})
        error = error_results[:math_facts][:squared_scale]
        expect(error).to be_frozen
        expect(error[:fact_bad_inputs]).to be_frozen
        expect(error[:fact_dependency_unmet]).to be_frozen
      end

      it "freezes sets and their elements within error results" do
        error_results = described_class.evaluate({})
        error_messages = error_results[:math_facts][:squared_scale][:fact_bad_inputs][[:scale]]
        expect(error_messages).to be_a(Set)
        expect(error_messages).to be_frozen
        error_messages.each { |msg| expect(msg).to be_frozen }
      end
    end
  end

  describe ".input_errors" do
    let!(:evaluation_results) { described_class.evaluate(input) }
    let(:results) { FactGraph::Evaluator.input_errors(evaluation_results) }

    context "when you evaluate with no input" do
      let(:input) { {} }

      it "returns all top-level inputs" do
        expect(results).to eq({
          [:circles] => Set.new(["must be an array"]),
          [:scale] => Set.new(["must be Numeric"])
        })
      end
    end

    context "when you evaluate with some valid input" do
      let(:input) { {scale: 5} }

      it "returns only invalid inputs" do
        expect(results).to eq({[:circles] => Set.new(["must be an array"])})
      end
    end

    context "when you evaluate with invalid structured input" do
      let(:input) { {scale: 5, circles: [{radius: "boat"}, {}]} }

      it "returns only invalid inputs" do
        expect(results).to eq({
          [:circles, 0, :radius] => Set.new(["must be an integer"]),
          [:circles, 1, :radius] => Set.new(["is missing"])
        })
      end
    end

    context "when you evaluate with valid input" do
      let(:input) { {scale: 5, circles: [{radius: 1}, {radius: 2}]} }

      it "returns an empty hash" do
        expect(results).to eq({})
      end
    end
  end
end
