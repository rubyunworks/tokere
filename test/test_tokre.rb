require 'yaml'
require 'facets/string/to_re'
require 'tokre'

s = %Q{
  MON[p]This is plain paragraph.[t][b]This bold.[b.]This teed off.[t.]&tm;[p.]KEY&tm;
}

class MyMachine < Tokre::Machine

  attr_accessor :tag_stack

  def initialize
    @tag_stack = []
  end

  token :tag do
    def match( state )
      %r{ \[ (.*?) \] }mx
    end

    def end_match(match, state)
      %r{ \[ [ ]* (#{tag_stack.last.to_rx}) (.*?) \. \] }mx
    end

    def callback( match, state )
      tag_stack << match[1]
      puts "<#{match[1]}>"
    end

    def end_callback( match, state )
      t = tag_stack.pop
      puts "</#{match[1]}>"
    end
  end

  token :entity do
    def match( state )
      %r{ \& (.*?) \; }x
    end

    def callback( match, state )
      puts "&" + match[1] + ';'
    end
  end

end

cp = Tokre::Parser.new(MyMachine.new)
d = cp.parse( s )
puts d

