require "active_support/concern"

module Filer
  extend ActiveSupport::Concern

  included do
    in_module :filer do
      constant(:year_of_birth) { 1990 } # imagine this takes an input

      fact :age do
        dependency :tax_year, from: :filing_context
        dependency :year_of_birth

        proc do
          data in { dependencies: { tax_year:, year_of_birth: } }
          tax_year - year_of_birth
        end
      end
    end
  end
end
