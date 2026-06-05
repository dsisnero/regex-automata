module Regex::Automata
  class Lazy(T)
    @create : Proc(T)
    @mutex : Mutex
    @value : T?
    @initialized : Bool

    def initialize(&@create : -> T)
      @mutex = Mutex.new
      @value = nil
      @initialized = false
    end

    def self.get(this : Lazy(T)) : T forall T
      this.get
    end

    def get : T
      return @value.not_nil! if @initialized

      @mutex.synchronize do
        unless @initialized
          @value = @create.call
          @initialized = true
        end
      end

      @value.not_nil!
    end
  end
end
