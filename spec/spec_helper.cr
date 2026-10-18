require "spec"
require "../src/regex-automata"

class Regex::Automata::Meta::Cache
  def pike_scratch_allocated_for_spec? : Bool
    !@cache.nil?
  end
end
