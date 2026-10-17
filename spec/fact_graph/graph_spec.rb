# frozen_string_literal: true

RSpec.describe FactGraph::Graph do
  let(:base_graph) do
    Class.new(FactGraph::Graph) do
      in_module :limits do
        constant(:income_limit) { 30_000 }

        fact :asset_limit do
          input :household_size, value: :integer

          proc do
            data in input: {household_size:}
            household_size * 1_000
          end
        end
      end
    end
  end

  def evaluate(graph_class, input = {})
    FactGraph::Evaluator.evaluate(input, graph_class:)
  end

  it "evaluates only the facts defined on or inherited by the graph" do
    sibling_graph = Class.new(FactGraph::Graph) do
      in_module :other do
        constant(:unrelated) { true }
      end
    end

    expect(evaluate(base_graph)).not_to have_key(:other)
    expect(evaluate(sibling_graph)).to eq({other: {unrelated: true}})
  end

  it "does not register facts on FactGraph::Graph" do
    base_graph
    expect(FactGraph::Graph.graph_registry).to be_empty
  end

  context "when a graph is subclassed" do
    let(:child_graph) do
      Class.new(base_graph) do
        in_module :limits do
          constant(:income_limit) { 32_000 }
        end

        in_module :extras do
          constant(:bonus) { 100 }
        end
      end
    end

    it "inherits the parent's facts and adds its own" do
      results = evaluate(child_graph, {household_size: 3})
      expect(results[:limits][:asset_limit]).to eq 3_000
      expect(results[:extras][:bonus]).to eq 100
    end

    it "replaces an inherited fact with the same module and name" do
      expect(evaluate(child_graph)[:limits][:income_limit]).to eq 32_000
      expect(child_graph.graph_registry.count { |f| f[:name] == :income_limit }).to eq 1
    end

    it "leaves the parent unchanged" do
      child_graph
      results = evaluate(base_graph)
      expect(results[:limits][:income_limit]).to eq 30_000
      expect(results).not_to have_key(:extras)
    end

    it "drops the inherited definition entirely, including its inputs" do
      overriding_graph = Class.new(base_graph) do
        in_module :limits do
          constant(:asset_limit) { 5_000 }
        end
      end

      results = evaluate(overriding_graph)
      expect(results[:limits][:asset_limit]).to eq 5_000
      expect(FactGraph::Evaluator.input_errors(results)).to be_empty
    end

    it "sees facts added to the parent after the subclass was defined" do
      child_graph
      base_graph.in_module(:limits) { base_graph.constant(:late_addition) { :present } }
      expect(evaluate(child_graph)[:limits][:late_addition]).to eq :present
    end
  end

  it "replaces an earlier definition of the same fact within one graph" do
    graph = Class.new(FactGraph::Graph) do
      in_module :limits do
        constant(:income_limit) { 1 }
        constant(:income_limit) { 2 }
      end
    end

    expect(evaluate(graph)).to eq({limits: {income_limit: 2}})
  end
end
