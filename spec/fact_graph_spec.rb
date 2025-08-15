# frozen_string_literal: true

RSpec.describe FactGraph do
  it "has a version number" do
    expect(FactGraph::VERSION).not_to be nil
  end

  let(:evaluator) { FactGraph::Evaluator.new }
  let(:results) { evaluator.evaluate(input) }

  before do
    FactGraph::Graph.graph_registry = []
  end

  context "with no facts defined" do
    context "with no input" do
      let(:input) { {} }

      it "returns an empty result" do
        expect(results).to eq({})
      end
    end

    context "with some input" do
      let(:input) { { foo: :bar } }

      it "returns an empty result" do
        expect(results).to eq({})
      end
    end
  end

  context "with facts defined" do
    before do
      load "spec/test_facts.rb"
    end

    context "with no input" do
      let(:input) { {} }
      let(:expected_result) do
        {
          math_facts: {
            squared_scale: {
              fact_bad_inputs: [
                [[:scale], "must be Numeric"]
              ],
              fact_dependency_unmet: {}
            }
          },
          circle_facts: {
            areas: {
              fact_bad_inputs: [
                [[:circles], "must be an array"]
              ],
              fact_dependency_unmet: {
                math_facts: [:squared_scale]
              }
            }
          }
        }
      end

      it "returns errors for everything" do
        expect(results).to eq(expected_result)
      end
    end

    context "with some invalid input and some missing input" do
      let(:input) { { scale: "boat" } }
      let(:expected_result) do
        {
          math_facts: {
            squared_scale: {
              fact_bad_inputs: [
                [[:scale], "must be Numeric"]
              ],
              fact_dependency_unmet: {}
            }
          },
          circle_facts: {
            areas: {
              fact_bad_inputs: [
                [[:circles], "must be an array"]
              ],
              fact_dependency_unmet: {
                math_facts: [:squared_scale]
              }
            }
          }
        }
      end

      it "returns errors for everything" do
        expect(results).to eq(expected_result)
      end
    end

    context "with some valid and some bad input" do
      let(:input) { { scale: 5 } }
      let(:expected_result) do
        {
          math_facts: {
            squared_scale: 25
          },
          circle_facts: {
            areas: {
              fact_bad_inputs: [
                [[:circles], "must be an array"]
              ],
              fact_dependency_unmet: {}
            }
          }
        }
      end

      it "returns some results & some errors" do
        expect(results).to eq(expected_result)
      end
    end

    context "with invalid nested repeated input" do
      let(:input) { { scale: 5, circles: [{ radius: "spoon" }, {}] } }
      let(:expected_result) do
        {
          math_facts: {
            squared_scale: 25
          },
          circle_facts: {
            areas: {
              fact_bad_inputs: [
                [[:circles, 0, :radius], "must be an integer"],
                [[:circles, 1, :radius], "is missing"]
              ],
              fact_dependency_unmet: {}
            }
          }
        }
      end

      it "returns some results & some errors" do
        expect(results).to eq(expected_result)
      end
    end

    context "with all valid input" do
      let(:input) { { scale: 5, circles: [{ radius: 1 }, { radius: 2 }] } }
      let(:expected_result) do
        {
          math_facts: {
            squared_scale: 25
          },
          circle_facts: {
            areas: [3.14 * 25, 3.14 * 25 * 4]
          }
        }
      end

      it "returns some results & some errors" do
        expect(results).to eq(expected_result)
      end
    end
  end
end
