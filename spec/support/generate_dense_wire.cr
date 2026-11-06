require "../../src/regex-automata"

include Regex::Automata

examples = {
  "abc"            => DFA::DFA.new("abc"),
  "always"         => DFA::DFA.always_match,
  "never"          => DFA::DFA.never_match,
  "multi"          => DFA::Builder.new.configure(DFA::DFA.config.starts_for_each_pattern(true).minimize(true)).build_many(["foo[0-9]+", "bar[0-9]+"]),
  "empty-patterns" => DFA::Builder.new.configure(DFA::DFA.config.starts_for_each_pattern(true)).build_many([] of String),
  "quitset"        => DFA::Builder.new.configure(DFA::DFA.config.quit('A'.ord.to_u8, true)).build("abc"),
}
%w(fwd rev).each do |direction|
  native = DFA::DFA.native_wire_endian == :little ? "littleendian" : "bigendian"
  path = File.join(__DIR__, "../../vendor/regex/regex-automata/tests/gen/dense/multi_pattern_v2_#{direction}.#{native}.dfa")
  examples["vendor-#{direction}"] = DFA::DFA.from_bytes(File.read(path).to_slice)[0]
end
padding_dfa = DFA::DFA.new("abc")
padding_bytes = padding_dfa.to_bytes_native_endian[0]
Wire.write_u32(UInt32::MAX, padding_bytes[312 + padding_dfa.alphabet_len * 4..])
examples["padding"] = DFA::DFA.from_bytes(padding_bytes)[0]
examples.each do |name, dfa|
  base = "temp/dense-wire-oracle/#{name}"
  bytes, padding = dfa.to_bytes_native_endian
  File.write("#{base}.dfa", bytes[padding..])
  # The pinned ByteSet reader uses the low bucket twice. Expected output
  # follows Rust's deserialize/reserialize behavior, not a byte-copy oracle.
  decoded = DFA::DFA.from_bytes(bytes)[0]
  File.write("#{base}.expected-le", decoded.to_bytes_little_endian[0])
  File.write("#{base}.expected-be", decoded.to_bytes_big_endian[0])
end
