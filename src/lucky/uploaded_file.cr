class Lucky::UploadedFile
  # Attempts to extract the content type from the part's headers.
  #
  # ```
  # uploaded_file_object.content_type
  # # => "image/png"
  # ```
  #
  def content_type : String?
    @part.headers["Content-Type"]?.try(&.split(';').first.strip)
  end
end
