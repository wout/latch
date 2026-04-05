require "../../spec_helper"

private struct TestVipsProcessor
  include Latch::Processor::Vips

  original resize: "2000x2000>", strip: true
  variant large, resize: "800x800"
  variant thumb, resize: "200x200", crop: true, quality: 85
end

private struct VipsUploader
  include Latch::Uploader

  process versions, using: TestVipsProcessor
end

describe Latch::Processor::Vips do
  describe "VARIANTS constant" do
    it "contains all defined variants" do
      TestVipsProcessor::VARIANTS.size.should eq(2)
      TestVipsProcessor::VARIANTS["large"][:resize].should eq("800x800")
      TestVipsProcessor::VARIANTS["thumb"][:resize].should eq("200x200")
      TestVipsProcessor::VARIANTS["thumb"][:crop].should be_true
      TestVipsProcessor::VARIANTS["thumb"][:quality].should eq(85)
    end
  end

  describe "ORIGINAL_OPTIONS constant" do
    it "stores the original processing options" do
      original = TestVipsProcessor::ORIGINAL_OPTIONS.first
      original[:resize].should eq("2000x2000>")
      original[:strip].should be_true
    end
  end

  describe "variant accessors" do
    it "generates accessor methods on StoredFile" do
      memory_store = Latch::Storage::Memory.new
      Latch.configure do |settings|
        settings.storages["store"] = memory_store
      end

      stored = VipsUploader.store(build_uploaded_file(
        content: "test", filename: "test.jpg"
      ))

      stored.responds_to?(:versions_large).should be_true
      stored.responds_to?(:versions_thumb).should be_true
    end
  end
end

private def build_uploaded_file(
  content : String,
  filename : String,
) : Lucky::UploadedFile
  headers = HTTP::Headers.new
  headers["Content-Disposition"] =
    %[form-data; name="file"; filename="#{filename}"; size=#{content.bytesize}]
  body = IO::Memory.new(content)
  part = HTTP::FormData::Part.new(headers: headers, body: body)
  Lucky::UploadedFile.new(part)
end
