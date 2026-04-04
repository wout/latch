# File attachment validations for Avram SaveOperations.
#
# Included automatically via `Latch::Avram::SaveOperation`.
#
module Latch::Avram::Validations
  # Validates that the file size is within the given bounds.
  #
  # ```
  # before_save do
  #   validate_file_size_of avatar_file, max: 5_000_000
  #   validate_file_size_of avatar_file, min: 1_000, max: 5_000_000
  # end
  # ```
  #
  def validate_file_size_of(
    attribute,
    min : Int64 = 0_i64,
    max : Int64? = nil,
    message : String? = nil,
    allow_blank : Bool = false,
  ) : Bool
    return true unless file = attribute.value
    size = file.size?
    return true if allow_blank && !size

    if (size || 0_i64) < min
      attribute.add_error(message || "must be at least #{min} bytes")
      return false
    end

    if (max_size = max) && (size || 0_i64) > max_size
      attribute.add_error(message || "must not be larger than #{max_size} bytes")
      return false
    end

    true
  end

  # Validates that the file has one of the allowed MIME types.
  #
  # ```
  # before_save do
  #   validate_file_mime_type_of avatar_file, in: %w[image/png image/jpeg]
  # end
  # ```
  #
  def validate_file_mime_type_of(
    attribute,
    in allowed : Enumerable(String),
    message : String = "is not an accepted file type",
    allow_blank : Bool = false,
  ) : Bool
    return true unless file = attribute.value
    mime_type = file.mime_type?
    return true if allow_blank && !mime_type

    unless allowed.includes?(mime_type)
      attribute.add_error(message)
      return false
    end

    true
  end

  # Validates that the file MIME type matches the given pattern.
  #
  # ```
  # before_save do
  #   validate_file_mime_type_of avatar_file, with: /image\/.*/
  # end
  # ```
  #
  def validate_file_mime_type_of(
    attribute,
    with pattern : Regex,
    message : String = "is not an accepted file type",
    allow_blank : Bool = false,
  ) : Bool
    return true unless file = attribute.value
    mime_type = file.mime_type?
    return true if allow_blank && !mime_type

    unless mime_type.to_s.match(pattern)
      attribute.add_error(message)
      return false
    end

    true
  end
end
