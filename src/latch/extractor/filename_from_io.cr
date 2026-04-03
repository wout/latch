struct Latch::Extractor::FilenameFromIO
  include Latch::Extractor

  # Returns the filename from the options or tries to extract the filename from
  # the IO object.
  def extract(uploaded_file, metadata, **options) : String?
    options[:filename]? || File.basename(uploaded_file.filename)
  end
end
