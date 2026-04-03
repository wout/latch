struct Latch::Extractor::SizeFromIO
  include Latch::Extractor

  # Tries to extract the file size from the IO.
  def extract(uploaded_file, metadata, **options) : Int64?
    uploaded_file.tempfile.size
  end
end
