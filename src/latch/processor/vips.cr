require "../run_command"

# Processor module for libvips-based image transformations. Uses
# `vipsthumbnail` for resize operations and `vips copy` for metadata/format
# changes without resizing.
#
# ```
# struct AvatarProcessor
#   include Latch::Processor::Vips
#
#   original resize: "2000x2000>", strip: true
#   variant large, resize: "800x800"
#   variant thumb, resize: "200x200", crop: true, quality: 85
# end
# ```
#
@[Latch::VariantOptions(
  auto_orient: Bool?, # fix orientation from EXIF data
  crop: Bool?,        # crop to fill instead of shrink-to-fit
  format: String?,    # output format via extension, e.g. "webp", "png"
  linear: Bool?,      # process in linear color space (higher quality)
  quality: Int32?,    # JPEG/WebP compression quality (1-100)
  resize: String?,    # bounding box, e.g. "200x200", "800x", "2000x2000>"
  smartcrop: String?, # smart crop mode, e.g. "attention", "entropy"
  strip: Bool?,       # remove all metadata and profiles
)]
module Latch::Processor::Vips
  include Latch::Processor

  process do
    suffix = vips_output_suffix(variant_options)
    output = File.tempfile("latch-variant", suffix)
    output_path = output.path + vips_save_options(variant_options)

    if variant_options[:resize]?
      args = vips_thumbnail_args(variant_options)
      run_vipsthumbnail(tempfile.path, args, output_path)
    else
      run_vips_copy(tempfile.path, output_path)
    end

    output.tap(&.rewind)
  end

  macro included
    extend Latch::RunCommand

    private def self.run_vipsthumbnail(input : String, args : Array(String), output : String) : Nil
      run_command("vipsthumbnail", [input] + args + ["-o", output])
    end

    private def self.run_vips_copy(input : String, output : String) : Nil
      run_command("vips", ["copy", input, output])
    end

    # Determines the output file suffix from the format option.
    private def self.vips_output_suffix(variant) : String
      if fmt = variant[:format]?
        ".#{fmt}"
      else
        ".jpg"
      end
    end

    # Builds bracket-style save options appended to the output path,
    # e.g. "[Q=85,strip]".
    private def self.vips_save_options(variant) : String
      opts = [] of String
      opts << "Q=#{variant[:quality]}" if variant[:quality]?
      opts << "strip" if variant[:strip]?
      opts.empty? ? "" : "[#{opts.join(",")}]"
    end

    # Builds the vipsthumbnail argument array.
    private def self.vips_thumbnail_args(variant) : Array(String)
      Array(String).new.tap do |args|
        args << "-s" << variant[:resize].to_s if variant[:resize]?
        args << "-c" if variant[:crop]?
        args << "--smartcrop" << variant[:smartcrop].to_s if variant[:smartcrop]?
        args << "--rotate" if variant[:auto_orient]?
        args << "--linear" if variant[:linear]?
      end
    end
  end
end
