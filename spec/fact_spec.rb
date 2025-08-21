# frozen_string_literal: true

RSpec.describe FactGraph::Fact do
  before do
    FactGraph::Graph.graph_registry = []
    load "spec/fixtures/contact_info.rb"
  end

  describe "#call" do
    context "when called with structured input that contains more fields than are required by a fact" do
      let(:input) do
        {
          street_address: {
            street_number: 1,
            street_name: "Sesame St",
            city: "New York",
            state: "New York",
            zip_code: "10123",
            county: "New York"
          }
        }
      end
      let(:evaluator) { FactGraph::Evaluator.new }

      it "filters that input before passing it to #validate_input" do
        expect(evaluator.graph[:contact_info][:formatted_address]).to receive(:validate_input).with(
          {
            street_address: {
              street_number: 1,
              street_name: "Sesame St",
              city: "New York",
              state: "New York",
              zip_code: "10123"
            }
          }
        )
        evaluator.evaluate(input)
      end
    end
  end
end
