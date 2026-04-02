require "../run_command"

# Processor module for ImageMagick-based image transformations. Include this
# module and use the `variant` macro to define variants. Each option key
# becomes a `-key value` pair passed to `magick convert`.
#
# ```
# struct AvatarSizesProcessor
#   include Lucky::Attachment::Processor::Magick
#
#   variant large, resize: "2000x2000"
#   variant small, resize: "200x200", gravity: "center"
# end
# ```
#
@[Lucky::Attachment::VariantOptions(
  resize: String?,
  gravity: String?,
  extent: String?,
  crop: String?,
  quality: String?,
)]
module Lucky::Attachment::Processor::Magick
  include Lucky::Attachment::Processor

  macro included
    extend Lucky::Attachment::RunCommand

    {%
      anno = @type.ancestors
        .map(&.annotation(Lucky::Attachment::VariantOptions))
        .first
    %}

    # Processes all configured variants
    def self.process(
      stored_file : Lucky::Attachment::StoredFile,
      storage : Lucky::Attachment::Storage,
      name : String,
      **options,
    ) : Nil
      stored_file.download do |tempfile|
        VARIANTS.each do |variant_name, variant_options|
          args = process_build_args(variant_options)
          location = stored_file.variant_location("#{name}_#{variant_name}")

          File.tempfile("lucky-attachment-variant") do |output|
            run_command("magick", ["convert", tempfile.path] + args + [output.path])
            output.rewind
            storage.upload(output, location)
          end
        end
      end
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
