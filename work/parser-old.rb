=begin rdoc

= Parser

Gerenal purpose stack-based parser. Define custom tokens
and the parser will build a parse tree from them.

== Synopsis

To use the parser you must define your token classes. There
are three types of tokens: normal, raw and unit. Normal
tokens are the default, requiring the definition of #start
and a #stop class methods. These must take a MatchData object
as a parameter (although it need not be used) and return a regular
expression to match against. Raw tokens are just like normal
tokens except the parser will not tokenize what lies between the raw 
token's start and stop markers, instead reading it as raw text.
Finally a unit token has no content, so a #stop method is not required,
simply define the start #method to be used for matching.

  require 'carat/parser'
  require 'yaml'

  s = "[p]THIS IS A [t][b]BOLD[b.]TEST[t.]&tm;[p.]"

  class XmlTagToken < Parser::Token
    def self.start( match ) ; %r{ \[ (.*?) \] }mx ; end
    def self.stop( match ) ; %r{ \[ [ ]* (#{esc(match[1])}) (.*?) \. \] }mx ; end
  end

  class XmlRawTagToken < Parser::RawToken
    def self.start( match ) ; %r{ \[ (t.*?) \] }mx ; end
    def self.stop( match ) ; %r{ \[ [ ]* (#{esc(match[1])}) (.*?) \. \] }mx ; end
  end

  class XmlEntityToken < Parser::UnitToken
    def self.start( match ) ; %r{ \& (.*?) \; }x ; end
  end

  markers = []
  markers << XmlRawTagToken
  markers << XmlTagToken
  markers << XmlEntityToken

  cp = Parser.new( *markers )
  d = cp.parse( s )
  y d

_produces_

  --- &id003 !ruby/array:Parser::Main
  - &id002 !ruby/object:#<Class:0x403084a0>
    body:
      - "THIS IS A "
      - &id001 !ruby/object:#<Class:0x403084a0>
        body:
          - !ruby/object:#<Class:0x403084a0>
            body:
              - BOLD
            match: !ruby/object:MatchData {}
            parent: *id001
          - TEST
        match: !ruby/object:MatchData {}
        parent: *id002
      - !ruby/object:#<Class:0x40308450>
        body: []
        match: !ruby/object:MatchData {}
        parent: *id002
    match: !ruby/object:MatchData {}
    parent: *id003

The order in which tokens are passed into the parser is significant, in that it decides
token precedence on a first-is-highest basis.

[Note: There are a few other subtilties to go over that I haven't yet
documented, primarily related to creating more elaborate custom tokens. TODO!]

== History

  2005-01-27:
    - Removed priority. Order of tokens when parser is initilized 
      now determines precedence.
    - If first argument to Parser.new is not a kind of AbstractToken
      it is assumed to be the reentrant parser, otherwise the parser
      itself is considered the reentrant parser. Having this allows raw
      tokens to parse embedded content (among other things).

== Author

Thomas Sawyer, (c)Copyright 2005 Ruby License

=end

require 'carat/attr'

#
# Parser
#
class Parser
  
  def initialize( *markers )
    unless markers.first.kind_of?( Parser::Token )
      rp = markers.shift
    else
      rp = self
    end
    markers = markers.collect{ |m| c = m.dup ; c.parser = rp ; c }
    @registry = Registry.new( *markers )
  end
  
  def parse( text )
    stack = reparse( text )
    return stack
  end
  
  private
  
  class Main < Array
    def match ; nil ;  end
  end
  
  def reparse( text )
    stack = Main.new
    token_stack = []
    current = stack
    
    offset = 0
    tokenize = 0
    finished = false
  
    until finished
      tag = nil
      mode = nil
      match = nil
      token = nil
      index = text.length
    
      unless token_stack.empty?
        t = token_stack.last
        m = stack.last
        i = text.index( t.stop( m.match ), offset )
        if i and i < index
          mode = :END
          token = t
          match = $~
          index = i
        end
      end
      
      @registry.each do |t|
        i = text.index( t.start( current.match ), offset )
        if i and i < index    # what comes first?
          m = $~              # store match
#           if t.unit?
#             mode = :UNIT
#             token = t
#             match = m
#             index = i
#           elsif text.index( t.stop( m ), m.end(0) )    # ensure a matching end tag
#             mode = :START
#             token = t
#             match = m
#             index = i
#           end
          mode = t.unit? ? :UNIT : :START 
          token = t
          match = m
          index = i
          if mode == :START
            unless text.index( t.stop( m ), m.end(0) )    # ensure a matching end tag
              raise "no end tag for #{t}"
            end
          end
        end
      end

      case mode
      when :START
        buffer_text = text[offset...index]
        current << buffer_text unless buffer_text.empty?
        new_marker = Marker.new( token.key, match, current ) #token.new( match, current )
#p "START", match[0], new_marker if $DEBUG
        if tokenize == 0 
          current << new_marker
          current = new_marker
        else
          current << match[0]
        end
        token_stack << token
        stack << new_marker
        tokenize += 1 if token.raw?                      # increment tokenizer raw tag count
        offset = match.end(0)                            # increment the offset
      when :END
        buffer_text = text[offset...index].chomp("\n")
        current << buffer_text unless buffer_text.empty?
        completed_token = token_stack.pop                # pop off the token
        completed_marker = stack.pop                     # pop off the marker
#p "END", match[0], completed_marker if $DEBUG
        tokenize -= 1 if token.raw?                      # decrement tokenizer raw tag count
        if tokenize == 0        
          current = completed_marker.parent
        else
          current << match[0]
        end
        offset = match.end(0)                            # increment the offset
      when :UNIT
        buffer_text = text[offset...index] #.chomp("\n")
        current << buffer_text unless buffer_text.empty?
        current << Marker.new( token.key, match, current ) #token.new( match, current )
#p "UNIT", match[0], current.last if $DEBUG
        offset = match.end(0)                            # increment the offset        
      else
        buffer_text = text[offset..-1].chomp("\n")
        current << buffer_text unless buffer_text.empty?
        finished = true                                  # finished
      end #case
    end #until

    return stack
  end

end #class Parser

#
# Registry
#
class Parser::Registry
 
  attr_reader :registry  

  def initialize( *tokens )
    @registry = []
    register( *tokens )
  end

  def register( *tokens )
    tokens.each { |tkn|
      raise( ArgumentError, "#{tkn.inspect} is not a Parser::Token" ) unless Parser::Token === tkn
    }
    @registry.concat( tokens )
    #@sorted = false
  end
  
  def empty? ; @registry.empty? ; end
  
  def each( &yld )
    registry.each( &yld )
  end

  #def registry_by_class( klass )
  #  @registry_by_class[ klass ].sort!
  #  @registry_by_class[ klass ]
  #end

  #def []( klass )
  #  registry_by_class[ klass ]
  #end

end #class Parser::Registry

def self.resc(str) ; Regexp.escape(str) ; end 

#
# Token Definition Class
#
class Parser::Token

  attr :key, :type, :start=, :stop=, :parser=

  def initialize( key, type=nil, start=nil, stop=nil )
    @key = key
    @type = type || :regular
    @start = start
    @stop = stop
  end

  def unit? ; @type == :unit  ; end
  def raw? ; @type == :raw ; end
  def normal? ; @type != :raw && @type != :unit ; end

  def start( match=nil )
    raise "start undefined for #{name}" unless @start
    @start.call( match )
  end
  
  def stop( match=nil )
    raise "stop undefined for #{name}" unless @stop
    @stop.call( match )
  end

end

#
# Token Marker
#
# This is the superclas of Token, UnitToken and RawToken
#
class Parser::Marker
  attr_reader :key, :parent, :match, :body
  def initialize( key, match, parent )
    @key = key
    @parent = parent
    @match = match
    @body = []
  end
  # array-like methods  
  def <<( content ) ; @body << content ; end
  def last ; @body.empty? ? @body : @body.last ; end
  def empty? ; @body.empty? ; end
  def pop ; @body.pop ; end
  def each(&blk) ; @body.each(&blk) ; end
end


# --- development testing ---

if $0 == __FILE__

  require 'yaml'

s = %Q{[p]
THIS IS A 
[t]
[b]BOLD[b.]TEST
[t.]
&tm;
[p.]
}

  tokens = []
  
  t = Parser::Token.new
  t.start = lambda { |match| %r{ \[ (.*?) \] }mx }
  t.stop = lambda { |match| %r{ \[ [ ]* (#{resc(match[1])}) (.*?) \. \] }mx }
  tokens << t

  t = Parser::Token.new(:raw)
  t.start = lambda { |match| %r{ \[ (t.*?) \] }mx }
  t.stop = lambda { |match| %r{ \[ [ ]* (#{resc(match[1])}) (.*?) \. \] }mx }
  tokens << t

  t = Parser::Token.new(:unit)
  t.start = lambda { |match| ; %r{ \& (.*?) \; }x }
  tokens << t

  cp = Parser.new( *tokens )
  d = cp.parse( s )
  y d
  
end
