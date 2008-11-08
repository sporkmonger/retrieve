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

require "retrieve/client"

module Retrieve
  ##
  # The FileClient handles URIs with a file scheme.
  #
  # @example
  #   res = Retrieve.open("file:///home/sporkmonger/todo.txt", :mode => :read)
  #   #=> #<Retrieve::Resource:0x847c2c URI:file:///home/sporkmonger/todo.txt>
  #   res.read
  #   #=> "TODO: Write some code."
  #   res.close
  class FileClient < Retrieve::Client
    ##
    # The FileClient handles URIs with a file scheme.
    #
    # @return [String] The string, "file"
    def self.scheme
      return "file"
    end

    ##
    # Initializes a <tt>FileClient</tt> for a given <tt>Resource</tt>.
    def initialize(resource)
      super(resource)
      if resource.uri.query.to_s != "" || resource.uri.authority.to_s != ""
        raise ArgumentError,
          "Resource cannot be handled by client: '#{resource.uri}'"
      end
      @file = nil
    end

    ##
    # Opens a <tt>Resource</tt>.
    #
    # @option [Array, Symbol] mode
    #   The mode to open the file in.  May either be specified as a single
    #   Symbol, or as an Array of Symbols for multiple flags.
    #   Valid flags:
    #     :read, :write, :read_write, :append, :create,
    #     :exclusive, :no_ctty, :non_block
    #
    # @return [Retrieve::Resource] The client's resource.
    def open(options={})
      options = {
        :mode => [:read]
      }.merge(options)
      options[:mode] = [options[:mode]] unless options[:mode].kind_of?(Array)
      file_path = self.resource.uri.path
      mode_flags = 0
      for flag in options[:mode]
        case flag
        when :read
          mode_flags |= File::RDONLY
        when :write
          mode_flags |= File::WRONLY
        when :read_write
          mode_flags |= File::RDWR
        when :append
          mode_flags |= File::APPEND
        when :create
          mode_flags |= File::CREAT
        when :exclusive
          mode_flags |= File::EXCL
        when :no_ctty
          mode_flags |= File::NOCTTY
        when :non_block
          mode_flags |= File::NONBLOCK
        else
          raise ArgumentError, "Invalid mode flag: #{flag.inspect}"
        end
      end
      @file = File.open(file_path, mode_flags)
      return self.resource
    end

    ##
    # Reads the entire contents of the <tt>Resource</tt>.
    #
    # @param [Integer, NilClass] The number of bytes to read, or nil for all.
    #
    # @return [String] The contents of the file.
    def read(n=nil)
      raise IOError, "Missing stream." if @file == nil
      process_metadata
      return @file.read(n)
    end


    ##
    # Writes a <tt>String</tt> to the file.
    #
    # @param [String] The <tt>String</tt> to write.
    #
    # @return [Integer] The number of bytes written.
    def write(contents)
      raise IOError, "Missing stream." if @file == nil
      return @file.write(contents)
    end

    ##
    # Closes the <tt>Resource</tt>.
    def close
      raise IOError, "Missing stream." if @file == nil
      @file.close
      @file = nil
      return nil
    end

  private
    ##
    # Loads the file metadata into the <tt>Resource</tt> object.
    def process_metadata
      if self.resource.metadata.empty?
        file_stat = @file.stat
        # A useful subset of the metadata provided by File::Stat,
        # somewhat normalized.
        self.resource.metadata[:access_time] = file_stat.atime
        self.resource.metadata[:change_time] = file_stat.ctime
        self.resource.metadata[:modified_time] = file_stat.mtime
        self.resource.metadata[:file_type] = (case file_stat.ftype
        when "file"
          :file
        when "directory"
          :directory
        when "characterSpecial"
          :character_special
        when "blockSpecial"
          :block_special
        when "fifo"
          :fifo
        when "link"
          :link
        when "socket"
          :socket
        end)
        self.resource.metadata[:file_mode] = file_stat.mode
        self.resource.metadata[:user_id] = file_stat.uid
        self.resource.metadata[:group_id] = file_stat.gid
      end
    end
  end
end
