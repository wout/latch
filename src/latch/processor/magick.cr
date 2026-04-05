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
  auto_orient: Bool?,       # fix orientation from EXIF data
  background: String?,      # background color, e.g. "white", "transparent"
  colorspace: String?,      # convert color model, e.g. "sRGB", "Gray"
  crop: String?,            # cut a region, e.g. "200x200+10+10"
  density: String?,         # resolution in DPI, e.g. "72"
  extent: String?,          # pad/canvas size, e.g. "800x600"
  flatten: Bool?,           # merge layers into one
  gaussian_blur: String?,   # blur effect, e.g. "0x3"
  gravity: String?,         # anchor point, e.g. "center", "north"
  interlace: String?,       # progressive rendering, e.g. "Plane"
  quality: String?,         # compression quality, e.g. "85"
  resize: String?,          # scale to fit, e.g. "800x600", "200x200>"
  rotate: String?,          # rotate by degrees, e.g. "90"
  sampling_factor: String?, # chroma subsampling, e.g. "4:2:0"
  sharpen: String?,         # sharpen, e.g. "0x1"
  strip: Bool?,             # remove all metadata and profiles
  thumbnail: String?,       # like resize but strips profiles, e.g. "200x200"
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

    # Builds an array of CLI flags from a variant's options. Underscores in
    # option names are converted to hyphens (e.g. `auto_orient` → `-auto-orient`).
    # Boolean options become standalone flags, string options become flag/value
    # pairs.
    private def self.process_build_args(variant) : Array(String)
      Array(String).new.tap do |args|
        {% for key, type in anno.named_args %}
          {% flag = key.stringify.gsub(/_/, "-") %}
          {% if type.stringify.includes?("Bool") %}
            args << "-{{ flag.id }}" if variant[:{{ key }}]
          {% else %}
            args << "-{{ flag.id }}" << variant[:{{ key }}].to_s if variant[:{{ key }}]
          {% end %}
        {% end %}
      end
    end
  end
end
