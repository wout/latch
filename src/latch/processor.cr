# Base module for processors that transform uploaded files into variants.
# Provides the `variant` macro with compile-time validation against a
# `@[Latch::VariantOptions(...)]` annotation declared by the
# concrete processor module.
#
# Non-nilable annotation types are required in every `variant` call, nilable
# types are optional. Unknown keys cause a compile-time error.
#
# See `Latch::Processor::Magick` for an ImageMagick-based
# implementation.
#
module Latch::Processor
  macro included
    {%
      anno = ([@type] + @type.ancestors)
        .map(&.annotation(Latch::VariantOptions))
        .first

      unless anno
        raise "#{@type} must include a processor with a @[Latch::VariantOptions(...)] annotation"
      end
    %}

    VARIANTS = {} of String => NamedTuple({{ anno.named_args.double_splat }})
  end

  # Generates the boilerplate `self.process` on the concrete type. The block
  # body is expanded inside the variant loop with `stored_file`, `storage`,
  # `name`, `tempfile`, `variant_name`, and `variant_options` in scope.
  macro process(&block)
    macro included
      def self.process(
        stored_file : Latch::StoredFile,
        storage : Latch::Storage,
        name : String,
        **options,
      ) : Nil
        stored_file.download do |tempfile|
          VARIANTS.each do |variant_name, variant_options|
            location = stored_file.variant_location("#{name}_#{variant_name}")
            io = begin
              {{ block.body }}
            end
            storage.upload(io, location)
          end
        end
      end
    end
  end

  # Defines a named variant. Options are validated at compile time against the
  # `@[Latch::VariantOptions(...)]` annotation on the processor.
  macro variant(name, **options)
    {%
      unless anno = @type.annotation(Latch::VariantOptions)
        @type.ancestors.each do |ancestor|
          anno = ancestor.annotation(Latch::VariantOptions) unless anno
        end
      end
    %}

    {%
      unless anno
        raise "#{@type} must include a processor with a " \
              "@[Latch::VariantOptions(...)] annotation"
      end
    %}

    {%
      declared_names = anno.named_args.keys

      # Verfies that all provided options are declared in the annotation
      options.keys.each do |key|
        unless declared_names.includes?(key)
          raise "Unknown variant option '#{key.id}' for #{@type}. " \
                "Valid options: #{declared_names.map(&.id).join(", ")}"
        end
      end

      # Verifies that all non-nilable options are provided
      anno.named_args.each do |key, type|
        is_nilable = type.is_a?(Generic) &&
                     type.name.resolve == Union &&
                     type.type_vars.map(&.resolve).includes?(Nil)
        unless is_nilable || options.keys.includes?(key)
          raise "Missing required option '#{key.id}' for variant '#{name.id}' in #{@type}"
        end
      end
    %}

    # Adds a compile-time marker for variant name discovery by the uploader
    VARIANT_{{ name.id.stringify.upcase.id }} = {{ name.stringify }}

    # Builds an stores the named tuple with options for the given variant
    VARIANTS[{{ name.stringify }}] = {
      {% for key in anno.named_args.keys %}
        {% if options.keys.includes?(key) %}
          {{ key }}: {{ options[key] }},
        {% else %}
          {{ key }}: nil,
        {% end %}
      {% end %}
    }
  end
end
