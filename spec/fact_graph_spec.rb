# frozen_string_literal: true

RSpec.describe FactGraph do
  it "has a version number" do
    expect(FactGraph::VERSION).not_to be nil
  end

  let(:evaluator) { FactGraph::Evaluator.new }
  let(:results) { evaluator.evaluate(input) }

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
    let!(:math_facts) do
      class MathFacts < FactGraph::Graph
        constant(:pi) { 3.14 }

        fact :squared_scale do
          input :scale do |val|
            val => Numeric
          end
          proc do
            data in input: { scale: }
            scale * scale
          end
        end
      end
    end

    let!(:circle_facts) do
      class CircleFacts < FactGraph::Graph
        fact :areas do
          input :circles, :radius do |val|
            val => 0..
          end
          dependency :pi, from: :math_facts
          dependency :squared_scale, from: :math_facts

          proc do
            puts data
            data in input: { circles: }, dependencies: { pi:, squared_scale: }
            circles.map do |circle|
              circle in radius:
              pi * radius * radius * squared_scale
            end
          end
        end
      end
    end

    context "with no input" do
      let(:input) { {} }
      let(:expected_result) do
        {
          math_facts: {
            squared_scale: {
              fact_bad_inputs: [{ name: :scale }],
              fact_dependency_unmet: {}
            }
          },
          circle_facts: {
            areas: {
              fact_bad_inputs: [{ name: :circles }],
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
              fact_bad_inputs: [{ name: :scale }],
              fact_dependency_unmet: {}
            }
          },
          circle_facts: {
            areas: {
              fact_bad_inputs: [{ name: :circles }],
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
              fact_bad_inputs: [{ name: :circles }],
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
                { name: :circles, attribute_name: :radius, index: 0 },
                { name: :circles, attribute_name: :radius, index: 1 }
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
