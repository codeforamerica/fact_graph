# frozen_string_literal: true
require "test_facts"

RSpec.describe FactGraph::Evaluator do
  describe "#facts_using_input" do
    let(:evaluator) { described_class.new }
    let(:results) { evaluator.facts_using_input(query_input) }

    context "when you query for an unused input" do
      let(:query_input) { "foo" }

      it "returns an empty array" do
        expect(results).to eq []
      end
    end

    context "when you query for a top-level simple input" do
      let(:query_input) { "scale" }

      it "returns the correct set of facts" do
        expect(results.count).to eq 1
        expect(results[0].module_name).to eq :math_facts
        expect(results[0].name).to eq :squared_scale
      end
    end

    context "when you query for a sub-path of a structured input" do
      let(:query_input) { "circles" }

      it "returns the correct set of facts" do
        expect(results.count).to eq 1
        expect(results[0].module_name).to eq :circle_facts
        expect(results[0].name).to eq :areas
      end
    end

    context "when you query for a fully-qualified structured input" do
      let(:query_input) { "circles[].radius" }

      it "returns the correct set of facts" do
        expect(results.count).to eq 1
        expect(results[0].module_name).to eq :circle_facts
        expect(results[0].name).to eq :areas
      end
    end
  end

  describe "#facts_with_dependency" do
    let(:evaluator) { described_class.new }
    let(:results) { evaluator.facts_with_dependency(query_dependency_module_name, query_dependency_fact_name) }

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
    let(:evaluator) { described_class.new }
    let(:results) { evaluator.leaf_facts_depending_on_input(query_input) }

    context "when you query for an unused input" do
      let(:query_input) { "foo" }

      it "returns an empty array" do
        expect(results).to eq []
      end
    end

    context "when you query for an input used directly by a leaf fact" do
      let(:query_input) { "circles[].radius" }

      it "returns that fact" do
        expect(results.count).to eq 1
        expect(results[0].module_name).to eq :circle_facts
        expect(results[0].name).to eq :areas
      end
    end

    context "when you query for an input used transitively by a leaf fact" do
      let(:query_input) { "scale" }

      it "returns that fact" do
        expect(results.count).to eq 1
        expect(results[0].module_name).to eq :circle_facts
        expect(results[0].name).to eq :areas
      end
    end
  end
end
