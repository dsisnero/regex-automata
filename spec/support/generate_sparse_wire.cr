require "../../src/regex-automata"

include Regex::Automata
examples = {
  "shadowed" => DFA::Builder.new.configure(DFA::DFA.config.minimize(true)).build_many(["a", "a", "(?-u:\\b\\B)"]),
  "abc"      => DFA::DFA.new("abc"),
  "empty"    => DFA::Builder.new.configure(DFA::DFA.config.starts_for_each_pattern(true)).build_many([] of String),
  "always"   => DFA::DFA.always_match,
  "never"    => DFA::DFA.never_match,
  "quit"     => DFA::Builder.new.configure(DFA::DFA.config.quit('A'.ord.to_u8, true)).build("abc"),
}
{true, false}.each do |classes|
  {true, false}.each do |minimize|
    {true, false}.each do |accelerate|
      name = "matrix-#{classes}-#{minimize}-#{accelerate}"
      examples[name] = DFA::Builder.new
        .configure(DFA::DFA.config.byte_classes(classes).minimize(minimize).accelerate(accelerate)
          .starts_for_each_pattern(true).specialize_start_states(true))
        .build_many(["a[^x]*x", "(?-u:\\b)foo", "bar$"])
    end
  end
end
native = DFA::DFA.native_wire_endian == :little ? "littleendian" : "bigendian"
%w(fwd rev).each do |direction|
  base = File.join(__DIR__, "../../vendor/regex/regex-automata/tests/gen")
  examples["vendor-#{direction}"] = DFA::DFA.from_bytes(File.read("#{base}/dense/multi_pattern_v2_#{direction}.#{native}.dfa").to_slice)[0]
  sparse_bytes = File.read("#{base}/sparse/multi_pattern_v2_#{direction}.#{native}.dfa").to_slice
  sparse = DFA::Sparse::DFA.from_bytes(sparse_bytes)[0]
  prefix = "temp/sparse-wire-oracle/sparse-#{direction}"
  File.write("#{prefix}.dfa", sparse_bytes)
  File.write("#{prefix}.le", sparse.to_bytes_little_endian)
  File.write("#{prefix}.be", sparse.to_bytes_big_endian)
  File.write("#{prefix}.memory", sparse.memory_usage.to_s)
end
examples.each do |name, dense|
  base = "temp/sparse-wire-oracle/#{name}"
  bytes, padding = dense.to_bytes_native_endian
  File.write("#{base}.dense", bytes[padding..])
  decoded = DFA::DFA.from_bytes(bytes)[0]
  sparse = decoded.to_sparse
  File.write("#{base}.le", sparse.to_bytes_little_endian)
  File.write("#{base}.be", sparse.to_bytes_big_endian)
  File.write("#{base}.memory", sparse.memory_usage.to_s)
end
File.write("temp/sparse-wire-oracle/cases.txt", examples.keys.join('\n'))
