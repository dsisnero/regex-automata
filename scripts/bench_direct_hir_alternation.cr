require "../src/regex-automata"

# Measure public build_from_hir throughput on already-built HIR, excluding parsing.
iterations = ENV.fetch("ITERATIONS", "10000").to_i
runs = ENV.fetch("RUNS", "4").to_i
raise "ITERATIONS must be positive and RUNS >= 4" unless iterations > 0 && runs >= 4

cases = {
  "parsed_singletons"   => Regex::Syntax.parse("α|β|γ"),
  "parsed_literal_trie" => Regex::Syntax.parse("alpha|bravo|charlie|delta"),
  "raw_ascii"           => Regex::Syntax::Hir::Hir.new(Regex::Syntax::Hir::Alternation.new(
    %w(a b c d).map { |s| Regex::Syntax::Hir::Literal.new(s.to_slice).as(Regex::Syntax::Hir::Node) })),
  "raw_unicode" => Regex::Syntax::Hir::Hir.new(Regex::Syntax::Hir::Alternation.new(
    %w(α β γ δ).map { |s| Regex::Syntax::Hir::Literal.new(s.to_slice).as(Regex::Syntax::Hir::Node) })),
  "raw_duplicate" => Regex::Syntax::Hir::Hir.new(Regex::Syntax::Hir::Alternation.new(
    %w(☃ ☃).map { |s| Regex::Syntax::Hir::Literal.new(s.to_slice).as(Regex::Syntax::Hir::Node) })),
}
puts "case,run,iterations,elapsed_ms,states_checksum"
cases.each do |name, hir|
  compiler = Regex::Automata::NFA::NFA.compiler.configure(
    Regex::Automata::NFA::NFA.config.which_captures(Regex::Automata::NFA::WhichCaptures::None)
      .unanchored_prefix(false).shrink(false))
  runs.times do |run|
    GC.collect
    checksum = 0_i64
    started = Time.instant
    iterations.times { checksum += compiler.build_from_hir(hir).states.size }
    elapsed = (Time.instant - started).total_milliseconds
    puts "#{name},#{run},#{iterations},#{elapsed},#{checksum}"
  end
end
