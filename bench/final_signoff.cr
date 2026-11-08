# Shared public-API workloads: copied unchanged into the phase-7 baseline.
require "../src/regex-automata"
alias RA = Regex::Automata

CHECK      = ARGV.includes?("--check")
ALLOC_ONLY = ARGV.includes?("--alloc")
DURATION   = ENV.fetch("BENCH_MS", "150").to_i.milliseconds
SAMPLES    = ENV.fetch("BENCH_SAMPLES", "5").to_i
SIZE       = ENV.fetch("BENCH_SIZE", "65536").to_i
raise "invalid benchmark parameters" unless DURATION > Time::Span.zero && SAMPLES >= 4 && SIZE >= 256

def measure(name : String, expected : UInt64, &operation : -> UInt64)
  actual = operation.call
  raise "#{name}: #{actual} != #{expected}" unless actual == expected
  if CHECK
    puts "#{name}\t#{actual}"
    return
  end
  if ALLOC_ONLY
    GC.collect
    bytes_before = GC.stats.total_bytes
    16.times { raise "unstable allocation probe" unless operation.call == expected }
    puts "#{name}\t#{GC.stats.total_bytes - bytes_before}\t16"
    return
  end
  SAMPLES.times do |sample|
    # The first sample is emitted, explicitly cold, and excluded by analysis.
    iterations = 0_u64
    checksum = 0_u64
    started = Time.instant
    loop do
      16.times { checksum &+= operation.call }
      iterations += 16
      break if Time.instant - started >= DURATION
    end
    elapsed = Time.instant - started
    raise "unstable result" unless checksum == expected &* iterations
    GC.collect
    bytes_before = GC.stats.total_bytes
    16.times { raise "unstable allocation probe" unless operation.call == expected }
    allocated = GC.stats.total_bytes - bytes_before
    puts "#{name}\t#{sample}\t#{iterations}\t#{elapsed.total_nanoseconds.to_i64}\t#{allocated}\t16\t#{checksum}"
  end
end

(1..3).each do |count|
  needles = ["x", "y", "z"].first(count)
  pre = RA::Prefilter.new(RA::MatchKind::LeftmostFirst, needles).not_nil!
  {false, true}.each do |hit|
    hay = ("a" * SIZE + (hit ? needles.last : "a")).to_slice
    span = RA::Span.new(0, hay.size)
    measure("byte#{count}-#{hit ? "hit" : "miss"}", hit ? hay.size.to_u64 : 0_u64) { pre.find(hay, span).try(&.end.to_u64) || 0_u64 }
  end
end
{"short" => "rareXYZ", "long" => "a" * 127 + "b", "periodic" => "ab" * 63 + "ac"}.each do |label, needle|
  pre = RA::Prefilter.new(RA::MatchKind::LeftmostFirst, [needle]).not_nil!
  {false, true}.each do |hit|
    prefix = label == "periodic" ? "ab" * (SIZE // 2) : "a" * SIZE
    hay = (prefix + (hit ? needle : "")).to_slice
    span = RA::Span.new(0, hay.size)
    measure("memmem-#{label}-#{hit ? "hit" : "miss"}", hit ? hay.size.to_u64 : 0_u64) { pre.find(hay, span).try(&.end.to_u64) || 0_u64 }
  end
end
{2, 16, 65}.each do |count|
  needles = Array(String).new(count) { |i| "key#{i.to_s.rjust(3, '0')}Z" }
  pre = RA::Prefilter.new(RA::MatchKind::LeftmostFirst, needles).not_nil!
  hay = ("a" * SIZE + needles.last).to_slice
  span = RA::Span.new(0, hay.size)
  measure("teddy#{count}", hay.size.to_u64) { pre.find(hay, span).try(&.end.to_u64) || 0_u64 }
end
meta = RA::Meta::Regex.new("[a-z]+[0-9]+")
input = RA::Input.new("abc123")
cache = meta.create_cache
measure("meta-pool", 6_u64) { meta.search_half(input).try(&.offset.to_u64) || 0_u64 }
measure("meta-cache", 6_u64) { meta.search_half_with(cache, input).try(&.offset.to_u64) || 0_u64 }
config = RA::DFA::Config.new.accelerate(false)
dfa = RA::DFA::Builder.new.configure(config).build("[a-z]+Z")
input = RA::Input.new("a" * SIZE + "Z")
measure("dense-scalar-loop", input.end.to_u64) do
  result = dfa.try_search_fwd(input)
  raise "unexpected search error" if result.is_a?(RA::MatchError)
  result.try(&.offset.to_u64) || 0_u64
end
reverse = RA::DFA::Builder.new.configure(config).thompson { |th| th.reverse(true) }.build("[a-z]+Z")
measure("dense-reverse-loop", 1_u64) do
  result = reverse.try_search_rev(input)
  raise "unexpected reverse search error" if result.is_a?(RA::MatchError)
  result.try { |mat| mat.offset.to_u64 + 1_u64 } || 0_u64
end
nfa = RA::HirCompiler.new.build("(?:(?:ab|ac|ad)+[0-9]{1,4}|(?:foo|bar|baz)+x)")
measure("dense-build", 1_u64) { RA::DFA::Builder.from_nfa(nfa).build.pattern_len.to_u64 }
