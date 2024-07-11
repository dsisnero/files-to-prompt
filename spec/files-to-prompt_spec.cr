require "./spec_helper"

  def create_tempfile(filename, content)
    tempfile = File.tempfile(filename)
    tempfile.write(content)
    tempfile.close
    tempfile.path
  end

def capture_output(args)
    output = IO::Memory.new
    error = IO::Memory.new
    original_stdout = STDOUT
    original_stderr = STDERR

    STDOUT.reopen(output)
    STDERR.reopen(error)

    begin
      FilesToPrompt::App.new.run(args)
    ensure
      STDOUT.reopen(original_stdout)
      STDERR.reopen(original_stderr)
    end

    {output: output.to_s, error: error.to_s}
  end

describe "files-to-prompt" do
  # Helper function to create a temporary file with content
  # Helper function to run the app with arguments and capture output
  # def capture_output(args)
  #   output = IO::Memory.new
  #   error = IO::Memory.new
  #   original_stdout = STDOUT
  #   original_stderr = STDERR

  #   STDOUT = output
  #   STDERR = error

  #   begin
  #     FilesToPrompt::App.new.run(args)
  #   ensure
  #     STDOUT = original_stdout
  #     STDERR = original_stderr
  #   end

  #   {output: output.to_s, error: error.to_s}
  # end

  describe "#run" do
    context "with no arguments" do
      it "prints the help message" do
        output, error = capture_output([] of String).values
        output.should contain("Usage: files-to-prompt [options] <paths>")
        error.should be_empty
      end
    end

    context "with -v or --version flag" do
      it "prints the version number" do
        ["-v", "--version"].each do |flag|
          output, error = capture_output([flag]).values
          output.should contain("files-to-prompt.cr version #{FilesToPrompt::VERSION}")
          error.should be_empty
        end
      end
    end

    context "with valid file path" do
      it "prints the file content" do
        tempfile = create_tempfile("test.txt", "This is a test file.")
        output, error = capture_output([tempfile]).values
        output.should contain("---\nThis is a test file.\n---")
        error.should be_empty
      end
    end

    context "with valid directory path" do
      it "prints the content of all files in the directory" do
        Dir.mktmpdir do |dir|
          create_tempfile(File.join(dir, "file1.txt"), "Content of file 1.")
          create_tempfile(File.join(dir, "file2.txt"), "Content of file 2.")

          output, error = capture_output([dir]).values

          output.should contain("---\nContent of file 1.\n---")
          output.should contain("---\nContent of file 2.\n---")
          error.should be_empty
        end
      end
    end

    context "with -H or --contain-hidden flag" do
      it "contains hidden files and directories" do
        Dir.mktmpdir do |dir|
          create_tempfile(File.join(dir, ".hidden_file.txt"), "Content of hidden file.")
          Dir.mkdir(File.join(dir, ".hidden_dir"))

          output, _ = capture_output([dir, "-H"]).values

          output.should contain("---\nContent of hidden file.\n---")
        end
      end
    end

    context "with -G or --ignore-gitignore flag" do
      it "ignores .gitignore files" do
        Dir.mktmpdir do |dir|
          create_tempfile(File.join(dir, ".gitignore"), "*.txt")
          create_tempfile(File.join(dir, "file.txt"), "Content of file.")

          output, _ = capture_output([dir, "-G"]).values

          output.should contain("---\nContent of file.\n---")
        end
      end
    end

    context "with -i or --ignore flag" do
      it "ignores files matching the pattern" do
        Dir.mktmpdir do |dir|
          create_tempfile(File.join(dir, "file1.txt"), "Content of file 1.")
          create_tempfile(File.join(dir, "file2.md"), "Content of file 2.")

          output, _ = capture_output([dir, "-i", "*.txt"]).values

          output.should_not contain("Content of file 1.")
          output.should contain("Content of file 2.")
        end
      end
    end

    context "with -o or --output flag" do
      it "writes output to the specified file" do
        tempfile = create_tempfile("test.txt", "This is a test file.")
        output_file = "output.txt"

        capture_output([tempfile, "-o", output_file])
        File.read(output_file).should contain("---\nThis is a test file.\n---")

        File.delete(output_file)
      end
    end

    context "with -e or --error flag" do
      it "writes errors to the specified file" do
        error_file = "error.txt"

        capture_output(["nonexistent_file.txt", "-e", error_file])

        File.read(error_file).should contain("Path does not exist: nonexistent_file.txt")

        File.delete(error_file)
      end
    end

    context "with -n or --nbconvert flag" do
      it "converts .ipynb files using nbconvert" do
        # Skip this test if nbconvert is not installed
        next if `which nbconvert`.empty?

        Dir.mktmpdir do |dir|
          ipynb_content = JSON.build do |json|
             json.object do
               json.field "cells" ,
                  json.array do 
                    json.object do
                     json.field "celltype", "markdown"
                     json.field "source",
                        json.array do 
                          json.string "# This is a markdown header"
                        end
                   end
                 end
              end
          end.to_s
          create_tempfile(File.join(dir, "notebook.ipynb"), ipynb_content)

          output, error = capture_output([dir, "-n", "nbconvert", "-f", "markdown"]).values

          output.should contain("# This is a markdown header")
          error.should be_empty
        end
      end

      it "outputs an error message if nbconvert is not found" do
        Dir.mktmpdir do |dir|
          ipynb_content = JSON.build do |json| 
            json.object do 
              json.field "cells", 
                json.array do
                  json.object do
                    json.field "cell_type", "markdown"
                    json.field "source",
                      json.array do 
                        json.string "# This is a markdown header"
                      end
                  end
              end
           end
        end.to_s
          create_tempfile(File.join(dir, "notebook.ipynb"), ipynb_content)

          output, error = capture_output([dir, "-n", "nonexistent_nbconvert", "-f", "markdown"]).values

          output.should be_empty
          error.should contain("Warning: nonexistent_nbconvert command not found")
        end
      end
    end

    context "with -f or --format flag" do
      # Tests for -f/--format flag are covered in the "-n or --nbconvert flag" context
    end
  end
end
