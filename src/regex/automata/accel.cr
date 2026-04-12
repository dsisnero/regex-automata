module Regex::Automata
  # Minimal acceleration module - just the types without implementation

  alias AccelTy = UInt32
  ACCEL_TY_SIZE = sizeof(AccelTy)
  ACCEL_LEN     = 4
  ACCEL_CAP     = 8

  # Basic accelerator structure
  struct Accel
    @bytes : StaticArray(UInt8, ACCEL_CAP)

    def self.empty : Accel
      Accel.new(StaticArray(UInt8, ACCEL_CAP).new(0))
    end

    def initialize(@bytes : StaticArray(UInt8, ACCEL_CAP))
    end

    def len : Int32
      @bytes[0].to_i
    end
  end

  # Accelerators collection
  struct Accels
    @accels : Slice(AccelTy)

    def self.empty : Accels
      Accels.new(Slice(AccelTy).new(1, 0_u32))
    end

    def initialize(@accels : Slice(AccelTy))
    end

    def len : Int32
      @accels[0].to_i
    end
  end
end
