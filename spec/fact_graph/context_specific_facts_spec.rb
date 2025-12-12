RSpec.describe "Context-specific facts" do
  before do
    FactGraph::Graph.graph_registry = []
    load "spec/fixtures/context_specific_facts/filer.rb"
    load "spec/fixtures/context_specific_facts/dependent.rb"
    load "spec/fixtures/context_specific_facts/ty_2024_graph.rb"
    load "spec/fixtures/context_specific_facts/ty_2025_graph.rb"
  end

  it "does" do
    expect(Ty2024Graph.prepare_fact_objects({})[:filer][:age].call({},{})).to eq 34
    expect(Ty2024Graph.prepare_fact_objects({})[:dependent][:age].call({},{})).to eq 24

    expect(Ty2025Graph.prepare_fact_objects({})[:filer][:age].call({},{})).to eq 35
    expect(Ty2025Graph.prepare_fact_objects({})[:dependent][:age].call({},{})).to eq 25

    expect(FactGraph::Evaluator.evaluate({}, graph_class: Ty2024Graph)[:filer][:age]).to eq 34
    expect(FactGraph::Evaluator.evaluate({}, graph_class: Ty2024Graph)[:dependent][:age]).to eq 24

    expect(FactGraph::Evaluator.evaluate({}, graph_class: Ty2025Graph)[:filer][:age]).to eq 35
    expect(FactGraph::Evaluator.evaluate({}, graph_class: Ty2025Graph)[:dependent][:age]).to eq 25
  end
end
