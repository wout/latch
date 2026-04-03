require "../../spec_helper"

# These tests verify compile-time validation of the `variant` macro against
# the `@[Latch::VariantOptions(...)]` annotation.

describe "variant macro compile-time validation" do
  it "rejects unknown option keys" do
    result = compile_snippet %(
      struct TestProcessor
        include Latch::Processor::Magick
        variant large, reisze: "50x50"
      end
    )

    result[:success].should be_false
    result[:stderr].should contain("Unknown variant option 'reisze'")
  end

  it "rejects missing required options" do
    result = compile_snippet %(
      @[Latch::VariantOptions(resize: String, gravity: String?)]
      module TestProcessorModule
        include Latch::Processor
        macro included
          def self.process(stored_file, storage, name, **options) : Nil; end
        end
      end

      struct TestProcessor
        include TestProcessorModule
        variant large, gravity: "center"
      end
    )

    result[:success].should be_false
    result[:stderr].should contain("Missing required option 'resize'")
  end

  it "accepts valid options" do
    result = compile_snippet %(
      struct TestProcessor
        include Latch::Processor::Magick
        variant large, resize: "50x50"
        variant small, resize: "10x10", gravity: "center"
      end
    )

    result[:success].should be_true
  end
end

PROJECT_ROOT = Path[{{ __DIR__ }}].join("../../..").normalize.to_s

private def compile_snippet(code : String)
  snippet = %(require "./src/latch"\n#{code})
  path = File.join(PROJECT_ROOT, "_variant_test.cr")
  File.write(path, snippet)

  stdout = IO::Memory.new
  stderr = IO::Memory.new
  status = Process.run(
    "crystal", ["build", "--no-codegen", path],
    output: stdout, error: stderr,
    chdir: PROJECT_ROOT,
  )
  File.delete(path)

  {success: status.success?, stderr: stderr.to_s, stdout: stdout.to_s}
end
