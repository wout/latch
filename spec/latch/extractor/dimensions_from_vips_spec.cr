require "../../spec_helper"

describe Latch::Extractor::DimensionsFromVips do
  describe "#extract" do
    subject = Latch::Extractor::DimensionsFromVips.new

    context "when vipsheader is not installed" do
      it "raises Latch::Error" do
        original_path = ENV["PATH"]
        ENV["PATH"] = ""
        uploaded_file = build_uploaded_file(filename: "test.png")

        begin
          expect_raises(
            Latch::Error,
            /The `vipsheader` command-line tool is not installed/
          ) do
            subject.extract(
              uploaded_file,
              metadata: {} of String => Latch::MetadataValue
            )
          end
        ensure
          ENV["PATH"] = original_path
        end
      end
    end

    context "when vipsheader is installed" do
      png_path = "spec/fixtures/lucky_logo_tiny.png"

      it "extracts width and height" do
        uploaded_file = build_uploaded_file(
          path: png_path,
          filename: "lucky_logo_tiny.png"
        )
        metadata = {} of String => Latch::MetadataValue
        subject.extract(uploaded_file, metadata: metadata)

        metadata["width"].should eq(69)
        metadata["height"].should eq(16)
      end

      it "does not modify metadata for an unrecognised file" do
        uploaded_file = build_uploaded_file(filename: "empty.bin")
        metadata = {} of String => Latch::MetadataValue
        subject.extract(uploaded_file, metadata: metadata)

        metadata.has_key?("width").should be_false
        metadata.has_key?("height").should be_false
      end
    end
  end
end

private def build_uploaded_file(
  filename : String,
  path : String? = nil,
) : Lucky::UploadedFile
  headers = HTTP::Headers.new
  headers["Content-Disposition"] =
    %[form-data; name="file"; filename="#{filename}"]
  body = path ? File.open(path) : IO::Memory.new
  part = HTTP::FormData::Part.new(headers: headers, body: body)
  Lucky::UploadedFile.new(part)
end
