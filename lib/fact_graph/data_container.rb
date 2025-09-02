module FactGraph
  class DataContainer
    attr_writer :data_errors
    attr_accessor :data

    def initialize(data, data_errors = nil)
      @data = data
      @data_errors = data_errors
    end

    def data_errors
      @data_errors&.call || :fact_incomplete_definition
    end
  end
end
