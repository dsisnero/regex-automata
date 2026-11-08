require "./spec_helper"

private def interpolate_string(
  name_to_index : Hash(String, Int32),
  caps : Array(String),
  replacement : String,
) : String
  String.build do |dst|
    Regex::Automata::Interpolate.string(
      replacement,
      ->(index : Int32, out : IO) do
        if value = caps[index]?
          out << value
        end
        nil
      end,
      ->(name : String) { name_to_index[name]? },
      dst
    )
  end
end

private def interpolate_bytes(
  name_to_index : Hash(String, Int32),
  caps : Array(String),
  replacement : String,
) : String
  dst = [] of UInt8
  Regex::Automata::Interpolate.bytes(
    replacement.to_slice,
    ->(index : Int32, out : Array(UInt8)) do
      if value = caps[index]?
        value.each_byte { |byte| out << byte }
      end
      nil
    end,
    ->(name : String) { name_to_index[name]? },
    dst
  )
  String.new(Bytes.new(dst.size) { |i| dst[i] })
end

private def assert_interpolates(
  name_to_index : Hash(String, Int32),
  caps : Array(String),
  replacement : String,
  expected : String,
) : Nil
  interpolate_string(name_to_index, caps, replacement).should eq(expected)
  interpolate_bytes(name_to_index, caps, replacement).should eq(expected)
end

describe Regex::Automata::Interpolate do
  it "parses a braced leading plus as an unsigned numeric reference" do
    assert_interpolates({"+1" => 0}, ["wrong", "one"], "${+1}", "one")
    assert_interpolates({" 1" => 0, "1_0" => 0, "-0" => 0}, ["named", "one"], "${ 1}/${1_0}/${-0}", "named/named/named")
  end

  it "distinguishes full-width numeric indexes from overflowing names" do
    result = String.build do |dst|
      Regex::Automata::Interpolate.string(
        "${18446744073709551615}/${18446744073709551616}",
        ->(index : UInt64, out : IO) { out << "index:#{index}"; nil },
        ->(name : String) { name == "18446744073709551616" ? 7_u64 : nil },
        dst)
    end
    result.should eq("index:18446744073709551615/index:7")
    # The compatibility Int32 callback cannot address such a group, and the
    # numeric text must not accidentally invoke the name lookup instead.
    assert_interpolates({"2147483648" => 0}, ["wrong"], "${2147483648}", "")
  end

  it "matches the vendored replacement semantics for names, indices, and escapes" do
    assert_interpolates({"foo" => 2}, ["", "", "xxx"], "test $foo test", "test xxx test")
    assert_interpolates({"foo" => 2}, ["", "", "xxx"], "test$footest", "test")
    assert_interpolates({"foo" => 2}, ["", "", "xxx"], "test${foo}test", "testxxxtest")
    assert_interpolates({"foo" => 2}, ["", "", "xxx"], "test$2test", "test")
    assert_interpolates({"foo" => 2}, ["", "", "xxx"], "test${2}test", "testxxxtest")
    assert_interpolates({"foo" => 2}, ["", "", "xxx"], "test $$foo test", "test $foo test")
    assert_interpolates({"foo" => 2}, ["", "", "xxx"], "test $foo", "test xxx")
    assert_interpolates({"foo" => 2}, ["", "", "xxx"], "$foo test", "xxx test")
    assert_interpolates({"bar" => 1, "foo" => 2}, ["", "yyy", "xxx"], "$foo$bar", "xxxyyy")
  end

  it "takes the longest unbraced reference and lets braced references disambiguate" do
    assert_interpolates({"42a" => 1}, ["", "named"], "$42a", "named")
    assert_interpolates({} of String => Int32, ["", "", "num"], "${2}a", "numa")
    assert_interpolates({"1_" => 1}, ["", "named"], "$1_$2", "named")
  end

  it "keeps invalid references literal and missing references empty" do
    assert_interpolates({} of String => Int32, ["", "", "xxx"], "${42", "${42")
    assert_interpolates({} of String => Int32, ["", "", "xxx"], "${42 ", "${42 ")
    assert_interpolates({} of String => Int32, ["", "", "xxx"], "x${}y", "xy")
    assert_interpolates({} of String => Int32, ["", "", "xxx"], "$", "$")
    assert_interpolates({} of String => Int32, ["", "", "xxx"], "plain text", "plain text")
  end

  it "supports braced non-ascii capture names" do
    assert_interpolates({"名字" => 1}, ["", "value"], "${名字}", "value")
    assert_interpolates({"foo[bar].baz" => 1}, ["", "value"], "${foo[bar].baz}", "value")
  end
end
