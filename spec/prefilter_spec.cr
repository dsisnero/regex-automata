require "./spec_helper"

describe Regex::Automata::Prefilter do
  # aho-corasick 1.1.4 src/tests.rs: leftmost300/310/340/350/360,
  # leftfirst000/020/100/110/300/330/400 and aleftfirst020/400.
  # Inert suffixes force regex-automata's >64-literal
  # fallback so this tests its DFA instead of packed Teddy.
  it "ports pinned leftmost-first DFA candidates and anchored starts" do
    kind = Regex::Automata::MatchKind::LeftmostFirst
    cases = [
      {["ab", "abcd"], "abcd", {0, 0, 2}},
      {["abcd", "ab"], "abcd", {0, 0, 4}},
      {["abcdefg", "bcde", "bcdef"], "abcdef", {1, 1, 5}},
      {["abcdefg", "bcdef", "bcde"], "abcdef", {1, 1, 6}},
      {["abcd", "b", "bce"], "abce", {1, 1, 2}},
      {["wise", "samwise", "sam"], "samwix", {2, 0, 3}},
      {["abcd", "bce", "b"], "abce", {1, 1, 4}},
      {["abcd", "ce", "bc"], "abce", {2, 1, 3}},
      {["bce", "cz", "bc"], "bcz", {2, 0, 2}},
      {["abc", "bd", "ab"], "abd", {2, 0, 2}},
      {["abcdefghi", "hz", "abcdefgh"], "abcdefghz", {2, 0, 8}},
      {["a", "abab"], "abab", {0, 0, 1}},
      {["amwix", "samwise", "sam"], "Zsamwix", {2, 1, 4}},
    ]
    cases.each do |needles, haystack, expected|
      padded = needles + (0..64).map { |n| "unused-#{n}-Q" }
      pre = Regex::Automata::Prefilter.new(kind, padded).not_nil!
      pre.strategy_name.should eq("aho-corasick")
      pre.aho_backend_name.should eq("dfa")
      bytes = haystack.to_slice
      span = Regex::Automata::Span.new(0, bytes.size)
      pre.find_with_index(bytes, span).should eq(
        {expected[0], Regex::Automata::Span.new(expected[1], expected[2])}
      )
      anchored = pre.prefix_with_index(bytes, span)
      anchored.should eq(expected[1] == 0 ? {expected[0], Regex::Automata::Span.new(expected[1], expected[2])} : nil)
    end
  end

  it "uses the same pinned DFA for Teddy's anchored prefix search" do
    pre = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      ["abcd", "ab", "bc"]
    ).not_nil!
    pre.strategy_name.should eq("teddy")
    pre.aho_backend_name.should eq("dfa")
    bytes = "zabcd".to_slice
    pre.prefix_with_index(bytes, Regex::Automata::Span.new(0, 5)).should be_nil
    pre.prefix_with_index(bytes, Regex::Automata::Span.new(1, 5)).should eq(
      {0, Regex::Automata::Span.new(1, 5)}
    )
  end

  it "keeps the pinned 500/501 DFA boundary and binary bounded candidates" do
    kind = Regex::Automata::MatchKind::All
    base = (0...498).map { |n| "unused-#{n}-Q".to_slice }
    five_hundred = Regex::Automata::Prefilter.new(
      kind, base + [Bytes[0_u8, 255_u8], Bytes[255_u8]]
    ).not_nil!
    five_hundred.aho_backend_name.should eq("dfa")
    bytes = Bytes[44_u8, 0_u8, 255_u8, 44_u8, 255_u8]
    five_hundred.find_with_index(bytes, Regex::Automata::Span.new(0, 3)).should eq(
      {498, Regex::Automata::Span.new(1, 3)}
    )
    five_hundred.find_with_index(bytes, Regex::Automata::Span.new(2, 5)).should eq(
      {499, Regex::Automata::Span.new(2, 3)}
    )
    five_hundred.prefix_with_index(bytes, Regex::Automata::Span.new(1, 3)).should eq(
      {498, Regex::Automata::Span.new(1, 3)}
    )
    five_hundred.prefix_with_index(bytes, Regex::Automata::Span.new(0, 3)).should be_nil

    five_hundred_one = Regex::Automata::Prefilter.new(
      kind, base + [Bytes[0_u8, 255_u8], Bytes[255_u8], "last".to_slice]
    ).not_nil!
    five_hundred_one.aho_backend_name.should eq("contiguous-nfa")
    # Pinned regex-automata 0.4.18 oracle for bounded binary searches.
    five_hundred_one.find_with_index(bytes, Regex::Automata::Span.new(0, 3)).should eq(
      {498, Regex::Automata::Span.new(1, 3)}
    )
    five_hundred_one.find_with_index(bytes, Regex::Automata::Span.new(2, 5)).should eq(
      {499, Regex::Automata::Span.new(2, 3)}
    )
    five_hundred_one.prefix_with_index(bytes, Regex::Automata::Span.new(1, 3)).should eq(
      {498, Regex::Automata::Span.new(1, 3)}
    )
    five_hundred_one.prefix_with_index(bytes, Regex::Automata::Span.new(0, 3)).should be_nil
  end

  # aho-corasick 1.1.4 src/tests.rs: leftfirst000/020/100/110/300 and
  # aleftfirst020/400, under the contiguous-NFA LeftmostFirst configurations.
  # Inert suffixes force the regex-automata wrapper's >500-needle choice.
  it "ports pinned contiguous NFA leftmost and anchored candidates" do
    cases = [
      {["ab", "abcd"], "abcd", {0, 0, 2}},
      {["abcd", "ab"], "abcd", {0, 0, 4}},
      {["abcdefg", "bcde", "bcdef"], "abcdef", {1, 1, 5}},
      {["abcdefg", "bcdef", "bcde"], "abcdef", {1, 1, 6}},
      {["abcd", "b", "bce"], "abce", {1, 1, 2}},
      {["wise", "samwise", "sam"], "samwix", {2, 0, 3}},
    ]
    padding = (0..500).map { |n| "unused-#{n}-Q" }
    cases.each do |needles, haystack, expected|
      pre = Regex::Automata::Prefilter.new(
        Regex::Automata::MatchKind::LeftmostFirst, needles + padding
      ).not_nil!
      pre.aho_backend_name.should eq("contiguous-nfa")
      bytes = haystack.to_slice
      span = Regex::Automata::Span.new(0, bytes.size)
      pre.find_with_index(bytes, span).should eq(
        {expected[0], Regex::Automata::Span.new(expected[1], expected[2])}
      )
      pre.prefix_with_index(bytes, span).should eq(expected[1] == 0 ? {expected[0], Regex::Automata::Span.new(expected[1], expected[2])} : nil)
    end
  end

  it "reports the pinned contiguous NFA memory for a 501-needle prefix family" do
    needles = (0..500).map { |n| "prefix-#{n}" }
    pre = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst, needles
    ).not_nil!
    pre.aho_backend_name.should eq("contiguous-nfa")
    # Rust regex-automata 0.4.18 + aho-corasick 1.1.4, no nested prefilter.
    pre.memory_usage.should eq(2772)
    haystack = "xxx-prefix-64-alpha".to_slice
    pre.find(haystack, Regex::Automata::Span.new(0, haystack.size)).should eq(
      Regex::Automata::Span.new(4, 12)
    )
  end

  # Rust regex-automata 0.4.18 + aho-corasick 1.1.4 on AArch64 NEON;
  # x86 slim AVX2 stores one additional verifier bucket-ID copy (+8 bytes).
  # These include packed pattern/Rabin-Karp/Teddy storage and the anchored
  # DFA for Teddy, not merely the Crystal transition table.
  it "reports pinned Teddy and DFA strategy memory" do
    kind = Regex::Automata::MatchKind::LeftmostFirst
    teddy = Regex::Automata::Prefilter.new(kind, ["alpha", "beta"]).not_nil!
    teddy.strategy_name.should eq("teddy")
    avx2_extra = Regex::Automata::TeddyMatcher.backend_for(2, 4) == :slim_avx2 ? 8 : 0
    teddy.memory_usage.should eq(2537 + avx2_extra)

    short = Regex::Automata::Prefilter.new(kind, ["ab", "bc"]).not_nil!
    short.strategy_name.should eq("teddy")
    short.memory_usage.should eq(1956 + avx2_extra)

    aho = Regex::Automata::Prefilter.new(
      kind, (0..64).map { |n| "prefix-#{n}" }
    ).not_nil!
    aho.aho_backend_name.should eq("dfa")
    aho.memory_usage.should eq(5684)
  end

  # aho-corasick 1.1.4 packed/teddy/builder.rs::Builder::build_imp.
  it "selects the pinned x86 and AArch64 Teddy variants" do
    teddy = Regex::Automata::TeddyMatcher
    teddy.backend_for(32, 4, neon: false, ssse3: true, avx2: true).should eq(:slim_avx2)
    teddy.backend_for(33, 4, neon: false, ssse3: true, avx2: true).should eq(:fat_avx2)
    teddy.backend_for(33, 4, neon: false, ssse3: true, avx2: false).should eq(:slim_ssse3)
    teddy.backend_for(2, 4, neon: false, ssse3: true, avx2: true, only_256bit: false).should eq(:slim_ssse3)
    teddy.backend_for(2, 4, neon: false, ssse3: true, avx2: false, only_256bit: true).should be_nil
    teddy.backend_for(17, 1, neon: false, ssse3: true, avx2: true).should be_nil
    teddy.backend_for(2, 4, neon: false, ssse3: false, avx2: false).should be_nil
    teddy.backend_for(17, 1, neon: true, ssse3: false, avx2: false).should eq(:slim_neon)
    teddy.backend_for(65, 4, neon: true, ssse3: false, avx2: false).should be_nil
    teddy.memory_usage_for(2, 9, :slim_neon).should eq(1641)
    teddy.memory_usage_for(2, 9, :slim_ssse3).should eq(1641)
    teddy.memory_usage_for(2, 9, :slim_avx2).should eq(1649)
    teddy.memory_usage_for(2, 9, :fat_avx2).should eq(1641)
  end

  # aho-corasick 1.1.4 packed/tests.rs::teddy010/020 variation matrix
  # exercises slim vectors; this case also crosses the 32-pattern AVX2 fat
  # boundary and checks a late verifier bucket after an unmatched prefix.
  it "finds bounded fat AVX2 candidates after an unmatched prefix" do
    if Regex::Automata::TeddyMatcher.backend_for(33, 3) == :fat_avx2
      needles = (0..32).map { |n| "q#{n.to_s.rjust(2, '0')}" }
      pre = Regex::Automata::Prefilter.new(Regex::Automata::MatchKind::LeftmostFirst, needles).not_nil!
      haystack = ("z" * 80 + "q99" + "z" * 17 + "q32").to_slice
      pre.find_with_index(haystack, Regex::Automata::Span.new(0, haystack.size)).should eq(
        {32, Regex::Automata::Span.new(100, 103)}
      )
      pre.find_with_index(haystack, Regex::Automata::Span.new(0, 100)).should be_nil
      pre.prefix_with_index(haystack, Regex::Automata::Span.new(100, 103)).should eq(
        {32, Regex::Automata::Span.new(100, 103)}
      )
    end
  end

  # aho-corasick 1.1.4 packed/tests.rs::search_teddy_ssse3_leftmost_first
  # forces the 128-bit path even on an AVX2 host.
  it "runs the pinned Teddy SSSE3 search path on x86" do
    if LibTeddyNative.capabilities & 2 != 0
      needles = %w(ab bc cd de ef fg gh hi ij jk kl).map(&.to_slice)
      matcher = Regex::Automata::TeddyMatcher.new(needles, only_256bit: false)
      haystack = ("Z" * 31 + "abcdefghijk" + "Z" * 17).to_slice
      matcher.find(haystack, Regex::Automata::Span.new(0, haystack.size)).should eq(
        {0, Regex::Automata::Span.new(31, 33)}
      )
      matcher.find(haystack, Regex::Automata::Span.new(33, haystack.size)).should eq(
        {2, Regex::Automata::Span.new(33, 35)}
      )
    end
  end

  # Rust's Aho automata retain lengths, ByteSet retains membership bits,
  # while Teddy keeps its packed patterns for verification and Rabin-Karp.
  it "releases original needle bytes when the selected Rust strategy does" do
    kind = Regex::Automata::MatchKind::LeftmostFirst
    aho = Regex::Automata::Prefilter.new(kind, (0..64).map { |n| "prefix-#{n}" }).not_nil!
    aho.retained_needle_bytes.should eq(0)
    byte_set = Regex::Automata::Prefilter.new(kind, (0..64).map { |n| Bytes[n.to_u8] }).not_nil!
    byte_set.retained_needle_bytes.should eq(0)
    teddy = Regex::Automata::Prefilter.new(kind, ["alpha", "beta"]).not_nil!
    teddy.retained_needle_bytes.should eq(9)
  end

  it "feeds contiguous-NFA candidates to the dense, hybrid, NFA, and Meta consumers" do
    needles = ["foo", "bar"] + (0..500).map { |n| "unused-#{n}-Q" }
    pre = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst, needles
    ).not_nil!
    pre.aho_backend_name.should eq("contiguous-nfa")
    pattern = "(foo|bar)[a-z]+"
    haystack = "foo1 barfox bar"
    expected = Regex::Automata::Match.must(0, 5...11)

    dense = Regex::Automata::DFA::Regex.builder
      .dense(Regex::Automata::DFA::DFA.config.prefilter(pre))
      .build(pattern)
    dense.find(haystack).should eq(expected)

    hybrid = Regex::Automata::Hybrid::Regex.builder
      .dfa(Regex::Automata::Hybrid::DFA.config.prefilter(pre))
      .build(pattern)
    hybrid.find(hybrid.create_cache, haystack).should eq(expected)

    pike = Regex::Automata::NFA::PikeVM.builder
      .configure(Regex::Automata::NFA::PikeVM.config.prefilter(pre))
      .build(pattern)
    pike.find(pike.create_cache, haystack).should eq(expected)

    backtrack = Regex::Automata::NFA::Backtrack::BoundedBacktracker.builder
      .configure(Regex::Automata::NFA::Backtrack::BoundedBacktracker.config.prefilter(pre))
      .build(pattern)
    backtrack.try_find(backtrack.create_cache, haystack).should eq(expected)

    meta = Regex::Automata::Meta::Regex.builder
      .configure(Regex::Automata::Meta::Regex.config.prefilter(pre))
      .build(pattern)
    meta.find(haystack).should eq(expected)
  end

  it "feeds packed Teddy candidates through every prefilter consumer" do
    pre = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst, ["foo", "bar"]
    ).not_nil!
    pre.strategy_name.should eq("teddy")
    pattern = "(foo|bar)[a-z]+"
    haystack = "foo1 barfox bar"
    expected = Regex::Automata::Match.must(0, 5...11)

    dense = Regex::Automata::DFA::Regex.builder
      .dense(Regex::Automata::DFA::DFA.config.prefilter(pre))
      .build(pattern)
    dense.find(haystack).should eq(expected)

    hybrid = Regex::Automata::Hybrid::Regex.builder
      .dfa(Regex::Automata::Hybrid::DFA.config.prefilter(pre))
      .build(pattern)
    hybrid.find(hybrid.create_cache, haystack).should eq(expected)

    pike = Regex::Automata::NFA::PikeVM.builder
      .configure(Regex::Automata::NFA::PikeVM.config.prefilter(pre))
      .build(pattern)
    pike.find(pike.create_cache, haystack).should eq(expected)

    backtrack = Regex::Automata::NFA::Backtrack::BoundedBacktracker.builder
      .configure(Regex::Automata::NFA::Backtrack::BoundedBacktracker.config.prefilter(pre))
      .build(pattern)
    backtrack.try_find(backtrack.create_cache, haystack).should eq(expected)

    meta = Regex::Automata::Meta::Regex.builder
      .configure(Regex::Automata::Meta::Regex.config.prefilter(pre))
      .build(pattern)
    meta.find(haystack).should eq(expected)
  end

  # Rust's Choice::new probes these in order; >64 literals force Teddy to
  # decline and exercise the ByteSet/Aho-Corasick fallback paths.
  it "selects the pinned Rust scalar and fallback strategies" do
    kind = Regex::Automata::MatchKind::LeftmostFirst
    one = Regex::Automata::Prefilter.new(kind, ["x"]).not_nil!
    one.strategy_name.should eq("memchr")
    one.memory_usage.should eq(0)
    one.is_fast.should be_true

    two = Regex::Automata::Prefilter.new(kind, ["x", "y"]).not_nil!
    two.strategy_name.should eq("memchr2")
    two.memory_usage.should eq(0)
    three = Regex::Automata::Prefilter.new(kind, ["x", "y", "z"]).not_nil!
    three.strategy_name.should eq("memchr3")
    three.memory_usage.should eq(0)

    substring = Regex::Automata::Prefilter.new(kind, ["needle"]).not_nil!
    substring.strategy_name.should eq("memmem")
    substring.memory_usage.should eq(6)
    substring.is_fast.should be_true

    bytes = (0..64).map { |n| Bytes[128_u8 + n.to_u8] }
    byte_set = Regex::Automata::Prefilter.new(kind, bytes).not_nil!
    byte_set.strategy_name.should eq("byteset")
    byte_set.memory_usage.should eq(0)
    byte_set.is_fast.should be_false

    many = (0..64).map { |n| "prefix-#{n}" }
    aho = Regex::Automata::Prefilter.new(kind, many).not_nil!
    aho.strategy_name.should eq("aho-corasick")
    aho.is_fast.should be_false
    aho.memory_usage.should be > 0
  end

  it "keeps byte-set and Aho candidates inside spans with leftmost priority" do
    kind = Regex::Automata::MatchKind::All
    byte_set = Regex::Automata::Prefilter.new(
      kind, (0..64).map { |n| Bytes[128_u8 + n.to_u8] }
    ).not_nil!
    hay = Bytes[0_u8, 129_u8, 130_u8, 0_u8]
    byte_set.find(hay, Regex::Automata::Span.new(2, 4)).should eq(
      Regex::Automata::Span.new(2, 3)
    )
    byte_set.prefix(hay, Regex::Automata::Span.new(0, 4)).should be_nil
    byte_set.prefix(hay, Regex::Automata::Span.new(1, 2)).should eq(
      Regex::Automata::Span.new(1, 2)
    )

    needles = (0..62).map { |n| "unused-#{n}" } + ["abc", "b"]
    aho = Regex::Automata::Prefilter.new(kind, needles).not_nil!
    aho.find("abc".to_slice, Regex::Automata::Span.new(0, 3)).should eq(
      Regex::Automata::Span.new(0, 3)
    )
    aho.find("abc".to_slice, Regex::Automata::Span.new(1, 3)).should eq(
      Regex::Automata::Span.new(1, 2)
    )
  end

  it "finds the earliest candidate and preserves leftmost-first tie order" do
    haystack = "Hello samwise".to_slice
    span = Regex::Automata::Span.new(0, haystack.size)

    pre = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      ["samwise", "sam"]
    ).not_nil!
    pre.find(haystack, span).should eq(Regex::Automata::Span.new(6, 13))

    reversed = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      ["sam", "samwise"]
    ).not_nil!
    reversed.find(haystack, span).should eq(Regex::Automata::Span.new(6, 9))
  end

  it "matches prefixes anchored at the start of the search span" do
    haystack = "Hello Bruce Springsteen!".to_slice
    pre = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      ["Bruce ", "Patti "]
    ).not_nil!

    pre.prefix(haystack, Regex::Automata::Span.new(0, haystack.size)).should be_nil
    pre.prefix(haystack, Regex::Automata::Span.new(6, haystack.size)).should eq(
      Regex::Automata::Span.new(6, 12)
    )
  end

  it "never returns a candidate outside the supplied search span" do
    haystack = "needle...needle".to_slice
    pre = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      ["needle"]
    ).not_nil!

    pre.find(haystack, Regex::Automata::Span.new(1, 9)).should be_nil
    pre.find(haystack, Regex::Automata::Span.new(1, haystack.size)).should eq(
      Regex::Automata::Span.new(9, 15)
    )
    pre.prefix(haystack, Regex::Automata::Span.new(1, haystack.size)).should be_nil

    byte = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::All,
      ["."]
    ).not_nil!
    byte.find(haystack, Regex::Automata::Span.new(0, 6)).should be_nil
    byte.find(haystack, Regex::Automata::Span.new(0, 10)).should eq(
      Regex::Automata::Span.new(6, 7)
    )
  end

  it "extracts prefix literals from HIRs" do
    hir = Regex::Syntax.parse("(Bruce|Patti) \\w+")
    pre = Regex::Automata::Prefilter.from_hir_prefix(
      Regex::Automata::MatchKind::LeftmostFirst,
      hir
    ).not_nil!

    haystack = "Hello Patti Scialfa!".to_slice
    pre.find(haystack, Regex::Automata::Span.new(0, haystack.size)).should eq(
      Regex::Automata::Span.new(6, 12)
    )
    pre.max_needle_len.should eq(6)
    pre.memory_usage.should be > 0
  end

  it "extracts and optimizes prefixes across multiple HIRs" do
    hirs = [
      Regex::Syntax.parse("(Bruce|Patti) \\w+"),
      Regex::Syntax.parse("Mrs?\\. Doubtfire"),
    ]

    pre = Regex::Automata::Prefilter.from_hirs_prefix(
      Regex::Automata::MatchKind::LeftmostFirst,
      hirs
    ).not_nil!

    haystack = "Hello Mrs. Doubtfire".to_slice
    pre.find(haystack, Regex::Automata::Span.new(0, haystack.size)).should eq(
      Regex::Automata::Span.new(6, 20)
    )
  end

  it "rejects empty needle sets and empty-prefix literal extractions" do
    Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      [] of String
    ).should be_nil

    Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      [""]
    ).should be_nil

    empty_hir = Regex::Syntax.parse("a*")
    Regex::Automata::Prefilter.from_hir_prefix(
      Regex::Automata::MatchKind::LeftmostFirst,
      empty_hir
    ).should be_nil
  end

  it "marks tiny single-byte and short multi-substring sets as fast" do
    fast = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::All,
      ["a", "b", "c"]
    ).not_nil!
    fast.is_fast.should be_true
    fast.find("zzcbax".to_slice, Regex::Automata::Span.new(0, 6)).should eq(
      Regex::Automata::Span.new(2, 3)
    )

    multi = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::All,
      ["alpha", "beta"]
    ).not_nil!
    multi.strategy_name.should eq("teddy")
    multi.is_fast.should be_true
  end

  # aho-corasick 1.1.4 src/packed/tests.rs teddy010 and teddy020, reached
  # through regex-automata's pinned Teddy prefilter selection.
  it "ports packed Teddy's byte and two-byte offset cases" do
    kind = Regex::Automata::MatchKind::LeftmostFirst
    one_byte = ('a'..'k').map(&.to_s)
    one = Regex::Automata::Prefilter.new(kind, one_byte).not_nil!
    one.strategy_name.should eq("teddy")
    one.is_fast.should be_false
    haystack = "Z" * 19 + "abcdefghijk" + "Z" * 19
    one_byte.each_index do |i|
      at = 19 + i
      one.find_with_index(haystack.to_slice, Regex::Automata::Span.new(at, haystack.bytesize)).should eq(
        {i, Regex::Automata::Span.new(at, at + 1)}
      )
    end

    two_byte = %w(ab bc cd de ef fg gh hi ij jk kl)
    two = Regex::Automata::Prefilter.new(kind, two_byte).not_nil!
    two.strategy_name.should eq("teddy")
    two.is_fast.should be_false
    short = "abcdefghijk".to_slice
    two.find_with_index(short, Regex::Automata::Span.new(0, short.size)).should eq(
      {0, Regex::Automata::Span.new(0, 2)}
    )
    long = ("Z" * 19 + "abcdefghijk" + "Z" * 19).to_slice
    two.find_with_index(long, Regex::Automata::Span.new(19, 30)).should eq(
      {0, Regex::Automata::Span.new(19, 21)}
    )
    two.find_with_index(long, Regex::Automata::Span.new(20, 30)).should eq(
      {1, Regex::Automata::Span.new(20, 22)}
    )
  end

  it "uses the pinned architecture-specific Teddy admission boundary" do
    kind = Regex::Automata::MatchKind::LeftmostFirst
    # aho-corasick 1.1.4's AArch64 builder logs a >16 one-byte warning but
    # still returns SlimNeon; the actual hard limit is >64 patterns.
    seventeen = (0..16).map { |n| Bytes[64_u8 + n.to_u8] }
    expected = Regex::Automata::TeddyMatcher.backend_for(17, 1) ? "teddy" : "aho-corasick"
    Regex::Automata::Prefilter.new(kind, seventeen).not_nil!.strategy_name.should eq(expected)
    sixty_five = (0..64).map { |n| Bytes[64_u8 + n.to_u8] }
    Regex::Automata::Prefilter.new(kind, sixty_five).not_nil!.strategy_name.should eq("byteset")
  end

  # The dependency's SearchTest::variations loops over 0..260 offsets and
  # tests prefix, suffix, and both for teddy010/teddy020.
  it "ports the full Teddy 261-offset variation matrix" do
    kind = Regex::Automata::MatchKind::LeftmostFirst
    cases = [
      {('a'..'k').map(&.to_s), (0..10).map { |i| {i.to_i32, i.to_i32, (i + 1).to_i32} }},
      {"ab bc cd de ef fg gh hi ij jk kl".split, (0..4).map { |i| {(i * 2).to_i32, (i * 2).to_i32, (i * 2 + 2).to_i32} }},
    ]
    cases.each do |needles, expected|
      pre = Regex::Automata::Prefilter.new(kind, needles).not_nil!
      (0..260).each do |offset|
        padding = "Z" * offset
        [
          {padding + "abcdefghijk", offset},
          {"abcdefghijk" + padding, 0},
          {padding + "abcdefghijk" + padding, offset},
        ].each do |haystack, base|
          bytes = haystack.to_slice
          at = 0
          expected.each do |id, relative_start, relative_end|
            found = pre.find_with_index(bytes, Regex::Automata::Span.new(at, bytes.size))
            found.should eq({id, Regex::Automata::Span.new(base + relative_start, base + relative_end)})
            at = base + relative_end
          end
          pre.find_with_index(bytes, Regex::Automata::Span.new(at, bytes.size)).should be_nil
        end
      end
    end
  end

  # aho-corasick 1.1.4 src/packed/tests.rs basic850 and regression050.
  it "preserves Teddy duplicate priority and binary candidate verification" do
    kind = Regex::Automata::MatchKind::LeftmostFirst
    duplicate = Regex::Automata::Prefilter.new(kind, ["foo", "foo"]).not_nil!
    duplicate.strategy_name.should eq("teddy")
    duplicate.find_with_index("foobarfoo".to_slice, Regex::Automata::Span.new(0, 9)).should eq(
      {0, Regex::Automata::Span.new(0, 3)}
    )

    binary = Regex::Automata::Prefilter.new(
      kind, [Bytes[0_u8, 0_u8, 1_u8], Bytes[0_u8, 0_u8, 0_u8]]
    ).not_nil!
    binary.strategy_name.should eq("teddy")
    binary.find_with_index(Bytes[0_u8, 0_u8, 0_u8], Regex::Automata::Span.new(0, 3)).should eq(
      {1, Regex::Automata::Span.new(0, 3)}
    )
  end

  # aho-corasick 1.1.4 packed/tests.rs basic810/basic820/basic850 and
  # SearchTest::variations (offset prefix, suffix, and both).
  it "keeps Teddy's leftmost priority across vector boundaries" do
    kind = Regex::Automata::MatchKind::LeftmostFirst
    cases = [
      {["abcd", "bcd", "cd"], "abcd", 0, 4},
      {["bcd", "cd", "abcd"], "abcd", 2, 4},
      {["foo", "foo"], "foobarfoo", 0, 3},
      {["inf", "ind"], "infind", 0, 3},
    ]
    cases.each do |needles, subject, id, finish|
      pre = Regex::Automata::Prefilter.new(kind, needles).not_nil!
      pre.strategy_name.should eq("teddy")
      [0, 1, 15, 16, 17, 31, 32, 63, 260].each do |offset|
        prefix = "Z" * offset
        suffix = "Z" * offset
        [{prefix + subject, offset}, {subject + suffix, 0}, {prefix + subject + suffix, offset}].each do |hay, at|
          pre.find_with_index(hay.to_slice, Regex::Automata::Span.new(0, hay.bytesize)).should eq(
            {id, Regex::Automata::Span.new(at, at + finish)}
          )
        end
      end
    end
  end

  it "verifies every Teddy mask width at bounded short and long spans" do
    sets = [
      ["a", "b", "c", "d"],
      ["ab", "bc", "cd", "de"],
      ["abc", "bcd", "cde", "def"],
      ["abcd", "bcde", "cdef", "defg"],
    ]
    haystack = ("Z" * 21 + "abcdefg" + "Z" * 23 + "defgabcd" + "Z" * 19).to_slice
    sets.each do |needles|
      pre = Regex::Automata::Prefilter.new(Regex::Automata::MatchKind::LeftmostFirst, needles).not_nil!
      pre.strategy_name.should eq("teddy")
      [0, 1, 15, 16, 20, 21, 22, 27, 28, 47, 50, 60].each do |start|
        [start, Math.min(start + 2, haystack.size), Math.min(start + 18, haystack.size), haystack.size].each do |finish|
          expected = nil.as(Tuple(Int32, Regex::Automata::Span)?)
          (start...finish).each do |at|
            needles.each_with_index do |needle, id|
              next if at + needle.bytesize > finish
              next unless haystack[at, needle.bytesize] == needle.to_slice
              expected = {id.to_i32, Regex::Automata::Span.new(at, at + needle.bytesize)}
              break
            end
            break if expected
          end
          pre.find_with_index(haystack, Regex::Automata::Span.new(start, finish)).should eq(expected)
        end
      end
    end
  end

  it "keeps leftmost start and pattern priority through failure-link overlaps" do
    pre = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      ["samwise", "sam", "wise"]
    ).not_nil!
    haystack = "xxsamwise".to_slice
    span = Regex::Automata::Span.new(0, haystack.size)
    pre.find_with_index(haystack, span).should eq({0, Regex::Automata::Span.new(2, 9)})
    pre.prefix_with_index(haystack, span).should be_nil
    pre.prefix_with_index(haystack, Regex::Automata::Span.new(2, 9)).should eq(
      {0, Regex::Automata::Span.new(2, 9)}
    )

    overlapping = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::LeftmostFirst,
      ["aab", "ab"]
    ).not_nil!
    overlapping.find("aab".to_slice, Regex::Automata::Span.new(0, 3)).should eq(
      Regex::Automata::Span.new(0, 3)
    )
  end

  it "treats a single substring needle as fast" do
    pre = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::All,
      ["ing"]
    ).not_nil!

    pre.is_fast.should be_true

    # The first `a` is only a candidate; the search must continue to the
    # later complete literal without scanning every non-candidate offset.
    pre = Regex::Automata::Prefilter.new(
      Regex::Automata::MatchKind::All,
      ["aba"]
    ).not_nil!
    pre.find("a---aba".to_slice, Regex::Automata::Span.new(0, 7)).should eq(
      Regex::Automata::Span.new(4, 7)
    )
  end
end
