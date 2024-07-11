require "file"
require "io"
require "json"
require "option_parser"
require "file_utils"

module FilesToPrompt
  VERSION = "0.1.0"

  # Configuration for output redirection
  struct OutputConfig
    # Filename to redirect stdout
    property stdout_file : String? = nil
    # Filename to redirect stderr
    property stderr_file : String? = nil
  end

  # Configuration for file processing
  struct ProcessingConfig
    # Include hidden files and directories
    property? include_hidden = false
    # Ignore .gitignore files
    property? ignore_gitignore = false
    # Ignore patterns
    property ignore_patterns = [] of String
    # .gitignore rules
    property gitignore_rules = [] of String
    # nbconvert tool name/path
    property nbconvert_name : String? = nil
    # Format for .ipynb conversion
    property nbconvert_format : String = "asciidoc"
  end

  class App
    property config : ProcessingConfig
    property paths_to_process : Array(String)
    property output_config : OutputConfig
    property paths_to_process : Array(String) = [] of String

    def initialize
      @config = ProcessingConfig.new
      @paths_to_process = [] of String
      @output_config = OutputConfig.new
    end

    # Output to console or stdout file
    def output(*args)
      if output_file = output_config.stdout_file
        File.open(output_file, "a") do |file|
          file.puts(args.join(" "))
        end
      else
        puts(*args)
      end
    end

    # Output error to console or stderr file
    def error(*args)
      if error_file = output_config.stderr_file
        File.open(error_file, "a") do |file|
          file.puts(args.join(" "))
        end
      else
        STDERR.puts(*args)
      end
    end

    # Checks if a file is binary
    def binary_file?(file_path, chunk_size = 8192) : Bool
      File.open(file_path, "rb") do |file|
        buffer = Bytes.new(chunk_size)

        bytes_read = file.read(buffer)
        return buffer.any? { |byte| byte > 127 } if bytes_read
      end
      false
    rescue ex : Exception
      # File not found
      false
    end

    # Converts a Jupyter Notebook file to AsciiDoc format.
    def convert_to_asciidoc(ipynb_data : JSON::Any) : String
      asciidoc_content = ""
      ipynb_data["cells"].as_a.each do |cell|
        case cell["cell_type"].as_s
        when "code"
          asciidoc_content += "+*In[#{cell["execution_count"]}]:*+\n[source, ipython3]\n----\n#{cell["source"].as_a.join("")}\n----\n\n"
          cell["outputs"].as_a.each do |output|
            if output["data"]["text/plain"]?
              asciidoc_content += "+*Out[#{cell["execution_count"]}]:*+\n----\n#{output["data"]["text/plain"]}\n----\n\n"
            end
          end
        when "markdown"
          asciidoc_content += "#{cell["source"].as_a.join("")}\n\n"
        end
      end
      asciidoc_content
    end

    # Converts a Jupyter Notebook file to Markdown format.
    def convert_to_markdown(ipynb_data : JSON::Any) : String
      markdown_content = ""
      ipynb_data["cells"].as_a.each do |cell|
        case cell["cell_type"].as_s
        when "code"
          markdown_content += "```python\n#{cell["source"].as_a.join("")}\n```\n\n"
          cell["outputs"].as_a.each do |output|
            markdown_content += "```\n#{output["data"]["text/plain"]}\n```\n\n" if output["data"]["text/plain"]?
          end
        when "markdown"
          markdown_content += "#{cell["source"].as_a.join("")}\n\n"
        end
      end
      markdown_content
    end

    # Converts a Jupyter Notebook file to the specified format using internal conversion.
    def convert_notebook_internal(file_path : String, config : ProcessingConfig)
      ipynb_contents = File.read(file_path)
      ipynb_data = JSON.parse(ipynb_contents)

      converted_content = if config.nbconvert_format == "asciidoc"
                            convert_to_asciidoc(ipynb_data)
                          else
                            convert_to_markdown(ipynb_data)
                          end

      output file_path
      output "---"
      output converted_content
      output "---"
    rescue ex : Exception
      error "Error converting .ipynb file #{file_path}: #{ex}"
    end

    # Converts a Jupyter Notebook file to the specified format using external conversion.
    def convert_notebook_external(file_path : String, config : ProcessingConfig)
      temp_file = File.tempfile("files-to-prompt-")
      temp_file_path = temp_file.path

      begin
        FileUtils.cp file_path, temp_file_path

        convert_command = "#{config.nbconvert_name} --to #{config.nbconvert_format} \"#{temp_file_path}\""
        begin
          system(convert_command)
        rescue ex : Exception
          error "Error running #{config.nbconvert_name}: #{ex}"
          return
        end

        converted_file_extension = config.nbconvert_format == "markdown" ? ".md" : ".#{config.nbconvert_format}"
        converted_file_path = File.join(Dir.tempdir, "#{File.basename(file_path, ".ipynb")}#{converted_file_extension}")
        converted_file_contents = File.read(converted_file_path)

        output file_path
        output "---"
        output converted_file_contents
        output "---"
      rescue ex : Exception
        error "Error converting .ipynb file #{file_path}: #{ex}"
      ensure
        temp_file.close
        FileUtils.rm_rf temp_file_path
      end
    end

    # Processes a single file.
    def process_file(file_path : String, config : ProcessingConfig)
      if config.nbconvert_name && file_path.ends_with?(".ipynb")
        if config.nbconvert_name == "internal"
          convert_notebook_internal(file_path, config)
        else
          convert_notebook_external(file_path, config)
        end
      elsif binary_file?(file_path)
        error "Warning: Skipping binary file #{file_path}"
      else
        file_contents = File.read(file_path)
        output file_path
        output "---"
        output file_contents
        output "---"
      end
    rescue ex : Exception
      error "Error processing file #{file_path}: #{ex}"
    end

    # Checks if a file should be ignored
    def should_ignore?(file_path, config)
      path = Path[file_path]
      patterns = config.gitignore_rules + config.ignore_patterns
      patterns.any? do |pattern|
        File.match?(pattern, path.basename) ||
          (pattern.ends_with?("/") && File.match?(pattern[0..-2], path.relative_to path.dirname))
      end
    end

    # Reads .gitignore rules
    def read_gitignore(dir_path)
      gitignore_path = File.join(dir_path, ".gitignore")
      return [] of String unless File.exists?(gitignore_path)
      File.read_lines(gitignore_path)
        .reject { |line| line.strip.empty? || line.starts_with?("#") }
        .map(&.strip)
    end

    # Processes a file or directory path
    def process_path(path_to_process, config)
      if File.file?(path_to_process)
        # Process a single file
        process_file(path_to_process, config) unless should_ignore?(path_to_process, config)
      elsif File.directory?(path_to_process)
        # Process directory
        new_config = config.dup
        if config.gitignore_rules.empty?
          new_config.gitignore_rules = read_gitignore(path_to_process) unless config.ignore_gitignore?
        end
        Dir.children(path_to_process)
          .select { |entry| config.include_hidden? || !entry.starts_with?(".") }
          .each do |entry|
            full_path = File.join(path_to_process, entry)
            if File.file?(full_path) && !should_ignore?(full_path, new_config)
              process_file(full_path, new_config)
            elsif File.directory?(full_path) && !should_ignore?(full_path, new_config)
              process_path(full_path, new_config)
            end
          end
      else
        error("Skipping #{path_to_process}: unsupported file type")
      end
    end

    # Reads the input from stdin.
    def read_stdin : String
      input = ""
      until (line = STDIN.gets).nil?
        input += "#{line}\n"
      end
      input
    end

    # Parses the file paths from the stdin input.
    def parse_file_paths_from_stdin(stdin_data : String) : Array(String)
      file_paths_from_stdin = [] of String
      seen_file_paths = Set(String).new
      stdin_data.each_line do |line|
        file_path = line.strip
        next if file_path.empty?
        if file_path.includes?(":")
          parts = file_path.split(":")
          if File.exists?(parts[0]) && !seen_file_paths.includes?(parts[0])
            seen_file_paths.add(parts[0])
            file_paths_from_stdin << parts[0]
          end
        elsif File.exists?(file_path) && !seen_file_paths.includes?(file_path)
          seen_file_paths.add(file_path)
          file_paths_from_stdin << file_path
        end
      end
      file_paths_from_stdin
    end

    # Parses file paths from stdin
    def parse_file_paths_from_stdin_bak(stdin_data)
      stdin_data.lines
        .reject(&:empty?)
        .map(&:strip)
        .map { |line| line.include?(":") ? line.split(":")[0] : line }
        .select { |path| File.file?(path) }
        .uniq!
    end

    def run(args)
      # Parse command-line arguments using OptionParser
      OptionParser.new do |opts|
        opts.banner = "Usage: files-to-prompt [options] <paths>"

        opts.on("-v", "--version", "Print version and exit") do
          output("files-to-prompt.cr version #{VERSION}")
          exit
        end

        opts.on("-H", "--include-hidden", "Include hidden files and directories") do
          config.include_hidden = true
        end

        opts.on("-G", "--ignore-gitignore", "Ignore .gitignore files") do
          config.ignore_gitignore = true
        end

        opts.on("-i PATTERN", "--ignore PATTERN", "Ignore files matching the pattern") do |pattern|
          config.ignore_patterns << pattern
        end

        opts.on("-o FILE", "--output FILE", "Output to file instead of stdout") do |file|
          output_config.stdout_file = file
        end
        opts.on("-e FILE", "--error FILE", "Output error to file instead of stderr") do |file|
          output_config.stderr_file = file
        end

        opts.on("-n TOOL", "--nbconvert TOOL", "Path to nbconvert tool") do |tool|
          config.nbconvert_name = tool
          begin
            system("#{config.nbconvert_name} --version")
          rescue ex
            error("Warning: #{config.nbconvert_name} command not found")
            config.nbconvert_name = nil
          end
        end

        opts.on("-f FORMAT", "--format FORMAT", "Format for .ipynb conversion (asciidoc or markdown)") do |format|
          if ["asciidoc", "markdown"].includes?(format)
            config.nbconvert_format = format
          else
            error("Error: Unsupported format '#{format}', use 'asciidoc' or 'markdown'")
            exit
          end
        end

        opts.on("-h", "--help", "Prints this help") do
          puts opts
          exit
        end

        opts.unknown_args do |args|
          @paths_to_process = args if args.size > 0
        end
      end.parse(args)

      if paths_to_process.empty? && !STDIN.tty?
        stdin_data = read_stdin
        file_paths_from_stdin = parse_file_paths_from_stdin(stdin_data)
        paths_to_process.concat file_paths_from_stdin
      end

      # p! args
      # p! ARGV
      # p! paths_to_process
      # p! ARGF

      if paths_to_process.empty?
        run(["-h"])
      end

      # Remaining arguments are paths to process

      # Process input from stdin
      # if !STDIN.tty?
      #   paths_to_process.concat ARGF
      # end

      # Process paths
      paths_to_process.each do |path|
        if File.exists?(path)
          process_path(path, config)
        else
          error("Path does not exist: #{path}")
        end
      end
    end
  end
end

FilesToPrompt::App.new.run(ARGV)
