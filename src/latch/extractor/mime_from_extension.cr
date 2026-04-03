struct Latch::Extractor::MimeFromExtension
  include Latch::Extractor

  # Extracts the MIME type from the extension of the filename.
  def extract(uploaded_file, metadata, **options) : String?
    MIME.from_filename?(uploaded_file.filename)
  end
end
