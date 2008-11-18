# ++
# Retrieve, Copyright (c) 2008 Bob Aman
# 
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
# 
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
# --

require "retrieve"

module Retrieve
  class NoClientError < StandardError
  end

  ##
  # A client which handles a given URI scheme.
  #
  # Subclass instances must minimally respond to <tt>open</tt>, <tt>read</tt>,
  # and <tt>close</tt>.  The subclass itself must respond to <tt>scheme</tt>.
  # The <tt>read</tt> method should set any relevant metadata on
  # the <tt>Retrieve::Resource</tt>.  The behavior of any other methods for
  # reading or writing are undefined, but authors are encouraged to be
  # as "unsurprising" as possible.  Any state that must been maintained
  # between opening and closing should be encapsulated within the client
  # rather than being temporarily stored within the <tt>Resource</tt>.
  # Subclasses of <tt>Retrieve::Client</tt> should generally "quack" like
  # an IO object.  Files which define a subclass of <tt>Retrieve::Client</tt>
  # should never assume that "retrieve/client" has already been required.
  class Client
    def initialize(resource)
      unless resource.kind_of?(Retrieve::Resource)
        raise TypeError,
          "Expected Retrieve::Resource, got #{resource.class}."
      end
      @resource = resource
    end

    ##
    # An array containing all subclasses of <tt>Retrieve::Client</tt>.
    @@subclasses = []

    ##
    # Called automatically when a subclass inherits from
    # <tt>Retrieve::Client</tt>.  There is no need to call this method
    # directly.
    #
    # @param [Class] subclass
    #   The subclass inheriting from <tt>Retrieve::Client</tt>
    def self.inherited(subclass)
      @@subclasses << subclass
      return nil
    end

    ##
    # A lookup method to find the appropriate client to handle a particular
    # URI scheme.
    #
    # @param [Symbol, String, #to_str] The scheme for which a client is needed
    #
    # @return [Retrieve::Client, NilClass]
    #   The client for handling the scheme, or nil if none was found.
    def self.for(scheme)
      if scheme.kind_of?(Symbol)
        scheme = scheme.to_s
      elsif scheme.respond_to?(:to_str)
        scheme = scheme.to_str
      else
        raise TypeError, "Can't convert #{scheme.class} into String."
      end

      # It would be nice if we could run this once in the inherited method,
      # but unfortunately, that's not possible because nothing is defined
      # on the client yet when the inherited method is called.
      @@subclasses.each do |subclass|
        if subclass.respond_to?(:scheme)
          client_scheme = subclass.scheme
          if client_scheme.kind_of?(String) ||
              client_scheme.respond_to?(:to_str)
            client_scheme = client_scheme.to_str
          else
            raise TypeError,
              "Can't convert #{client_scheme.class} into String."
          end
          if (["open", :open] & subclass.instance_methods).empty?
            raise TypeError,
              "Subclass instance must respond to :open message."
          end
          if (["read", :read] & subclass.instance_methods).empty?
            raise TypeError,
              "Subclass instance must respond to :read message."
          end
          if (["close", :close] & subclass.instance_methods).empty?
            raise TypeError,
              "Subclass instance must respond to :close message."
          end
          if client_scheme =~ /^[^:\/?#]+$/
            if scheme == client_scheme
              return subclass
            end
          else
            raise ArgumentError, "Invalid scheme: '#{client_scheme}'"
          end
        else
          raise TypeError, "Subclass must respond to :scheme message."
        end
      end
      return nil
    end

    ##
    # The resource this client is operating on.
    #
    # @return [Retrieve::Resource]
    attr_reader :resource
  end
end
