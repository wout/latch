# Base module for processors that transform uploaded files into variants.
# Provides the `variant` and `original` macros with compile-time validation
# against a `@[Latch::VariantOptions(...)]` annotation declared by the
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

    alias ProcessOptions = NamedTuple({{ anno.named_args.double_splat }})

    macro included
      VARIANTS = {} of String => ProcessOptions
      ORIGINAL_OPTIONS = [] of ProcessOptions
    end
  end

  # Generates the boilerplate `self.process` on the concrete type. The block
  # body is expanded inside the variant loop with `stored_file`, `storage`,
  # `name`, `tempfile`, `variant_name`, and `variant_options` in scope.
  #
  # Variants are processed first, then the original (if defined), so that
  # variants always use the maximum available quality.
  macro process(&block)
    macro included
      def self.process(
        stored_file : Latch::StoredFile,
        storage : Latch::Storage,
        name : String,
        **options,
      ) : Nil
        stored_file.download do |tempfile|
          channel = Channel(Exception?).new(VARIANTS.size)

          VARIANTS.each do |variant_name, variant_options|
            spawn do
              location = stored_file.variant_location("#{name}_#{variant_name}")
              io = begin
                {{ block.body }}
              end
              storage.upload(io, location)
              channel.send(nil)
            rescue ex
              channel.send(ex)
            end
          end

          VARIANTS.size.times do
            if ex = channel.receive
              raise ex
            end
          end

          if (original = ORIGINAL_OPTIONS.first?)
            variant_name = "original"
            variant_options = original
            io = begin
              {{ block.body }}
            end
            storage.upload(io, stored_file.id)
          end
        end
      end
    end
  end

  # Resolves the `@[Latch::VariantOptions(...)]` annotation, validates the
  # provided options, builds a NamedTuple, and stores it in the target.
  private macro __store_validated_options(target, entry_key, label, options)
    {%
      unless anno = @type.annotation(Latch::VariantOptions)
        @type.ancestors.each do |ancestor|
          anno = ancestor.annotation(Latch::VariantOptions) unless anno
        end
      end

      unless anno
        raise "#{@type} must include a processor with a " \
              "@[Latch::VariantOptions(...)] annotation"
      end

      declared_names = anno.named_args.keys

      options.keys.each do |key|
        unless declared_names.includes?(key)
          raise "Unknown variant option '#{key.id}' for #{@type}. " \
                "Valid options: #{declared_names.map(&.id).join(", ")}"
        end
      end

      anno.named_args.each do |key, type|
        unless type.resolve.nilable? || options.keys.includes?(key)
          raise "Missing required option '#{key.id}' for #{label.id} in #{@type}"
        end
      end
    %}

    {% if entry_key %}
      {{ target }}[{{ entry_key }}] = {
    {% else %}
      {{ target }} << {
    {% end %}
      {% for key in anno.named_args.keys %}
        {% if options.keys.includes?(key) %}
          {{ key }}: {{ options[key] }},
        {% else %}
          {{ key }}: nil,
        {% end %}
      {% end %}
    }
  end

  # Defines a named variant. Options are validated at compile time against the
  # `@[Latch::VariantOptions(...)]` annotation on the processor.
  macro variant(name, **options)
    __store_validated_options(VARIANTS, {{ name.stringify }}, "variant '#{name.id}'", {{ options }})

    # Adds a compile-time marker for variant name discovery by the uploader. I
    # tried with a hash, but that wouldn't work.
    VARIANT_{{ name.id.stringify.upcase.id }} = {{ name.stringify }}
  end

  # Defines processing options for the original file. The original is processed
  # after all variants, so they use the maximum available quality.
  macro original(**options)
    __store_validated_options(ORIGINAL_OPTIONS, nil, "original", {{ options }})
  end
end
