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

require "addressable/uri"
require "retrieve"

module Retrieve
  class Resource
    ##
    # Creates a new Retrieve::Resource object from a URI.
    #
    # @param [Addressable::URI, String, #to_str] The URI for the resource.
    def initialize(uri)
      if !uri.kind_of?(Addressable::URI)
        if uri.respond_to?(:to_str)
          uri = Addressable::URI.parse(uri.to_str)
        else
          raise TypeError, "Can't convert #{uri.class} into String."
        end
      end
      @uri = uri
      @permanent_uri = uri
      @metadata = {}
      @client = nil
    end

    ##
    # The URI for this resource.  This will be set to the final resource URI
    # after all redirections required by the protocol.
    #
    # @return [Addressable::URI] The URI.
    attr_accessor :uri

    ##
    # The permanent URI for this resource.  This will be the permanent URI
    # that should be used for subsequent requests for the same resource.
    #
    # @return [Addressable::URI] The URI.
    attr_accessor :permanent_uri

    ##
    # The metadata for this resource.
    #
    # @return [Hash] Resource metadata provided by the client.
    attr_reader :metadata

    ##
    # The actual client which handles accessing the resource.
    #
    # @return [Retrieve::Client] The client.
    def client
      @client ||= (begin
        if @uri.scheme
          client_class = Retrieve::Client.for(@uri.scheme)
          if client_class
            client_class.new(self)
          else
            nil
          end
        else
          nil
        end
      end)
    end

    ##
    # Opens a <tt>Retrieve::Resource</tt> with the client.
    #
    # @param [Hash] options Optional parameters to be passed to the client.
    # @yieldparam [Retrieve::Resource] resource
    #   The <tt>Retrieve::Resource</tt> after it has been opened.
    # @return [Retrieve::Resource, NilClass]
    #   If the optional block is supplied, returns the block's return value.
    #   Otherwise, the opened <tt>Retrieve::Resource</tt> object is returned.
    def open(options={}, &block)
      begin
        # Call the appropriate client's open method.
        self.client.open(options)
        if block
          # If we were supplied a block, yield to it, then close.
          yield self
        else
          self
        end
      ensure
        # Make sure we close if there's a block.
        self.close if block rescue nil
      end
    end

    ##
    # All other methods are simply relayed to the resource's client.
    def method_missing(message, *params, &block)
      # We only want to relay to public client methods.
      if self.respond_to?(message)
        return self.client.send(message, *params, &block)
      else
        raise NoMethodError,
          "Undefined method '#{message}' for #{self.inspect}."
      end
    end

    ##
    # Determines if the resource responds to the message.
    #
    # @param [String, Symbol] message The message to check.
    #
    # @return [TrueClass, FalseClass]
    #   Returns true if Retrieve::Response directly implements the method.
    #   Returns true if the client responds to the message instead.
    #   Otherwise returns false.
    def respond_to?(message)
      # Return true if we directly implement the method.
      return true if super(message)
      # Return true if our client responds to the message.
      return self.client.respond_to?(message)
    end

    ##
    # Provides a standard inspection string.
    #
    # @return [String] A very simple representation of the object.
    def inspect
      return sprintf(
        "#<%s:%#0x URI:%s>",
        self.class.to_s, self.object_id, self.uri.to_s
      )
    end
  end
end
