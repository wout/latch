require "../run_command"

# Processor module for ImageMagick-based image transformations. Include this
# module and use the `variant` macro to define variants. Each option key
# becomes a `-key value` pair passed to `magick convert`.
#
# ```
# struct AvatarSizesProcessor
#   include Latch::Processor::Magick
#
#   variant large, resize: "2000x2000"
#   variant small, resize: "200x200", gravity: "center"
# end
# ```
#
@[Latch::VariantOptions(
  resize: String?,
  gravity: String?,
  extent: String?,
  crop: String?,
  quality: String?,
)]
module Latch::Processor::Magick
  include Latch::Processor

  process do
    args = process_build_args(variant_options)
    output = File.tempfile("latch-variant")
    run_magick_convert(tempfile.path, args, output.path)
    output.tap(&.rewind)
  end

  macro included
    extend Latch::RunCommand

    {%
      anno = @type.ancestors
        .map(&.annotation(Latch::VariantOptions))
        .first
    %}

    # Runs `magick convert`, falling back to `convert` for ImageMagick 6.
    private def self.run_magick_convert(input : String, args : Array(String), output : String) : Nil
      run_command("magick", ["convert", input] + args + [output])
    rescue Latch::CliToolNotFound
      run_command("convert", [input] + args + [output])
    end

    # Builds an array of CLI flag/value pairs from a variant's options.
    private def self.process_build_args(variant) : Array(String)
      Array(String).new.tap do |args|
        {% for key in anno.named_args.keys %}
          args << "-{{ key }}" << variant[:{{ key }}].to_s if variant[:{{ key }}]
        {% end %}
      end
    end
  end
end
