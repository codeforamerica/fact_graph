require "active_support/concern"

module SimpleFacts
  extend ActiveSupport::Concern

  included do
    in_module :simple_facts do
      constant(:two) { 2 }
    end
  end
end

module MathFacts
  extend ActiveSupport::Concern

  included do
    in_module :math_facts do
      constant(:pi) { 3.14 }

      fact :squared_scale do
        input :scale, type?: Numeric, gteq?: 0

        proc do
          data in input: {scale:}
          scale * scale
        end
      end
    end
  end
end

module CircleFacts
  extend ActiveSupport::Concern

  included do
    in_module :circle_facts do
      fact :areas do
        input :circles do
          required(:circles).array(:hash) do
            required(:radius).value(:integer)
            optional(:color).value(:string)
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
  end
end

class MathGraph < FactGraph::Graph
  include SimpleFacts
  include MathFacts
  include CircleFacts
end
