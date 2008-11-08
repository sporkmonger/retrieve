# coding:utf-8
#--
# Addressable, Copyright (c) 2006-2007 Bob Aman
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
#++

$:.unshift(File.expand_path(File.dirname(__FILE__) + '/../../../lib'))
$:.uniq!

require "retrieve/clients/http"

class ExpectationIO < StringIO
  def initialize
    @request_io = StringIO.new
    @request = nil
    super
  end

  alias_method :readpartial, :read

  def request
    return @request
  end

  def response=(new_response)
    self.reopen
    self.original_write(new_response)
    self.rewind
  end

  def replay(&block)
    @replay = block
  end

  alias_method :original_write, :write

  def write(contents)
    @request_io.write(contents)
  end

  def flush
    @request_io.rewind
    @request = @request_io.read
    @replay.call(@request)
  end
end

describe Retrieve::HTTPClient do
  def replay(&block)
    @io.replay(&block)
  end

  def response(new_response)
    @io.response = new_response
  end

  before do
    @io = ExpectationIO.new
    TCPSocket.stub!(:new).with("example.com", 80).and_return(@io)
  end

  it "should handle a normal response" do
    replay do |request|
      request.should ==
        "GET / HTTP/1.1\r\nContent-Length: 0\r\nHost: example.com\r\n\r\n"
    end
    response(<<-RESPONSE)
HTTP/1.1 200 OK\r
Content-Length: 17\r
\r
Example response.\r
\r
RESPONSE
    Retrieve.open("http://example.com/") do |resource|
      resource.read.should == "Example response."
    end
  end

  it "should not explode if there are no headers" do
    replay do |request|
      request.should ==
        "GET / HTTP/1.1\r\nContent-Length: 0\r\nHost: example.com\r\n\r\n"
    end
    response("HTTP/1.1 200 OK\r\n\r\n")
    Retrieve.open("http://example.com/") do |resource|
      resource.read.should == ""
    end
  end

  it "should handle a Transfer-Encoding of 'chunked' properly" do
    replay do |request|
      request.should ==
        "GET / HTTP/1.1\r\nContent-Length: 0\r\nHost: example.com\r\n\r\n"
    end
    response(<<-RESPONSE)
HTTP/1.1 200 OK\r
Transfer-Encoding: chunked\r
\r
A  \r
This is a \r
11\r
chunked response.\r
0    \r
\r
RESPONSE
    Retrieve.open("http://example.com/") do |resource|
      resource.read.should == "This is a chunked response."
    end
  end
end
