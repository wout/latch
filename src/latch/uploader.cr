require "uuid"

# Uploader module that handles file uploads with metadata extraction and
# location generation. Include this module in a struct or class.
#
# ```
# struct ImageUploader
#   include Latch::Uploader
#
#   def generate_location(uploaded_file, metadata, **options) : String
#     date = Time.utc.to_s("%Y/%m/%d")
#     File.join("images", date, super)
#   end
# end
#
# ImageUploader.new("store").upload(uploaded_file)
# # => Latch::StoredFile with id "images/2024/01/15/abc123.jpg"
# ```
#
module Latch::Uploader
  alias MetadataHash = ::Latch::MetadataHash

  macro included
    {% stored_file = "#{@type}::StoredFile".id %}

    @@extractors = {} of String => Latch::Extractor
    @@processor_procs = [] of Proc({{ stored_file }}, Latch::Storage, Nil)

    class {{ stored_file }} < Latch::StoredFile
      def process(**options) : self
        {{ @type }}.process(self, **options)
      end
    end

    # Defines the path prefix for uploads in the storage. Overwrite this method
    # in uploader subclasses to use custom path prefixes per uploader.
    def self.path_prefix : String
      Latch.settings.path_prefix
    end

    # Default storage keys (overridable via the `storages` macro)
    @@cache_storage_key = "cache"
    @@store_storage_key = "store"

    # Defines `self.storages` and `self.process` after all user code has been
    # processed, so the `storages` and `process` macros can be called without
    # being shadowed by the methods.
    macro finished
      def self.storages : NamedTuple(cache: String, store: String)
        {cache: @@cache_storage_key, store: @@store_storage_key}
      end

      def self.process(
        stored_file : {{ stored_file }},
        **options,
      ) : {{ stored_file }}
        storage = stored_file.storage
        @@processor_procs.each(&.call(stored_file, storage))
        stored_file
      end
    end

    # Register default extractors
    extract filename, using: Latch::Extractor::FilenameFromIO
    extract mime_type, using: Latch::Extractor::MimeFromIO
    extract size, using: Latch::Extractor::SizeFromIO

    # Uploads a file and returns a `Latch::StoredFile`. This method
    # accepts additional metadata and arbitrary arguments for overrides.
    #
    # ```
    # uploader.upload(uploaded_file)
    # uploader.upload(uploaded_file, metadata: {"custom" => "value"})
    # uploader.upload(uploaded_file, location: "custom/path.jpg")
    # ```
    #
    def upload(
      uploaded_file : Latch::UploadedFile,
      metadata : MetadataHash? = nil,
      **options
    ) : {{ stored_file }}
      data = extract_metadata(uploaded_file, metadata, **options)
      data = data.merge(metadata) if metadata
      location = options[:location]? || generate_location(uploaded_file, data, **options)

      storage.upload(uploaded_file.tempfile, location, **options.merge(metadata: data))
      {{ stored_file }}.new(id: location, storage_key: storage_key, metadata: data)
    end

    # Uploads to the "cache" storage.
    #
    # ```
    # cached = ImageUploader.cache(uploaded_file)
    # ```
    #
    def self.cache(
      uploaded_file : Latch::UploadedFile,
      **options
    ) : {{ stored_file }}
      new(self.storages[:cache]).upload(uploaded_file, **options)
    end

    # Uploads to the "store" storage.
    #
    # ```
    # stored = ImageUploader.store(uploaded_file)
    # ```
    #
    def self.store(
      uploaded_file : Latch::UploadedFile,
      **options
    ) : {{ stored_file }}
      new(self.storages[:store]).upload(uploaded_file, **options)
    end

    # Promotes a file from cache to store.
    #
    # ```
    # cached = ImageUploader.cache(uploaded_file)
    # stored = ImageUploader.promote(cached)
    # ```
    #
    def self.promote(
      stored_file : {{ stored_file }},
      to storage : String = self.storages[:store],
      delete_source : Bool = true,
      **options,
    ) : {{ stored_file }}
      store_location = options[:location]? || stored_file.id
      store_storage = ::Latch.find_storage(storage)
      store_storage.move(
        stored_file,
        store_location,
        **options,
        metadata: stored_file.metadata
      )
      promoted = {{ stored_file }}.new(
        id: store_location,
        storage_key: storage,
        metadata: stored_file.metadata
      )
      stored_file.delete if delete_source
      promoted
    end

  end

  # Configures the storage keys used by this uploader. Both `cache` and `store`
  # have defaults, so you only need to specify the ones you want to change.
  #
  # ```
  # struct ImageUploader
  #   include Latch::Uploader
  #
  #   # Override both
  #   storages cache: "tmp", store: "offsite"
  # end
  #
  # struct VideoUploader
  #   include Latch::Uploader
  #
  #   # Override only store; cache stays "cache"
  #   storages store: "offsite"
  # end
  # ```
  #
  macro storages(cache = "cache", store = "store")
    @@cache_storage_key = {{ cache }}
    @@store_storage_key = {{ store }}
  end

  # Registers a processor and generates variant accessor methods on the
  # uploader's `StoredFile`. The processor must define a `VARIANTS` constant
  # listing its variant names.
  #
  # ```
  # struct AvatarUploader
  #   include Latch::Uploader
  #
  #   process sizes, using: AvatarSizesProcessor
  # end
  #
  # stored = AvatarUploader.store(uploaded_file)
  # AvatarUploader.process(stored)
  # stored.sizes_large.url # => "/uploads/abc123/sizes_large.jpg"
  # ```
  #
  macro process(name, using)
    {%
      variant_names = using.resolve.constants
        .select(&.starts_with?("VARIANT_"))
        .map { |const| using.resolve.constant(const) }
    %}

    {% unless @type.has_constant?(:HAS_PROCESSORS) %}
      HAS_PROCESSORS = true
    {% end %}


    @@processor_procs << ->(
      stored_file : {{ @type }}::StoredFile,
      storage : Latch::Storage
    ) do
      {{ using }}.process(stored_file, storage, {{ name.stringify }})
    end

    class {{ @type }}::StoredFile < Latch::StoredFile
      {% for variant_name in variant_names %}
        def {{ name }}_{{ variant_name.id }} : {{ @type }}::StoredFile
          {{ @type }}::StoredFile.new(
            id: variant_location("{{ name }}_{{ variant_name.id }}"),
            storage_key: storage_key,
            metadata: Latch::MetadataHash.new,
          )
        end
      {% end %}
    end
  end

  # Registers an extractor for a given key.
  #
  # ```
  # struct PdfUploader
  #   include Latch::Uploader
  #
  #   # Use a different MIME type extractor than the default one
  #   extract mime_type, using: Latch::Extractor::MimeFromExtension
  #
  #   # Or use your own custom extractor to add arbitrary data
  #   extract pages, using: MyNumberOfPagesExtractor
  # end
  # ```
  #
  # The result will then be added to the attachment's metadata after uploading:
  # ```
  # invoice.pdf.pages
  # # => 24
  # ```
  #
  macro extract(name, using)
    {%
      type = using.resolve.methods
        .find { |method| method.name == :extract.id }
        .return_type.types.first
    %}

    class {{ @type }}::StoredFile < Latch::StoredFile
      def {{ name }}? : {{ type }}?
        {% if {Int32, Int64}.includes? type.resolve %}
          if value = metadata["{{ name }}"]?
            {{ type }}.new(value.as(Int32 | Int64))
          end
        {% else %}
          metadata["{{ name }}"]?.try(&.as?({{ type }}))
        {% end %}
      end

      def {{ name }} : {{ type }}
        {% if {Int32, Int64}.includes? type.resolve %}
          {{ type }}.new(metadata["{{ name }}"].as(Int32 | Int64))
        {% else %}
          metadata["{{ name }}"].as({{ type }})
        {% end %}
      end

      {% if methods = using.resolve.annotation(Latch::MetadataMethods) %}
        {% for td in methods.args %}
          def {{ td.var }}? : {{ td.type }}?
            {% if {Int32, Int64}.includes? td.type.resolve %}
              if value = metadata["{{ td.var }}"]?
                {{ td.type }}.new(value.as(Int32 | Int64))
              end
            {% else %}
              metadata["{{ td.var }}"]?.try(&.as?({{ td.type }}))
            {% end %}
          end

          def {{ td.var }} : {{ td.type }}
            {% if {Int32, Int64}.includes? td.type.resolve %}
              {{ td.type }}.new(metadata["{{ td.var }}"].as(Int32 | Int64))
            {% else %}
              metadata["{{ td.var }}"].as({{ td.type }})
            {% end %}
          end
        {% end %}
      {% end %}
    end

    @@extractors["{{ name }}"] = {{ using }}.new
  end

  getter storage_key : String

  def initialize(@storage_key : String)
  end

  # Returns the storage instance for this uploader.
  def storage : Storage
    Latch.find_storage(storage_key)
  end

  # Generates a unique location for the uploaded file. Override this in
  # subclasses for custom locations.
  #
  # ```
  # struct ImageUploader
  #   include Latch::Uploader
  #
  #   def generate_location(uploaded_file, metadata, **options) : String
  #     File.join("images", super)
  #   end
  # end
  # ```
  #
  def generate_location(
    uploaded_file : Latch::UploadedFile,
    metadata : MetadataHash,
    **options,
  ) : String
    extension = file_extension(uploaded_file, metadata)
    basename = generate_uid(uploaded_file, metadata, **options)
    filename = extension ? "#{basename}.#{extension}" : basename
    File.join([options[:path_prefix]?, filename].compact)
  end

  # Generates a unique identifier for file locations. Override this in
  # subclasses for custom filenames in the storage.
  #
  # ```
  # struct ImageUploader
  #   include Latch::Uploader
  #
  #   def generate_uid(uploaded_file, metadata, **options) : String
  #     "#{metadata["filename"]}-#{Time.local.to_unix}"
  #   end
  # end
  # ```
  #
  def generate_uid(
    uploaded_file : Latch::UploadedFile,
    metadata : MetadataHash,
    **options,
  ) : String
    UUID.random.to_s
  end

  # Extracts metadata from the IO. Override to add completely custom metadata
  # extraction outside of the `extract` DSL.
  #
  # ```
  # struct ImageUploader
  #   include Latch::Uploader
  #
  #   def extract_metadata(
  #     uploaded_file : Latch::UploadedFile,
  #     metadata : MetadataHash? = nil,
  #     **options,
  #   ) : MetadataHash
  #     data = super
  #     # Add custom metadata
  #     data["custom"] = "value"
  #     data
  #   end
  #
  #   # Reopen the `StoredFile` class to add a method for the custom value.
  #   class StoredFile
  #     def custom : String
  #       metadata["custom"].as(String)
  #     end
  #   end
  # end
  # ```
  #
  def extract_metadata(
    uploaded_file : Latch::UploadedFile,
    metadata : MetadataHash? = nil,
    **options,
  ) : MetadataHash
    (metadata.try(&.dup) || MetadataHash.new).tap do |data|
      @@extractors.each do |name, extractor|
        if value = extractor.extract(uploaded_file, data, **options)
          data[name] = value
        end
      end
    end
  end

  # Tries to determine the file extension from the metadata or IO.
  protected def file_extension(
    uploaded_file : Latch::UploadedFile,
    metadata : MetadataHash,
  ) : String?
    if filename = metadata["filename"]?.try(&.as(String))
      ext = File.extname(filename).lchop('.')
      return ext.downcase unless ext.empty?
    end

    File.extname(uploaded_file.path).lchop('.').try(&.downcase.presence)
  end
end
