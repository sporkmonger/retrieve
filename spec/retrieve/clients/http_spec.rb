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
require "time"

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
    @replay.call(@request) if @replay
  end
end

describe Retrieve::HTTPClient, "with artificial responses" do
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

  it "should raise an error if there is no authority component" do
    (lambda do
      Retrieve.open("http:/") do |resource|
        # Should never get here.
      end
    end).should raise_error(ArgumentError)
  end

  it "should raise an error if a read is attempted after a close" do
    (lambda do
      response(<<-RESPONSE)
HTTP/1.1 200 OK\r
Content-Length: 17\r
\r
Example response.\r
\r
RESPONSE
      resource = Retrieve.open("http://example.com/")
      resource.close
      resource.read
    end).should raise_error(IOError)
  end

  it "should raise an error if a close is attempted after a close" do
    (lambda do
      response(<<-RESPONSE)
HTTP/1.1 200 OK\r
Content-Length: 17\r
\r
Example response.\r
\r
RESPONSE
      resource = Retrieve.open("http://example.com/")
      resource.close
      resource.close
    end).should raise_error(IOError)
  end

  it "should raise an error for a bogus start line" do
    (lambda do
      response(<<-RESPONSE)
This is not HTTP.
RESPONSE
      Retrieve.open("http://example.com/")
    end).should raise_error(Retrieve::HTTPClient::HTTPParserError)
  end

  it "should raise an error for a start line in the wrong place" do
    (lambda do
      response(<<-RESPONSE)


HTTP/1.1 200 OK\r
RESPONSE
      Retrieve.open("http://example.com/")
    end).should raise_error(Retrieve::HTTPClient::HTTPParserError)
  end

  it "should raise an error for a header in the wrong place" do
    (lambda do
      response(<<-RESPONSE)
HTTP/1.1 200 OK\r
Something here.\r
Content-Length: 17\r
\r
Example response.\r
\r
RESPONSE
      puts Retrieve.open("http://example.com/").read
    end).should raise_error(Retrieve::HTTPClient::HTTPParserError)
  end

  it "should handle a normal response" do
    replay do |request|
      request.should include("GET / HTTP/1.1\r\n")
      request.should include("Content-Length: 0\r\n")
      request.should include("Host: example.com\r\n")
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
      resource.metadata[:headers].inspect.should ==
        {"Content-Length" => "17"}.inspect
      resource.metadata[:headers].to_s.should ==
        {"Content-Length" => "17"}.to_s
    end
  end

  it "should handle a response missing Content-Length" do
    replay do |request|
      request.should include("GET / HTTP/1.1\r\n")
      request.should include("Content-Length: 0\r\n")
      request.should include("Host: example.com\r\n")
    end
    response(<<-RESPONSE)
HTTP/1.1 200 OK\r
\r
Example response.\r
\r
RESPONSE
    Retrieve.open("http://example.com/") do |resource|
      resource.read.should == "Example response.\r\n\r\n"
    end
  end

  it "should handle a response with a lot of headers" do
    replay do |request|
      request.should include("GET / HTTP/1.1\r\n")
      request.should include("Content-Length: 0\r\n")
      request.should include("Host: example.com\r\n")
    end
    response(<<-RESPONSE)
HTTP/1.1 200 OK\r
Content-Length: 17\r
Content-Type: text/plain\r
Connection: close\r
Cache-Control: private\r
Server: RSpec\r
P3P: CP='ALL IND DSP COR ADM CONo CUR CUSo IVAo IVDo PSA PSD TAI TELo'\r
X-Powered-By: Ruby\r
ETag: 42\r
Date: #{Time.now.gmtime.rfc822.gsub(/\-0000/, "GMT")}\r
\r
Example response.\r
\r
RESPONSE
    Retrieve.open("http://example.com/") do |resource|
      resource.metadata[:headers]["Content-Length"].should == "17"
      resource.metadata[:headers]["Content-Type"].should == "text/plain"
      resource.metadata[:headers]["Connection"].should == "close"
      resource.metadata[:headers]["Cache-Control"].should == "private"
      resource.metadata[:headers]["Server"].should == "RSpec"
      resource.metadata[:headers]["P3P"].should ==
        "CP='ALL IND DSP COR ADM CONo CUR CUSo IVAo IVDo PSA PSD TAI TELo'"
      resource.metadata[:headers]["X-Powered-By"].should == "Ruby"
      resource.metadata[:headers]["ETag"].should == "42"
      resource.metadata[:headers]["Date"].should_not == nil
    end
  end

  it "should headers to be accessed in a case-insensitive fashion" do
    replay do |request|
      request.should include("GET / HTTP/1.1\r\n")
      request.should include("Content-Length: 0\r\n")
      request.should include("Host: example.com\r\n")
    end
    response(<<-RESPONSE)
HTTP/1.1 200 OK\r
Content-Length: 17\r
Content-type: text/plain\r
CoNneCtIoN: close\r
Cache-Control: private\r
Server: RSpec\r
P3p: CP='ALL IND DSP COR ADM CONo CUR CUSo IVAo IVDo PSA PSD TAI TELo'\r
X-powered-by: Ruby\r
ETag: 42\r
date: #{Time.now.gmtime.rfc822.gsub(/\-0000/, "GMT")}\r
\r
Example response.\r
\r
RESPONSE
    Retrieve.open("http://example.com/") do |resource|
      resource.metadata[:headers]["Content-Length"].should == "17"
      resource.metadata[:headers]["content-type"].should == "text/plain"
      resource.metadata[:headers]["Connection"].should == "close"
      resource.metadata[:headers]["cache-control"].should == "private"
      resource.metadata[:headers]["Server"].should == "RSpec"
      resource.metadata[:headers]["p3P"].should ==
        "CP='ALL IND DSP COR ADM CONo CUR CUSo IVAo IVDo PSA PSD TAI TELo'"
      resource.metadata[:headers]["x-Powered-By"].should == "Ruby"
      resource.metadata[:headers]["ETAG"].should == "42"
      resource.metadata[:headers]["Date"].should_not == nil
    end
  end

  it "should not explode if there are no headers" do
    replay do |request|
      request.should include("GET / HTTP/1.1\r\n")
      request.should include("Content-Length: 0\r\n")
      request.should include("Host: example.com\r\n")
    end
    response("HTTP/1.1 200 OK\r\n\r\n")
    Retrieve.open("http://example.com/") do |resource|
      resource.read.should == ""
    end
  end

  it "should handle a Transfer-Encoding of 'chunked' properly" do
    replay do |request|
      request.should include("GET / HTTP/1.1\r\n")
      request.should include("Content-Length: 0\r\n")
      request.should include("Host: example.com\r\n")
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

  it "should raise an error for bogus chunking" do
    replay do |request|
      request.should include("GET / HTTP/1.1\r\n")
      request.should include("Content-Length: 0\r\n")
      request.should include("Host: example.com\r\n")
    end
    response(<<-RESPONSE)
HTTP/1.1 200 OK\r
Transfer-Encoding: chunked\r
\r
This is a bogus chunked response.\r
\r
RESPONSE
    (lambda do
      Retrieve.open("http://example.com/")
    end).should raise_error(Retrieve::HTTPClient::HTTPParserError)
  end

  it "should raise an error for bogus chunking" do
    replay do |request|
      request.should include("GET / HTTP/1.1\r\n")
      request.should include("Content-Length: 0\r\n")
      request.should include("Host: example.com\r\n")
    end
    response(<<-RESPONSE)
HTTP/1.1 200 OK\r
Transfer-Encoding: chunked\r
\r
A  \r
This is a bogus chunked response.\r
0    \r
\r
RESPONSE
    (lambda do
      Retrieve.open("http://example.com/")
    end).should raise_error(Retrieve::HTTPClient::HTTPParserError)
  end

  it "should send out proper cookie headers with the :cookies option" do
    replay do |request|
      request.should include("GET / HTTP/1.1\r\n")
      request.should include("Content-Length: 0\r\n")
      request.should include("Host: example.com\r\n")
      request.should include("Cookie: foo=bar\r\n")
    end
    response(<<-RESPONSE)
HTTP/1.1 200 OK\r
Content-Length: 17\r
\r
Example response.\r
\r
RESPONSE
    Retrieve.open("http://example.com/", :cookies => {
      "foo" => "bar"
    }) do |resource|
      resource.read.should == "Example response."
    end
  end

  it "should send out proper cookie headers with the :cookies option" do
    replay do |request|
      request.should include("GET / HTTP/1.1\r\n")
      request.should include("Content-Length: 0\r\n")
      request.should include("Host: example.com\r\n")
      request.should include("Cookie: one=two\r\n")
      request.should include("Cookie: foo=bar\r\n")
      request.should include("Cookie: foo=baz\r\n")
    end
    response(<<-RESPONSE)
HTTP/1.1 200 OK\r
Content-Length: 17\r
\r
Example response.\r
\r
RESPONSE
    Retrieve.open("http://example.com/", :cookies => {
      "foo" => ["bar", "baz"], "one" => "two"
    }) do |resource|
      resource.read.should == "Example response."
    end
  end

  it "should send out proper cookie headers with the :cookies option" do
    replay do |request|
      request.should include("GET / HTTP/1.1\r\n")
      request.should include("Content-Length: 0\r\n")
      request.should include("Host: example.com\r\n")
      request.should include("Cookie: a=b\r\n")
      request.should include("Cookie: one=two\r\n")
      request.should include("Cookie: foo=bar\r\n")
      request.should include("Cookie: foo=baz\r\n")
    end
    response(<<-RESPONSE)
HTTP/1.1 200 OK\r
Content-Length: 17\r
\r
Example response.\r
\r
RESPONSE
    Retrieve.open("http://example.com/", :headers => {
      "Cookie" => "a=b"
    }, :cookies => {
      "foo" => ["bar", "baz"], "one" => "two"
    }) do |resource|
      resource.read.should == "Example response."
    end
  end
end

describe Retrieve::HTTPClient, "with real responses" do
  it "should timeout correctly" do
    (lambda do
      Retrieve.open("http://www.google.com/", :timeout => 0.001)
    end).should raise_error(Retrieve::HTTPClient::HTTPClientError)
  end

  it "should retrieve a live page without error" do
    Retrieve.open("http://www.google.com/") do |resource|
      resource.read.should_not == nil
      resource.metadata[:status].should_not == nil
      resource.metadata[:headers].should_not == nil
    end
  end
end

describe Retrieve::HTTPClient::PushBackIO do
  it "should raise an error if wrapping a non-IO object" do
    (lambda do
      Retrieve::HTTPClient::PushBackIO.new("bogus")
    end).should raise_error(TypeError)
  end
end
