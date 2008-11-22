namespace :metrics do
  namespace :benchmark do
    task :http do
      require "retrieve/clients/http"
      require "net/http"
      require "curb"
      require "rfuzz/client"
      require "benchmark"

      uri = ENV["URI"] || "http://localhost:80/"
      iterations = (ENV["N"] || "300").to_i

      # Make a request before benchmarking to avoid start-up time skewing
      `curl \"#{uri}\" 2>&1`

      puts "Running #{iterations} iterations with Retrieve..."
      result = Benchmark.measure do
        iterations.times do
          Retrieve.open(uri) do |resource|
            resource.read
          end
        end
      end
      puts "#{result.real} seconds."

      puts "Running #{iterations} iterations with Net/HTTP..."
      result = Benchmark.measure do
        iterations.times do
          Net::HTTP.get(URI.parse(uri))
        end
      end
      puts "#{result.real} seconds."

      puts "Running #{iterations} iterations with Curb..."
      result = Benchmark.measure do
        iterations.times do
          Curl::Easy.http_get(uri).body_str
        end
      end
      puts "#{result.real} seconds."

      puts "Running #{iterations} iterations with C Curl..."
      result = Benchmark.measure do
        iterations.times do
          `curl \"#{uri}\" 2>&1`
        end
      end
      puts "#{result.real} seconds."

      puts "Running #{iterations} iterations with Apache Bench..."
      result = Benchmark.measure do
        `ab -n #{iterations} \"#{uri}\" 2>&1`
      end
      puts "#{result.real} seconds."

      puts "Running #{iterations} iterations with RFuzz..."
      result = Benchmark.measure do
        iterations.times do
          parsed_uri = Addressable::URI.parse(uri)
          host, port = parsed_uri.host, parsed_uri.inferred_port
          RFuzz::HttpClient.new(host, port).get(parsed_uri.omit(
            :scheme, :authority, :fragment
          ).to_s)
        end
      end
      puts "#{result.real} seconds."
    end
  end

  task :lines do
    lines, codelines, total_lines, total_codelines = 0, 0, 0, 0
    for file_name in FileList["lib/**/*.rb"]
      f = File.open(file_name)
      while line = f.gets
        lines += 1
        next if line =~ /^\s*$/
        next if line =~ /^\s*#/
        codelines += 1
      end
      puts "L: #{sprintf("%4d", lines)}, " +
        "LOC #{sprintf("%4d", codelines)} | #{file_name}"
      total_lines     += lines
      total_codelines += codelines

      lines, codelines = 0, 0
    end

    puts "Total: Lines #{total_lines}, LOC #{total_codelines}"
  end
end
