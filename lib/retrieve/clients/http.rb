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
require "retrieve/client"
require "socket"

module Retrieve
  ##
  # The HTTPClient handles URIs with an http scheme.
  #
  # @example
  #   res = Retrieve.open("http://example.com/", :method => :get)
  #   #=> #<Retrieve::Resource:0x847c2c URI:http://example.com/>
  #   res.read
  #   #=> "This is an example."
  #   res.close
  class HTTPClient < Retrieve::Client
    class HTTPClientError < StandardError
    end
    class HTTPParserError < HTTPClientError
    end

    ##
    # The HTTPClient handles URIs with an http scheme.
    #
    # @return [String] The string, "http"
    def self.scheme
      return "http"
    end

    ##
    # Initializes a <tt>FileClient</tt> for a given <tt>Resource</tt>.
    def initialize(resource)
      super(resource)
      if resource.uri.authority.to_s == ""
        raise ArgumentError,
          "Resource cannot be handled by client: '#{resource.uri}'"
      end
      @response = nil
      @remaining_body = StringIO.new
    end

    ##
    # Opens a <tt>Resource</tt>.
    #
    # @option [Symbol] method
    #   The HTTP method to use for the request.
    #
    # @return [Retrieve::Resource] The client's resource.
    def open(options={})
      options = {
        :method => :get,
        :cookie_store => {}
      }.merge(options)
      @cookie_store = options[:cookie_store]
      @response = send_request(options[:method], options)
      @remaining_body << @response.body
      @remaining_body.rewind
      return self.resource
    end

    ##
    # Reads the entire contents of the <tt>Resource</tt>.
    #
    # @return [String] The contents of the file.
    def read(n=nil)
      if @response == nil
        raise IOError, "No response available."
      end
      return @remaining_body.read(n)
    end

    ##
    # Closes the <tt>Resource</tt>.
    def close
      if @response == nil
        raise IOError, "No stream to close."
      end
      @response.close
      @response = nil
      return nil
    end

  private
    CHUNK_SIZE=1024 * 16
    CRLF = "\r\n"

    ##
    # Sends out the actual HTTP request, and returns the HTTP response.
    #
    # @param [String] method GET/POST/PUT/DELETE/etc
    # @option headers The request headers to send.
    # @option cookies The HTTP cookies to send.
    # @option timeout The number of seconds to wait before timeout.
    # @option body The body of the request.
    # @return [Retrieve::HTTPClient::HTTPResponse] The server's response.
    def send_request(method, options={})
      begin
        host, port = self.resource.uri.host, self.resource.uri.inferred_port
        @socket = PushBackIO.new(TCPSocket.new(host, port), options)

        output = StringIO.new
        write_head(method, output, options)
        body = options[:body] || ""

        @socket.write(output.string + body)
        @socket.flush

        return read_response(options)
      rescue Object
        raise $!
      ensure
        @socket.close if @socket
      end
    end

    ##
    # Writes the head section of an HTTP request.
    #
    # @param [String] method The HTTP method to use in the request.
    # @param [IO, StringIO] output The output stream to write to.
    # @option headers The HTTP headers to write.
    # @option cookies The HTTP cookies to write.
    # @option body The HTTP body that will be used in the request.
    def write_head(method, output, options={})
      headers = options[:headers] || {}

      # We always need these headers.
      headers["Host"] = self.resource.uri.normalized_authority
      headers["Content-Length"] = options[:body] ? options[:body].bytesize : 0

      # Merge cookies with headers.
      if headers["Cookie"].kind_of?(String)
        headers["Cookie"] = [headers["Cookie"]]
      else
        headers["Cookie"] ||= []
      end
      for key, value in (options[:cookies] || {})
        if value.kind_of?(Array)
          value.each do |subvalue|
            headers["Cookie"] << "#{escape(key)}=#{escape(subvalue)}"
          end
        else
          headers["Cookie"] << "#{escape(key)}=#{escape(value)}"
        end
      end

      # Write to the socket.
      output.write("%s %s HTTP/1.1\r\n" % [
        method.to_s.upcase, self.resource.uri.omit(
          :scheme, :authority, :fragment
        )
      ])
      output.write(encode_headers(headers))
      output.write(CRLF)
      nil
    end

    ##
    # Encodes the headers as a String.
    #
    # @param [Hash] headers The HTTP headers to encode to a <tt>String</tt>.
    #
    # @return [String] The encoded headers.
    def encode_headers(headers)
      result = StringIO.new
      headers.each do |key, value|
        if value.kind_of?(Array)
          value.each do |subvalue|
            result << ("%s: %s\r\n" % [key, subvalue])
          end
        else
          result << ("%s: %s\r\n" % [key, value])
        end
      end
      return result.string
    end

    ##
    # Escapes a string.
    #
    # @param [String] string The <tt>String</tt> to escape.
    # @return [String] The escaped <tt>String</tt>.
    def escape(string)
      (string.to_s.gsub(/([^ a-zA-Z0-9_.-]+)/n) do
        '%' + $1.unpack('H2' * $1.size).join('%').upcase
      end).tr(' ', '+')
    end

    HTTP_START_LINE = /^HTTP\/([0-9]\.[0-9]) ([0-9]{3}) (.+?)\r\n/m
    HTTP_TOKEN = /[^\(\)<>@,;:\\\"\/\[\]\?={}\t ]/
    HTTP_LWS = /[ \t]/
    HTTP_HEADER = /^(#{HTTP_TOKEN}+):[ \t]*([^\r\n]*)\r\n/
    HTTP_CHUNK_SIZE = /^([0-9a-fA-F]+)[ \t]*\r\n/

    ##
    # Reads the response from the socket.
    #
    def read_response(options={})
      @response = HTTPResponse.new

      if @socket.secondary.kind_of?(IO)
        ready =
          @socket.buffer.size > 0 ||
          !!select([@socket.secondary], nil, nil, (options[:timeout] || 20))
      end
      until read_status_line
      end
      until read_headers
      end
      process_metadata
      until read_body
      end

      return @response
    end

    def read_status_line
      data = @socket.read(1024, partial=true)
      match = data.match(HTTP_START_LINE)
      if !match && data !~ /\r\n/
        @socket.push(data)
        return false
      elsif !match
        raise HTTPParserError, "Response missing HTTP start line."
      elsif match.begin(0) != 0
        raise HTTPParserError, "Found HTTP start line on the wrong line."
      else
        @socket.push(match.post_match)
        @response.http_version, @response.status, @response.reason =
          match.captures
        return true
      end
    end

    def read_headers
      read_bytes = @socket.buffer.size > 0 ? @socket.buffer.size : CHUNK_SIZE
      data = @socket.read(read_bytes, partial=true)
      match = data.match(HTTP_HEADER)
      if !match && data !~ /\r\n/
        @socket.push(data)
        return false
      elsif !match
        data = data[2..-1] if (data =~ /^\r\n/) == 0
        @socket.push(data)
        return true
      elsif match.begin(0) != 0
        raise HTTPParserError, "Found HTTP header in the wrong place."
      else
        # TODO: deal with LWS header continuations and comments
        @socket.push(match.post_match)
        key, value = match.captures
        @response.headers[key] = value
        return false
      end
    end

    def read_body
      body = StringIO.new
      if @response.headers["Transfer-Encoding"] =~ /chunked/i
        loop do
          data = @socket.read(CHUNK_SIZE, partial=true)
          match = data.match(HTTP_CHUNK_SIZE)
          if match == nil
            raise HTTPParserError, "Could not determine chunk size."
          end
          chunk_size = match.captures[0].to_i(16)
          @socket.push(match.post_match)
          chunk = @socket.read(chunk_size, partial=true)
          crlf = @socket.read(2, partial=true)
          if crlf != "\r\n"
            raise HTTPParserError,
              "Expected CRLF after chunk, got: #{crlf.inspect}"
          end
          body << chunk
          break if chunk_size == 0
        end
      else
        if @response.headers["Content-Length"]
          content_length = @response.headers["Content-Length"].to_i
          remainder = content_length
          loop do
            read_bytes = remainder > CHUNK_SIZE ? CHUNK_SIZE : remainder
            data = @socket.read(read_bytes, partial=true)
            remainder -= data.bytesize
            body << data
            break if remainder == 0
          end
        else
          # If we end up here, we don't know how big our body is, and we're
          # likely to read too far, and get stuck waiting for an EOFError.
          data = nil
          if @socket.buffer.size > 0
            data = @socket.read(@socket.buffer.size, partial=true)
            body << data
          end
          begin
            loop do
              break if data == ""
              data = @socket.read(CHUNK_SIZE, partial=true)
              body << data
            end
          rescue HTTPClientError
            # We can easily end up reading too far since we don't know how
            # far to read.
          end
        end
      end
      @response.body = body.string
    end

    ##
    # Loads the HTTP request metadata into the <tt>Resource</tt> object.
    def process_metadata
      if !@response
        raise HTTPClientError, "No response object, cannot process metadata."
      end
      if self.resource.metadata.empty?
        self.resource.metadata[:http_version] = @response.http_version
        self.resource.metadata[:status] = @response.status
        self.resource.metadata[:reason] = @response.reason
        self.resource.metadata[:headers] = @response.headers
      end
    end

    ##
    # This Hash subclass stores keys in a case-insensitive manner.
    class CaseInsensitiveHash < Hash
      def [](key)
        return super(key.downcase)
      end

      def []=(key, value)
        @key_labels ||= {}
        @key_labels[key.downcase] = key
        return super(key.downcase, value)
      end
      alias_method :store, :[]=

      def key_labels
        @key_labels ||= {}
        self.keys.map { |key| @key_labels[key] }
      end

      def to_hash
        # Iterate over key labels, and look up the value, stuffing everything
        # into a new Hash as we go.
        self.key_labels.inject({}) do |accu, label|
          accu[label] = self[label]
          accu
        end
      end

      def to_s
        return self.to_hash.to_s
      end

      def inspect
        return self.to_hash.inspect
      end
    end

    class HTTPResponse
      # The HTTP version returned.
      attr_accessor :http_version

      # The reason returned in the http response ("OK","File not found",etc.)
      attr_accessor :reason

      # The status code (as a string!)
      attr_accessor :status

      # The HTTP headers.
      def headers
        @headers ||= CaseInsensitiveHash.new
      end

      # The http body of the response, in the raw
      attr_accessor :body
    end

    # This class was borrowed from the RFuzz HTTP client, by Zed Shaw, with
    # very minor modifications.  Additional documentation added.

    ##
    # A simple class that using a <tt>StringIO</tt> object internally to allow
    # for faster and simpler "push back" semantics.  It lets you read from a
    # secondary <tt>IO</tt> object, parse what is needed, and then anything
    # remaining can be quickly pushed back into the buffer for the next read.
    class PushBackIO
      attr_accessor :secondary

      ##
      # Creates a new <tt>PushBackIO</tt> from a secondary <tt>IO</tt> object.
      #
      # @param [IO, StringIO] secondary
      #   The secondary <tt>IO</tt> object to wrap.
      def initialize(secondary, options)
        if !secondary.kind_of?(IO) && !secondary.kind_of?(StringIO)
          raise TypeError, "Expected IO or StringIO, got #{secondary.class}."
        end
        @secondary = secondary
        @buffer = StringIO.new
        @options = options
      end

      attr_accessor :secondary
      attr_accessor :buffer

      ##
      # Pushes the given string content back onto the stream for the 
      # next read to handle.
      #
      # @param [String] content
      #   The <tt>String</tt> to put back into the buffer.
      def push(content)
        @buffer.write(content) if content.length > 0; nil
      end

      ##
      # Pops a given number of bytes off the buffer.
      #
      # @param [Integer] n The number of bytes to pop.
      def pop(n)
        @buffer.rewind
        @buffer.read(n) || ""
      end

      ##
      # Resets the internal buffer.
      def reset
        @buffer.string = @buffer.read; nil
      end

      ##
      # First does a read from the internal buffer, and then appends anything
      # needed from the secondary <tt>IO</tt> to complete the request.
      #
      # @param [Integer] n The number of bytes to read.
      # @param [TrueClass, FalseClass] partial
      #   If partial is true then readpartial is used instead.
      # @return [String]
      #   The return value is guaranteed to be a <tt>String</tt>, and never
      #   <tt>nil</tt>.  If it returns a string of length 0 then there is
      #   nothing to read from the buffer (most likely because it's closed).
      #   It will also avoid reading from a secondary that's closed.
      def read(n, partial=false)
        r = pop(n)
        needs = n - r.length

        if needs > 0 && !@secondary.closed?
          sec = ""

          if partial
            begin
              protect do
                sec = @secondary.readpartial(needs)
              end
            rescue EOFError
              close
            end
          else
            protect do
              sec = @secondary.read(needs)
            end
          end

          r << (sec || "")

          # Finally, if there's nothing at all returned then this is bad.
          if r.length == 0
            raise HTTPClientError, "Server returned empty response."
          end
        end

        reset
        return r
      end

      ##
      # Flushes the secondary <tt>IO</tt> object.
      def flush
        protect { @secondary.flush }
      end

      ##
      # Writes to the secondary <tt>IO</tt> object.
      #
      # @param [String] content The <tt>String</tt> to write.
      def write(content)
        protect { @secondary.write(content) }
      end

      ##
      # Closes the secondary <tt>IO</tt> object.
      def close
        @secondary.close rescue nil
      end

    protected
      ##
      # Prevents calling methods on a closed <tt>IO</tt> object.
      #
      # @yield
      #   The block will only be called if the secondary <tt>IO</tt> object
      #   hasn't been closed.
      def protect
        if !@secondary.closed?
          yield
        else
          raise HTTPClientError, "Socket closed."
        end
      end
    end
  end
end
