# Base module for processors that transform uploaded files into variants.
# Provides the `variant` macro with compile-time validation against a
# `@[Lucky::Attachment::VariantOptions(...)]` annotation declared by the
# concrete processor module.
#
# Non-nilable annotation types are required in every `variant` call, nilable
# types are optional. Unknown keys cause a compile-time error.
#
# See `Lucky::Attachment::Processor::Magick` for an ImageMagick-based
# implementation.
#
module Lucky::Attachment::Processor
  macro included
    {%
      unless anno = @type.annotation(Lucky::Attachment::VariantOptions)
        @type.ancestors.each do |ancestor|
          anno = ancestor.annotation(Lucky::Attachment::VariantOptions) unless anno
        end
      end
    %}

    {% unless anno %}
      {% raise "#{@type} must include a processor with a @[Lucky::Attachment::VariantOptions(...)] annotation" %}
    {% end %}

    VARIANTS = {} of String => NamedTuple({{ anno.named_args.double_splat }})
  end

  # Defines a named variant. Options are validated at compile time against the
  # `@[Lucky::Attachment::VariantOptions(...)]` annotation on the processor.
  macro variant(name, **options)
    {%
      unless anno = @type.annotation(Lucky::Attachment::VariantOptions)
        @type.ancestors.each do |ancestor|
          anno = ancestor.annotation(Lucky::Attachment::VariantOptions) unless anno
        end
      end
    %}

    {%
      unless anno
        raise "#{@type} must include a processor with a " \
              "@[Lucky::Attachment::VariantOptions(...)] annotation"
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
