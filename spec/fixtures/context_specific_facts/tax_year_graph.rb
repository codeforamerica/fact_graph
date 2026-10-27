# Facts shared by every tax year. Each year subclasses this directly rather
# than inheriting from another year.
class TaxYearGraph < FactGraph::Graph
  include Filer
  include Dependent
end
