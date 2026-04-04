require "./validations"

# Integrates Latch uploads with Avram models.
#
# Include this module in your model to use the `attach` macro for declaring
# file attachments backed by Latch uploaders.
#
# ```
# class User < BaseModel
#   include Latch::Avram::Model
#
#   table do
#     attach avatar : ImageUploader::StoredFile?
#   end
# end
# ```
#
# By including this module, the model's operation classes will also receive the
# required macros and methods to seamlessly integrate with Latch.
#
module Latch::Avram::Model
  macro included
    class ::{{ @type }}::SaveOperation < ::Avram::SaveOperation({{ @type }})
      include Latch::Avram::SaveOperation
    end
  end

  # Registers a serializable column for an attachment. The type should be an
  # uploader's `StoredFile` class.
  #
  # ```
  # attach avatar : ImageUploader::StoredFile
  # # or
  # attach avatar : ImageUploader::StoredFile?
  # ```
  #
  # It is assumed that a `jsonb` column exists with the same name. So in your
  # migration, you'll need to add the column as follows:
  #
  # ```
  # add avatar : JSON::Any
  # # or
  # add avatar : JSON::Any?
  # ```
  #
  # The data of a stored file can then be accessed through the `avatar` method:
  #
  # ```
  # user.avatar.class
  # # => ImageUploader::StoredFile
  #
  # user.avatar.url
  # # => "https://bucket.s3.amazonaws.com/user/1/avatar/abc123.jpg"
  #
  # # for presigned URLs
  # user.avatar.url(expires_in: 1.hour)
  # ```
  #
  macro attach(type_declaration)
    {% name = type_declaration.var %}
    {% if type_declaration.type.is_a?(Union) %}
      {% stored_file = type_declaration.type.types.first %}
      {% nilable = true %}
    {% else %}
      {% stored_file = type_declaration.type %}
      {% nilable = false %}
    {% end %}
    {% uploader = stored_file.stringify.split("::")[0..-2].join("::").id %}

    ATTACHMENT_PREFIX_{{ name.stringify.upcase.id }} = {{ uploader }}.path_prefix
      .gsub(/:model/, {{ @type.stringify.gsub(/::/, "_").underscore }})
      .gsub(/:attachment/, {{ name.stringify }})

    ATTACHMENT_UPLOADER_{{ name.stringify.upcase.id }} = {{ uploader }}

    column {{ name }} : ::{{ stored_file }}{% if nilable %}?{% end %}, serialize: true

    class ::{{ @type }}::DeleteOperation < ::Avram::DeleteOperation({{ @type }})
      after_delete { |record| record.{{ name }}.try(&.delete) }
    end
  end
end

module Latch::Avram::SaveOperation
  include Latch::Avram::Validations

  # Registers a file attribute for an existing attachment on the model.
  #
  # ```
  # # The field name in the form will be "avatar_file"
  # attach avatar
  #
  # # With a custom field name
  # attach avatar, field_name: "avatar_upload"
  # ```
  #
  # The attachment will then be uploaded to the cache store, and after
  # committing to the database the attachment will be moved to the permanent
  # storage.
  #
  macro attach(name, field_name = nil, process = false, &block)
    {%
      field_name = "#{name}_file".id if field_name.nil?

      unless column = T.constant(:COLUMNS).find { |col| col[:name].stringify == name.stringify }
        raise %(The `#{T.name}` model does not have a column named `#{name}`)
      end

      if process && block
        raise "Cannot use both `process: true` and a block with `attach`"
      end
    %}

    file_attribute :{{ field_name }}

    {% if nilable = column[:nilable] %}
      attribute delete_{{ name }} : Bool = false
    {% end %}

    before_save __cache_{{ field_name }}
    after_commit __process_{{ field_name }}

    # Moves uploaded file to the cache storage.
    private def __cache_{{ field_name }} : Nil
      {% if nilable %}
        {{ name }}.value = nil if delete_{{ name }}.value
      {% end %}

      return unless upload = {{ field_name }}.value

      record_id = new_record? ?
        UUID.random.to_s :
        {{ T.constant(:PRIMARY_KEY_NAME).id }}.value
      prefix = T::ATTACHMENT_PREFIX_{{ name.stringify.upcase.id }}.gsub(/:id/, record_id)
      {{ name }}.value = T::ATTACHMENT_UPLOADER_{{ name.stringify.upcase.id }}.cache(
        upload.as(Latch::UploadedFile),
        path_prefix: prefix,
      )
    end

    # Deletes or promotes the attachment and updates the record.
    private def __process_{{ field_name }}(record) : Nil
      {% if nilable %}
        if delete_{{ name }}.value && (file = {{ name }}.original_value)
          file.delete
        end
      {% end %}

      return unless {{ field_name }}.value && (cached = {{ name }}.value)

      if old_file = {{ name }}.original_value
        old_file.delete
      end

      record_id = record.{{ T.constant(:PRIMARY_KEY_NAME).id }}.to_s
      prefix = T::ATTACHMENT_PREFIX_{{ name.stringify.upcase.id }}.gsub(/:id/, record_id)
      stored = T::ATTACHMENT_UPLOADER_{{ name.stringify.upcase.id }}.promote(
        cached,
        location: File.join(prefix, File.basename(cached.id))
      )
      T::SaveOperation.update!(record, {{ name }}: stored)

      {% if process %}
        stored.process
      {% elsif block %}
        {% if block.args.size > 0 %}{{ block.args[0] }} = stored{% end %}
        {% if block.args.size > 1 %}{{ block.args[1] }} = record{% end %}
        {{ block.body }}
      {% end %}
    end

    {% if process %}
      macro finished
        \{%
          uploader = T.constant(:ATTACHMENT_UPLOADER_{{ name.stringify.upcase.id }}).resolve

          unless uploader.has_constant?(:HAS_PROCESSORS)
            raise <<-ERROR

            `attach {{ name }}, process: true` on #{@type} but `#{uploader}`
            has no processors registered.

            Try this...

              ▸ Register a processor on the uploader:

                struct #{uploader}
                  include Latch::Uploader

                  process sizes, using: MySizesProcessor
                end

              ▸ Or use a block for custom processing:

                attach {{ name }} do |stored_file, record|
                  ProcessJob.perform_async(stored_file.id)
                end

            ERROR
          end
        \%}
      end
    {% end %}
  end
end
