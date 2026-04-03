# Helper module for running command-line tools. Include this in extractors
# or processors that need to shell out to CLI tools.
#
# ```
# struct ColourspaceFromIdentify
#   include Latch::Extractor
#   include Latch::RunCommand
#
#   def extract(uploaded_file, metadata, **options) : String?
#     run_command("magick", ["identify", "-format", "%[colorspace]"], uploaded_file)
#   end
# end
# ```
#
module Latch::RunCommand
  # Runs the given command with the given args. Returns the stripped stdout
  # string if the command was successful, nil otherwise.
  private def run_command(
    command : String,
    args : Array(String),
  ) : String?
    result, stdout, stderr = run_command_process(command, args)

    return stdout.to_s.strip if result.success?

    run_command_log_debug(command, args, stderr)
  rescue File::NotFoundError
    raise run_command_cli_error(command)
  end

  # Runs the given command, piping the IO to stdin. Appends `"-"` to args so
  # the tool reads from stdin. Rewinds the input after execution.
  private def run_command(
    command : String,
    args : Array(String),
    input : IO,
  ) : String?
    result, stdout, stderr = run_command_process(command, args + ["-"], input: input)
    input.rewind

    return stdout.to_s.strip if result.success?

    run_command_log_debug(command, args, stderr)
  rescue File::NotFoundError
    raise run_command_cli_error(command)
  end

  # Convenience overload accepting an `UploadedFile` instead of a raw `IO`.
  private def run_command(
    command : String,
    args : Array(String),
    uploaded_file : Lucky::UploadedFile,
  ) : String?
    run_command(command, args, uploaded_file.tempfile)
  end

  private def run_command_process(
    command : String,
    args : Array(String),
    **input,
  ) : {Process::Status, IO, IO}
    stdout, stderr = IO::Memory.new, IO::Memory.new
    result = Process.run(command, **input, args: args, output: stdout, error: stderr)
    {result, stdout, stderr}
  end

  private def run_command_log_debug(command, args, stderr) : Nil
    Log.debug do
      "Unable to run `#{command} #{args.join(' ')}` (#{stderr})"
    end
  end

  private def run_command_cli_error(command)
    CliToolNotFound.new("The `#{command}` command-line tool is not installed")
  end
end
