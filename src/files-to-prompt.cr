# TODO: Write documentation for `Files::To::Prompt`

require "file"
require "io"
require "json"
require "option_parser"

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
    property convert_format : String = "asciidoc"
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
    def is_binary_file?(file_path)
      File.open(file_path, "rb") do |file|
        buffer = Bytes.new(8192)

        file.read(buffer)
        return buffer.any? { |byte| byte > 127 }
      end
    rescue ex : Exception
      # File not found
      return false
    end

    # Processes a single file
    def process_file(file_path, config)
      if is_binary_file?(file_path)
        error("Warning: Skipping binary file #{file_path}")
      else
        if config.nbconvert_name && file_path.ends_with?(".ipynb")
          convert_ipython_notebook(file_path, config)
        else
          output(file_path)
          output("---")
          output(File.read(file_path))
          output("---")
        end
      end
    rescue ex
      error("Error processing file #{file_path}: #{ex}")
    end

    # Converts an IPython notebook to the specified format
    def convert_ipython_notebook(file_path, config)
      tempfile = File.tempfile(File.basename(file_path))
      temp_file_path = tempfile.path

      begin
        # Copy the .ipynb file to the temporary directory
        File.copy(file_path, temp_file_path)

        # Run nbconvert
        convert_command = "#{config.nbconvert_name} --to #{config.convert_format} \"#{temp_file_path}\""
        system(convert_command)

        # Get converted file path
        converted_file_extension = config.convert_format == "markdown" ? ".md" : ".#{config.convert_format}"
        converted_file_path = File.join(Dir.tempdir, File.basename(file_path, ".ipynb") + converted_file_extension)

        # Output the converted file with the original file name and path
        output(file_path)
        output("---")
        output(File.read(converted_file_path))
        output("---")
      rescue ex
        error("Error converting .ipynb file #{file_path}: #{ex}")
      ensure
        tempfile.delete
        # Clean up the temporary directory
        end
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
      if File.exists?(gitignore_path)
        File.read_lines(gitignore_path)
          .reject { |line| line.strip.empty? || line.starts_with?("#") }
          .map(&.strip)
      else
        Array(String).new
      end
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

    # Parses file paths from stdin
    def parse_file_paths_from_stdin(stdin_data)
      stdin_data.lines
        .reject(&:empty?)
        .map(&:strip)
        .map { |line| line.include?(":") ? line.split(":")[0] : line }
        .select { |path| File.valid_path?(path) }
        .uniq
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
            config.convert_format = format
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

      # p! args
      # p! ARGV
      # p! paths_to_process

      if paths_to_process.empty?
        run( ["-h"])
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
