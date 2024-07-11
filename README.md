# files-to-prompt

A command-line tool to prepare multiple files for ingestion to a large language model (LLM) prompt.

This tool reads a list of files and directories and outputs their content in a format suitable for an LLM prompt. It supports various features like including hidden files, ignoring files based on patterns or `.gitignore`, and converting Jupyter Notebook (.ipynb) files to Markdown or AsciiDoc.

## Installation

```bash
crystal build src/files-to-prompt.cr --release -o files-to-prompt
chmod +x files-to-prompt
# Optionally move the binary to a directory in your PATH
sudo mv files-to-prompt /usr/local/bin/
```

## Usage

```
Usage: files-to-prompt [options] <paths>

Options:
  -v, --version                Print version and exit
  -H, --include-hidden          Include hidden files and directories
  -G, --ignore-gitignore        Ignore .gitignore files
  -i PATTERN, --ignore PATTERN  Ignore files matching the pattern
  -o FILE, --output FILE        Output to file instead of stdout
  -e FILE, --error FILE         Output error to file instead of stderr
  -n TOOL, --nbconvert TOOL     Path to nbconvert tool
  -f FORMAT, --format FORMAT   Format for .ipynb conversion (asciidoc or markdown)
  -h, --help                   Prints this help

<paths>                        Paths to files or directories to process. If no path is provided, reads from stdin.
```

## Examples

### Process specific files:

```bash
files-to-prompt README.md src/files-to-prompt.cr
```

### Process all files in a directory:

```bash
files-to-prompt src
```

### Process files from stdin:

```bash
find src -name "*.cr" | files-to-prompt
```

### Include hidden files:

```bash
files-to-prompt -H src
```

### Ignore files matching a pattern:

```bash
files-to-prompt -i "*.log" src
```

### Convert Jupyter Notebook to Markdown:

```bash
files-to-prompt -n jupyter nbconvert -f markdown notebook.ipynb
```

## Output Format

The tool outputs each file's content with the following format:

```
<file_path>
---
<file_content>
---
```

This format allows LLMs to easily identify individual files and their content within the prompt.

## Contributing

1. Fork the repository (<https://github.com/dsisnero/files-to-prompt/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [dsisnero](https://github.com/dsisnero) - creator and maintainer```
