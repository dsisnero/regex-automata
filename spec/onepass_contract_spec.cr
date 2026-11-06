require "./spec_helper"

# Source characterizations of pinned dfa/onepass.rs. The existing upstream
# unit/regression ports remain in dfa_onepass_spec.cr.
describe "pinned one-pass construction and search contracts" do
  it "reserves a metadata column even for a full singleton alphabet" do
    re = Regex::Automata::DFA::OnePass::DFA.builder
      .configure(Regex::Automata::DFA::OnePass::DFA.config.byte_classes(false)).build("a")
    re.alphabet_len.should eq(256)
    re.stride2.should eq(9)
    re.stride.should eq(512)
  end

  it "reports only packed table and start payload memory, excluding the retained NFA" do
    {false, true}.each do |individual_starts|
      re = Regex::Automata::DFA::OnePass::DFA.builder
        .configure(Regex::Automata::DFA::OnePass::DFA.config.starts_for_each_pattern(individual_starts))
        .build_many(["a", "b"])
      start_len = individual_starts ? 3 : 1
      re.memory_usage.should eq(re.state_len.to_i64 * re.stride * 8 + start_len * 4)
    end
  end

  it "retains the pinned anchored Unicode shape after prefix finalization" do
    re = Regex::Automata::DFA::OnePass::DFA.new("^\\w+")
    re.state_len.should eq(318)
    re.memory_usage.should eq(325_636)
  end

  it "clears retained explicit capture scratch between searches" do
    re = Regex::Automata::DFA::OnePass::DFA.new("(a)?b")
    cache = re.create_cache
    slots = Array(Int32?).new(4, nil)
    re.try_search_slots(cache, Regex::Automata::Input.new("ab").anchored(Regex::Automata::Anchored::Yes), slots)
      .should eq(Regex::Automata::PatternID.new(0))
    slots.should eq([0, 2, 0, 1])
    re.try_search_slots(cache, Regex::Automata::Input.new("b").anchored(Regex::Automata::Anchored::Yes), slots)
      .should eq(Regex::Automata::PatternID.new(0))
    slots.should eq([0, 1, nil, nil])
  end

  it "writes match-side slots to the result without altering transition scratch" do
    re = Regex::Automata::DFA::OnePass::DFA.new("(a)")
    cache = re.create_cache
    slots = Array(Int32?).new(4, nil)
    re.try_search_slots(cache, Regex::Automata::Input.new("a").anchored(Regex::Automata::Anchored::Yes), slots)
      .should eq(Regex::Automata::PatternID.new(0))
    slots.should eq([0, 1, 0, 1])
    cache.compiled_slots[1].should be_nil
  end

  it "lets an inherently anchored NFA satisfy an unanchored low-level request" do
    re = Regex::Automata::DFA::OnePass::DFA.new("^a")
    slots = Array(Int32?).new(2, nil)
    re.try_search_slots(re.create_cache, Regex::Automata::Input.new("a"), slots)
      .should eq(Regex::Automata::PatternID.new(0))
    slots.should eq([0, 1])
  end

  it "returns a done-input miss before anchor validation or slot/cache mutation" do
    re = Regex::Automata::DFA::OnePass::DFA.new("(a)")
    cache = re.create_cache
    slots = Array(Int32?).new(4, 7)
    re.try_search_slots(cache, Regex::Automata::Input.new("a").span(1...0), slots).should be_nil
    slots.should eq([7, 7, 7, 7])
    cache.compiled_slot_len.should eq(2)
  end

  it "checks size limits while adding states, before discovering conflicts" do
    error = expect_raises(Regex::Automata::DFA::OnePass::BuildError) do
      Regex::Automata::DFA::OnePass::DFA.builder
        .configure(Regex::Automata::DFA::OnePass::DFA.config.size_limit(1)).build("a*a")
    end
    error.kind.should eq(Regex::Automata::DFA::OnePass::BuildError::Kind::ExceededSizeLimit)
  end

  it "consumes explicit Dense NFA states just like ByteRange and Sparse states" do
    sid = Regex::Automata::StateID.new(1)
    targets = Array(Regex::Automata::StateID).new(256, Regex::Automata::StateID::ZERO)
    targets['a'.ord] = Regex::Automata::StateID.new(2)
    states = [Regex::Automata::NFA::Fail.new, Regex::Automata::NFA::Dense.new(targets),
              Regex::Automata::NFA::Match.new(Regex::Automata::PatternID.new(0))] of Regex::Automata::NFA::State
    nfa = Regex::Automata::NFA::NFA.new(states, sid, sid, [sid], true, false,
      Regex::Automata::GroupInfo.new([[nil] of String?]))
    re = Regex::Automata::DFA::OnePass::DFA.new_from_nfa(nfa)
    re.find(re.create_cache, "a").should eq(Regex::Automata::Match.must(0, 0, 1))
    re.find(re.create_cache, "b").should be_nil
  end

  it "merges successive Thompson configurations instead of dropping prior settings" do
    re = Regex::Automata::DFA::OnePass::DFA.builder
      .thompson(Regex::Automata::HirCompilerConfig.new.utf8(false))
      .thompson(Regex::Automata::HirCompilerConfig.new.shrink(true)).build("a*")
    re.get_nfa.is_utf8.should be_false
  end
end

describe "one-pass configuration ownership" do
  it "preserves unset options when overwriting configs" do
    unspecified = Regex::Automata::DFA::OnePass::Config.new.overwrite(Regex::Automata::DFA::OnePass::Config.new)
    builder = Regex::Automata::DFA::OnePass::DFA.builder
      .configure(Regex::Automata::DFA::OnePass::DFA.config.match_kind(Regex::Automata::MatchKind::All))
      .configure(unspecified)
    builder.build("a").get_match_kind.should eq(Regex::Automata::MatchKind::All)
  end

  it "keeps builder and DFA configuration snapshots independent" do
    builder = Regex::Automata::DFA::OnePass::DFA.builder
      .configure(Regex::Automata::DFA::OnePass::DFA.config.match_kind(Regex::Automata::MatchKind::All))
    copy = builder.clone
    copy.configure(Regex::Automata::DFA::OnePass::DFA.config.match_kind(Regex::Automata::MatchKind::LeftmostFirst))
    original = builder.build("(a)+?")
    original.find(original.create_cache, "aa").should eq(Regex::Automata::Match.must(0, 0, 2))
    copy.build("(a)+?").find(copy.build("(a)+?").create_cache, "aa").should eq(Regex::Automata::Match.must(0, 0, 1))
    cloned = original.clone
    cloned.find(cloned.create_cache, "aa").should eq(original.find(original.create_cache, "aa"))
    original.get_config.match_kind(Regex::Automata::MatchKind::LeftmostFirst)
    original.find(original.create_cache, "aa").should eq(Regex::Automata::Match.must(0, 0, 2))
    cache = original.create_cache
    cached_copy = cache.clone
    cached_copy.compiled_slots.same?(cache.compiled_slots).should be_false
  end

  it "represents size limits wider than Int32 and explicit removal" do
    config = Regex::Automata::DFA::OnePass::DFA.config.size_limit(1_i64 << 32)
    config.get_size_limit.should eq(1_i64 << 32)
    config.overwrite(Regex::Automata::DFA::OnePass::DFA.config.size_limit(nil)).get_size_limit.should be_nil
  end
end

# Private source representations are inspected within their own namespace.
module Regex::Automata::DFA::OnePass
  private class Admission
    describe "pinned one-pass packed word representations" do
      it "packs 21 state, one priority, 32 slot and ten assertion bits in eight bytes" do
        sizeof(Transition).should eq(8)
        sizeof(Epsilons).should eq(8)
        epsilons = Epsilons.new.with_slot(31).with_look(::Regex::Automata::NFA::Look::Kind::WordBoundaryUnicode)
        epsilons.bits.should eq((1_u64 << 41) | 256_u64)
        trans = Transition.new(::Regex::Automata::StateID.new((1 << 21) - 1), true, epsilons)
        trans.word.should eq((((1_u64 << 21) - 1) << 43) | (1_u64 << 42) | (1_u64 << 41) | 256_u64)
        trans.state_id.to_i.should eq((1 << 21) - 1)
        trans.match_wins?.should be_true
        trans.epsilons.bits.should eq(epsilons.bits)
        Transition.new(0_u64).state_id.should eq(::Regex::Automata::StateID::ZERO)
      end

      it "iterates set slot bits in order and truncates writes to arbitrary caller buffers" do
        epsilons = Epsilons.new(0xFFFFFFFF_u64 << 10)
        (0..35).each do |length|
          plain = Array(Int32?).new(length, nil)
          wrapped = Array(::Regex::Automata::NonMaxUsize?).new(length, nil)
          epsilons.apply_slots(plain, 17)
          epsilons.apply_slots(wrapped, 17)
          expected = (0...length).map { |index| index < 32 ? 17 : nil }
          plain.should eq(expected)
          wrapped.map { |slot| slot.try(&.get) }.should eq(expected)
        end
      end
    end
  end
end

describe "one-pass full-width captures" do
  it "resolves all 32 explicit slots and preserves result/cache separation" do
    re = ::Regex::Automata::DFA::OnePass::DFA.new("(a)" * 16)
    cache = re.create_cache
    slots = Array(Int32?).new(34, nil)
    re.try_search_slots(cache, ::Regex::Automata::Input.new("a" * 16).anchored(::Regex::Automata::Anchored::Yes), slots)
      .should eq(::Regex::Automata::PatternID.new(0))
    slots[0, 2].should eq([0, 16])
    16.times { |index| slots[2 + index * 2, 2].should eq([index, index + 1]) }
    cache.compiled_slots[31].should be_nil
  end
end

describe "one-pass fallible captures" do
  it "preserves the prior pattern marker on an error, as Rust's question-mark return does" do
    re = Regex::Automata::DFA::OnePass::DFA.new("a")
    cache = re.create_cache
    captures = re.create_captures
    re.captures(cache, "a", captures)
    result = re.try_search(cache, Regex::Automata::Input.new("a"), captures)
    result.should be_a(Regex::Automata::MatchError)
    captures.pattern.should eq(Regex::Automata::PatternID.new(0))
  end
end

describe "one-pass error clones" do
  it "retains error classification, message and cause" do
    error = expect_raises(Regex::Automata::DFA::OnePass::BuildError) do
      Regex::Automata::DFA::OnePass::DFA.new("(")
    end
    copy = error.clone
    copy.same?(error).should be_false
    copy.kind.should eq(error.kind)
    copy.message.should eq(error.message)
    copy.source.try(&.message).should eq(error.source.try(&.message))
  end
end
