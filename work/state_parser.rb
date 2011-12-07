#--
# StateParser
#
# Copyright (c) 2005 Thomas Sawyer
#
# Ruby License
#
# This module is free software. You may use, modify, and/or redistribute this
# software under the same terms as Ruby.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.
#
# ==========================================================================
#  Revision History
# ==========================================================================
#
#  5.2.6  Trans
#   - Removed raw tokens. Raw text is now available to every regular
#     token, so the end application can decided how to treat it.
#
#  5.1.27 Trans
#   - Removed priority. Order of tokens when parser is initialized
#     now determines precedence.
#   - If first argument to Parser.new is not a kind of AbstractToken
#     it is assumed to be the reentrant parser, otherwise the parser
#     itself is considered the reentrant parser. Having this allows raw
#     tokens to parse embedded content (among other things).
#
# ==========================================================================
#++

#:title: StateParser
#
# Gerenal purpose stack-based parser. Define custom tokens
# and the parser will build a parse tree from them.
#
# == Synopsis
#
# (note: these docs need updating)
#
# To use the parser you must define your token classes. There
# are three types of tokens: normal, raw and unit. Normal
# tokens are the default, requiring the definition of #start
# and #stop class methods. These must take a MatchData object
# as a parameter (although it need not be used) and return a regular
# expression to match against. Raw tokens are just like normal
# tokens except the parser will not tokenize what lies between the raw
# token's start and stop markers, instead reading it as raw text.
# Finally a unit token has no content, so a #stop method is not required,
# simply define the start #method to be used for matching.
#
#   require 'mega/state_parser'
#   require 'yaml'
#
#   s = "[p]THIS IS A [t][b]BOLD[b.]TEST[t.]&tm;[p.]"
#
#   class XmlTagToken < StateParser::Token
#     def self.start( match ) ; %r{ \[ (.*?) \] }mx ; end
#     def self.stop( match ) ; %r{ \[ [ ]* (#{esc(match[1])}) (.*?) \. \] }mx ; end
#   end
#
#   class XmlRawTagToken < StateParser::RawToken
#     def self.start( match ) ; %r{ \[ (t.*?) \] }mx ; end
#     def self.stop( match ) ; %r{ \[ [ ]* (#{esc(match[1])}) (.*?) \. \] }mx ; end
#   end
#
#   class XmlEntityToken < StateParser::UnitToken
#     def self.start( match ) ; %r{ \& (.*?) \; }x ; end
#   end
#
#   markers = []
#   markers << XmlRawTagToken
#   markers << XmlTagToken
#   markers << XmlEntityToken
#
#   cp = StateParser.new( *markers )
#   d = cp.parse( s )
#   y d
#
# _produces_
#
#   --- &id003 !ruby/array:Parser::Main
#   - &id002 !ruby/object:#<Class:0x403084a0>
#     body:
#       - "THIS IS A "
#       - &id001 !ruby/object:#<Class:0x403084a0>
#         body:
#           - !ruby/object:#<Class:0x403084a0>
#             body:
#               - BOLD
#             match: !ruby/object:MatchData {}
#             parent: *id001
#           - TEST
#         match: !ruby/object:MatchData {}
#         parent: *id002
#       - !ruby/object:#<Class:0x40308450>
#         body: []
#         match: !ruby/object:MatchData {}
#         parent: *id002
#     match: !ruby/object:MatchData {}
#     parent: *id003
#
# The order in which tokens are passed into the parser is significant,
# in that it decides token precedence on a first-is-highest basis.
#
# [Note: There are a few other subtilties to go over that I haven't yet
# documented, primarily related to creating more elaborate custom tokens. TODO!]
#
# == Author(s)
#
# * Thomas Sawyer
#

require 'ostruct'
require 'nano/kernel/resc'


class StateParser ; end

#
# State
#
class StateParser::State
  attr_reader :text, :stack
  attr_accessor :offset

  def initialize( text )
    @text = text.dup.freeze
    @offset = 0
    @stack = []
    @current = {}
  end

  def next_start( token, index )
    i,e,f = token.start( self )
    if i and i < index    # what comes first?
      @current[:token] = token
      @current[:mode] = token.unit? ? :UNIT : :START
      @current[:begins] = i
      @current[:ends] = e
      @current[:info] = f
      return i
    end
    return index
  end

  def next_end( index )
    token = @stack.last.token
    i,e,f = token.stop( self )
    if i and i < index    # what comes first?
      @current[:token] = token
      @current[:mode] = :END
      @current[:begins] = i
      @current[:ends] = e
      @current[:info] = f
      return i
    end
    return index
  end

  def clear_current ; @current = {} ; end

  def current_token  ; @current[:token]  ; end
  def current_mode   ; @current[:mode]   ; end
  def current_begins ; @current[:begins] ; end
  def current_ends   ; @current[:ends]   ; end
  def current_info   ; @current[:info]   ; end

  def mock( current )
    mock = StateParser::Marker.new
    mock.token = current_token
    #mock.match = current_match
    mock.begins = current_begins
    mock.ends = current_ends
    mock.info = current_info
    mock.parent = current
    mock
  end

  # increment the offset
  def next_offset
    @offset = current_ends
  end

  def to_s
    @stack.join
  end
end


#
# Marker
#
# This is used to hold token places in the parse tree.
#
class StateParser::Marker
  attr_accessor :token, :parent, :content
  attr_accessor :begins, :ends, :info #:match
  attr_accessor :outer_range, :inner_range
  def initialize
    @content = []
  end
  # array-like methods
  def <<( content ) ; @content << content ; end
  def last ; @content.empty? ? @content : @content.last ; end
  def empty? ; @content.empty? ; end
  def pop ; @content.pop ; end
  def each(&blk) ; @content.each(&blk) ; end
end


#
#
#
class StateParser

  def initialize( *markers )
    unless markers.first.kind_of?( StateParser::Token )
      rp = markers.shift
    else
      rp = nil #self
    end
    #markers = markers.collect{ |m| c = m.dup ; c.parser = rp ; c }
    @registry = Registry.new( *markers )
  end

  def parse( text )
    stack = reparse( text )
    return stack
  end

  private

  def reparse( text )

    state = State.new( text )
    current = state.stack
    finished = false

    until finished
      state.clear_current
      index = text.length  # by comparision to find the nearest match

      unless state.stack.empty?
        raise "not a marker on end of stack?" unless Marker === state.stack.last  # should not happen
        index = state.next_end( index )
      end

      @registry.each do |tokn|
        index = state.next_start( tokn, index )

# TODO Fix (need to make mock marker, I guess, and use a dummy stack to pass to #stop)

          #unless t.unit? #if mode == :START
            #unless text.index( t.stop( m ), m.end(0) )    # ensure a matching end token
            #  raise "no end token matching #{t.stop( m )}"
#            unless text.index( t.stop( stack ), m.end(0) )    # ensure a matching end token
#              raise "no end token matching #{t.stop( stack )}"
#            end
          #end
        #end
      end

      case state.current_mode
      when :START
        buffer_text = state.text[state.offset...index]
        current << buffer_text unless buffer_text.empty?

        mock = state.mock( current )

        current << mock
        current = mock
        state.stack << mock

        state.next_offset
        #state.offset = state.current_ends

      when :END
        buffer_text = state.text[state.offset...index].chomp("\n")
        current << buffer_text unless buffer_text.empty?

        mock = state.stack.pop                # pop off the marker

        mock.outer_range = mock.begins...state.current_ends
        mock.inner_range = mock.ends...state.current_begins

        current = mock.parent

        state.next_offset
        #state.offset = state.current_ends #match.end(0)                   # increment the offset

      when :UNIT
        buffer_text = state.text[state.offset...index] #.chomp("\n")
        current << buffer_text unless buffer_text.empty?

        mock = state.mock( current )

        mock.outer_range = state.current_begins...state.current_ends

        current << mock

        state.next_offset
        #state.offset = state.current_ends #match.end(0)                             # increment the offset

      else
        buffer_text = state.text[state.offset..-1].chomp("\n")
        current << buffer_text unless buffer_text.empty?

        finished = true                                   # finished

      end #case
    end #until

    return state.stack
  end

end #class Parser


#
# Registry
#
class StateParser::Registry

  attr_reader :registry

  def initialize( *tokens )
    @registry = []
    register( *tokens )
  end

  def register( *tokens )
#     tokens.each { |tkn|
#       unless StateParser::Token === tkn or StateParser::UnitToken === tkn
#         raise( ArgumentError, "#{tkn.inspect} is not a StateParser::Token" )
#       end
#     }
    @registry.concat( tokens )
    #@sorted = false
  end

  def empty? ; @registry.empty? ; end

  def each( &yld )
    registry.each( &yld )
  end

end #class Parser::Registry


#
# Token Definition Class
#
class StateParser::Token

  attr_reader :key #, :type

  def initialize( key )
    @key = key
  end

  def unit? ; false  ; end
  #def raw? ; @type == :raw ; end
  #def normal? ; @type != :raw && @type != :unit ; end

  def start( text, offset, state )
    raise "start undefined for #{key}"
  end

  #def stop( match=nil )
  #  raise "stop undefined for #{key}" unless @stop
  #  @stop.call( match )
  #end

end

#
# Unit Token Definition Class
#
class StateParser::UnitToken

  attr_reader :key #, :type

  def initialize( key )
    @key = key
  end

  def unit? ; true  ; end
  #def raw? ; @type == :raw ; end
  #def normal? ; @type != :raw && @type != :unit ; end

  def start( text, offset, state )
    raise "start undefined for #{key}"
  end

end



#__TEST__

if $0 == __FILE__

  require 'yaml'

s = %Q{
[p]
This is plain paragraph.
[t][b]This bold.[b.]This tee'd off.[t.]&tm;
[p.]
}

  tokens = []

  t = StateParser::Token.new( :ONE )
  def t.start( state )
    r = %r{ \[ (.*?) \] }mx
    i = state.text.index( r, state.offset )


    return i, $~.end(0), { :tag => $~[1] } if i
    return nil,nil,nil
  end

  def t.stop( state )
    r = %r{ \[ [ ]* (#{resc(state.stack.last.info[:tag])}) (.*?) \. \] }mx
    i = state.text.index( r, state.offset )

    return i, $~.end(0) if i
    return nil,nil
  end

  tokens << t


  t = StateParser::UnitToken.new( :TWO )

  def t.start( state )
    r = %r{ \& (.*?) \; }x
    i = state.text.index( r, state.offset )
    return i, $~.end(0), { :tag => $~[1] } if i
    return nil,nil,nil
  end

  tokens << t

  cp = StateParser.new( *tokens )
  d = cp.parse( s )
  y d

end
