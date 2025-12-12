RSpec.describe "Context-specific facts" do
  before do
    FactGraph::Graph.graph_registry = []
    load "spec/fixtures/context_specific_facts/filer.rb"
    load "spec/fixtures/context_specific_facts/dependent.rb"
    load "spec/fixtures/context_specific_facts/ty_2024_graph.rb"
    load "spec/fixtures/context_specific_facts/ty_2025_graph.rb"
  end

  it "does" do
    puts Ty2024Graph.prepare_fact_objects({})[:dependent][:age].call({},{})
    puts Ty2024Graph.prepare_fact_objects({})[:filer][:age].call({},{})
    puts Ty2025Graph.prepare_fact_objects({})[:dependent][:age].call({},{})
    puts Ty2025Graph.prepare_fact_objects({})[:filer][:age].call({},{})
  end
end
