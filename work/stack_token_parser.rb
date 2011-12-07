#--
# TokenParser
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
#   - Removed priority. Order of tokens when parser is initilized
#     now determines precedence.
#   - If first argument to Parser.new is not a kind of AbstractToken
#     it is assumed to be the reentrant parser, otherwise the parser
#     itself is considered the reentrant parser. Having this allows raw
#     tokens to parse embedded content (among other things).
#
# ==========================================================================
#++

#:title: TokenParser
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
#   require 'mega/tokenparser'
#   require 'yaml'
#
#   s = "[p]THIS IS A [t][b]BOLD[b.]TEST[t.]&tm;[p.]"
#
#   class XmlTagToken < TokenParser::Token
#     def self.start( match ) ; %r{ \[ (.*?) \] }mx ; end
#     def self.stop( match ) ; %r{ \[ [ ]* (#{esc(match[1])}) (.*?) \. \] }mx ; end
#   end
#
#   class XmlRawTagToken < TokenParser::RawToken
#     def self.start( match ) ; %r{ \[ (t.*?) \] }mx ; end
#     def self.stop( match ) ; %r{ \[ [ ]* (#{esc(match[1])}) (.*?) \. \] }mx ; end
#   end
#
#   class XmlEntityToken < TokenParser::UnitToken
#     def self.start( match ) ; %r{ \& (.*?) \; }x ; end
#   end
#
#   markers = []
#   markers << XmlRawTagToken
#   markers << XmlTagToken
#   markers << XmlEntityToken
#
#   cp = TokenParser.new( *markers )
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

class TokenParser

  def initialize( *markers )
    unless markers.first.kind_of?( TokenParser::Token )
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

  #
  # Main to start stack
  #
  class Main < Array
    def match ; nil ;  end
  end

  #
  # Token Marker
  #
  # This is the superclass of Token, UnitToken and RawToken
  #
  class Marker
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


  def reparse( text )
    stack = [] #Main.new
    #stack = []
    #token_stack = []
    current = stack

    offset = 0
    #tokenize = 0
    finished = false

    until finished
      mode  = nil
      begins = nil
      ends = nil
      info = nil
#match = nil
      token = nil
      index = text.length  # by comparision to find the nearest match

      #unless token_stack.empty?
      unless stack.empty?
        raise "not a marker on end of stack?" unless Marker === stack.last  # should not happen
        m = stack.last  # get last marker
        #t = token_stack.last
        t = m.token     # marker's token
        #i = text.index( t.stop( m.match ), offset )
        #i = text.index( t.stop( stack ), offset )

        i,e = t.stop( text, offset, stack )

        if i #and i < index
          mode = :END
          token = t
          #match = $~
          begins = i
          ends = e
          #info = ih
          index = i
        end
      end

      @registry.each do |t|
        #i = text.index( t.start( current.match ), offset )
        #i = text.index( t.start( stack ), offset )

        i,e,ih = t.start( text, offset, stack )

        if i and i < index    # what comes first?
          #m = $~              # store match
          mode = t.unit? ? :UNIT : :START
          token = t
          #match = m
          begins = i
          ends = e
          info = ih
          index = i

# TODO Fix (need to make mock marker, I guess, and use a dummy stack to pass to #stop)

          unless t.unit? #if mode == :START
            #unless text.index( t.stop( m ), m.end(0) )    # ensure a matching end token
            #  raise "no end token matching #{t.stop( m )}"
#            unless text.index( t.stop( stack ), m.end(0) )    # ensure a matching end token
#              raise "no end token matching #{t.stop( stack )}"
#            end
          end
        end
      end

      case mode
      when :START
        buffer_text = text[offset...index]
        current << buffer_text unless buffer_text.empty?

        mock = Marker.new
        mock.token = token
        #mock.match = match
        mock.begins = begins
        mock.ends = ends
        mock.info = info
        mock.parent = current

        current << mock
        current = mock
        stack << mock

        offset = ends #match.end(0)                            # increment the offset

        #tokenize += 1 if token.raw?                      # increment tokenizer raw token count

      when :END
        buffer_text = text[offset...index].chomp("\n")
        current << buffer_text unless buffer_text.empty?

        mock = stack.pop                # pop off the marker

        #mock.outer_range = mock.match.begin(0)...match.end(0)
        #mock.inner_range = mock.match.end(0)...match.begin(0)
        mock.outer_range = mock.begins...ends
        mock.inner_range = mock.ends...begins

        current = mock.parent

        offset = ends #match.end(0)                   # increment the offset

      when :UNIT
        buffer_text = text[offset...index] #.chomp("\n")
        current << buffer_text unless buffer_text.empty?

        mock = Marker.new
        mock.token = token
        #mock.match = match
        mock.begins = begins
        mock.ends = ends
        mock.info = info
        mock.parent = current

        mock.outer_range = begins...ends
        #mock.outer_range = match.begin(0)...match.end(0)

        current << mock

        offset = ends #match.end(0)                             # increment the offset        

      else
        buffer_text = text[offset..-1].chomp("\n")
        current << buffer_text unless buffer_text.empty?

        finished = true                                   # finished

      end #case
    end #until

    return stack
  end

end #class Parser

#
# Registry
#
class TokenParser::Registry

  attr_reader :registry

  def initialize( *tokens )
    @registry = []
    register( *tokens )
  end

  def register( *tokens )
#     tokens.each { |tkn|
#       unless TokenParser::Token === tkn or TokenParser::UnitToken === tkn
#         raise( ArgumentError, "#{tkn.inspect} is not a TokenParser::Token" )
#       end
#     }
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

#def self.resc(str) ; Regexp.escape(str) ; end 

#
# Token Definition Class
#
class TokenParser::Token

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
class TokenParser::UnitToken

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

  t = TokenParser::Token.new( :ONE )
  def t.start( text, offset, state )
    r = %r{ \[ (.*?) \] }mx
    i = text.index( r, offset )
    return i, $~.end(0), { :tag => $~[1] } if i
    return nil,nil,nil
  end

  def t.stop( text, offset, state )
    r = %r{ \[ [ ]* (#{resc(state.last.info[:tag])}) (.*?) \. \] }mx
    i = text.index( r, offset )
    return i, $~.end(0) if i
    return nil,nil
  end

  tokens << t


  t = TokenParser::UnitToken.new( :TWO )

  def t.start( text, offset, state )
    r = %r{ \& (.*?) \; }x
    i = text.index( r, offset )
    return i, $~.end(0), { :tag => $~[1] } if i
    return nil,nil,nil
  end

  tokens << t

  cp = TokenParser.new( *tokens )
  d = cp.parse( s )
  y d

end
