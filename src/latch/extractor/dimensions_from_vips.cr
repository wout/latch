@[Latch::MetadataMethods(width : Int32, height : Int32)]
struct Latch::Extractor::DimensionsFromVips
  include Latch::Extractor
  include Latch::RunCommand

  # Extracts the dimensions of a file using `vipsheader`.
  def extract(uploaded_file, metadata, **options) : Nil
    path = uploaded_file.tempfile.path
    return unless width = run_command("vipsheader", ["-f", "width", path])
    return unless height = run_command("vipsheader", ["-f", "height", path])

    metadata["width"] = width.to_i
    metadata["height"] = height.to_i
  end
end
