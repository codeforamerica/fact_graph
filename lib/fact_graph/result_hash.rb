module FactGraph
  class ResultHash < Hash
    def self.deep_cast(value)
      case value
      when Hash
        self[value.transform_values { |v| deep_cast(v) }]
      else
        value
      end
    end

    def deconstruct_keys(keys)
      base = keys.nil? ? self : slice(*keys)
      base.transform_values { |v| unwrap(v) }
    end

    def [](key)
      unwrap(super)
    end

    private

    def unwrap(value)
      case value
      in Dry::Monads::Success(success_value)
        success_value
      else
        value
      end
    end
  end
end
