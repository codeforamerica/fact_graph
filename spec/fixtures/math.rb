class SimpleFacts < FactGraph::Graph
  constant(:two) { 2 }
end

class MathFacts < FactGraph::Graph
  constant(:pi) { 3.14 }

  fact :squared_scale do
    input :scale do
      Dry::Schema.Params do
        required(:scale).value(type?: Numeric, gteq?: 0)
      end
    end

    proc do
      data in input: {scale:}
      scale * scale
    end
  end
end

class CircleFacts < FactGraph::Graph
  fact :areas do
    input :circles do
      Dry::Schema.Params do
        required(:circles).array(:hash) do
          required(:radius).value(:integer)
          optional(:color).value(:string)
        end
      end
    end

    dependency :pi, from: :math_facts
    dependency :squared_scale, from: :math_facts

    proc do
      data in input: {circles:}, dependencies: {pi:, squared_scale:}
      circles.map do |circle|
        circle in radius:
        pi * radius * radius * squared_scale
      end
    end
  end
end
