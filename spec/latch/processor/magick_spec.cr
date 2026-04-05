require "../../spec_helper"

private struct TestSizesProcessor
  include Latch::Processor::Magick

  original resize: "40x40"
  variant large, resize: "50x50"
  variant small, resize: "10x10"
end

private struct ProcessorUploader
  include Latch::Uploader

  process sizes, using: TestSizesProcessor
end

describe Latch::Processor::Magick do
  memory_store = Latch::Storage::Memory.new

  before_each do
    memory_store.clear!

    Latch.configure do |settings|
      settings.storages["cache"] = Latch::Storage::Memory.new
      settings.storages["store"] = memory_store
    end
  end

  describe "VARIANTS constant" do
    it "contains all defined variants as a hash of named tuples" do
      TestSizesProcessor::VARIANTS.size.should eq(2)
      TestSizesProcessor::VARIANTS["large"][:resize].should eq("50x50")
      TestSizesProcessor::VARIANTS["small"][:resize].should eq("10x10")
    end
  end

  describe "ORIGINAL_OPTIONS constant" do
    it "stores the original processing options" do
      TestSizesProcessor::ORIGINAL_OPTIONS.first[:resize].should eq("40x40")
    end
  end

  describe "#process" do
    it "creates variant files in storage" do
      stored = ProcessorUploader.store(build_uploaded_file(
        path: "spec/fixtures/lucky_logo_tiny.png",
        filename: "logo.png",
      ))

      ProcessorUploader.process(stored)

      memory_store.exists?(stored.variant_location("sizes_large")).should be_true
      memory_store.exists?(stored.variant_location("sizes_small")).should be_true
    end

    it "processes the original file in place" do
      stored = ProcessorUploader.store(build_uploaded_file(
        path: "spec/fixtures/lucky_logo_tiny.png",
        filename: "logo.png",
      ))

      original_content = memory_store.open(stored.id).gets_to_end

      ProcessorUploader.process(stored)

      processed_content = memory_store.open(stored.id).gets_to_end
      processed_content.should_not eq(original_content)
    end

    it "produces resized images" do
      stored = ProcessorUploader.store(build_uploaded_file(
        path: "spec/fixtures/lucky_logo_tiny.png",
        filename: "logo.png",
      ))

      ProcessorUploader.process(stored)

      # Verify the large variant exists and is a valid image
      large_location = stored.variant_location("sizes_large")
      io = memory_store.open(large_location)
      content = io.gets_to_end
      content.bytesize.should be > 0
      io.close
    end
  end

  describe "StoredFile variant accessors" do
    it "generates accessor methods for each variant" do
      stored = ProcessorUploader.store(build_uploaded_file(
        path: "spec/fixtures/lucky_logo_tiny.png",
        filename: "logo.png",
      ))

      ProcessorUploader.process(stored)

      stored.sizes_large.should be_a(ProcessorUploader::StoredFile)
      stored.sizes_small.should be_a(ProcessorUploader::StoredFile)
    end

    it "derives the correct variant location" do
      stored = ProcessorUploader.store(build_uploaded_file(
        path: "spec/fixtures/lucky_logo_tiny.png",
        filename: "logo.png",
      ))

      stored.sizes_large.id.should eq(stored.variant_location("sizes_large"))
      stored.sizes_small.id.should eq(stored.variant_location("sizes_small"))
    end

    it "preserves the storage key" do
      stored = ProcessorUploader.store(build_uploaded_file(
        path: "spec/fixtures/lucky_logo_tiny.png",
        filename: "logo.png",
      ))

      stored.sizes_large.storage_key.should eq("store")
    end

    it "returns a variant that exists after processing" do
      stored = ProcessorUploader.store(build_uploaded_file(
        path: "spec/fixtures/lucky_logo_tiny.png",
        filename: "logo.png",
      ))

      ProcessorUploader.process(stored)

      stored.sizes_large.exists?.should be_true
      stored.sizes_small.exists?.should be_true
    end

    it "deletes variants when the stored file is deleted" do
      stored = ProcessorUploader.store(build_uploaded_file(
        path: "spec/fixtures/lucky_logo_tiny.png",
        filename: "logo.png",
      ))

      ProcessorUploader.process(stored)
      stored.sizes_large.exists?.should be_true

      stored.delete

      stored.exists?.should be_false
      stored.sizes_large.exists?.should be_false
      stored.sizes_small.exists?.should be_false
    end

    it "returns a variant that does not exist before processing" do
      stored = ProcessorUploader.store(build_uploaded_file(
        path: "spec/fixtures/lucky_logo_tiny.png",
        filename: "logo.png",
      ))

      stored.sizes_large.exists?.should be_false
    end
  end
end

private def build_uploaded_file(
  path : String? = nil,
  filename : String = "test.txt",
  content : String? = nil,
  content_type : String? = nil,
) : Lucky::UploadedFile
  body = if path
           File.open(path)
         else
           IO::Memory.new(content || "")
         end
  size = path ? File.size(path) : (content || "").bytesize
  headers = HTTP::Headers.new
  headers["Content-Disposition"] =
    %[form-data; name="file"; filename="#{filename}"; size=#{size}]
  headers["Content-Type"] = content_type if content_type
  part = HTTP::FormData::Part.new(headers: headers, body: body)
  Lucky::UploadedFile.new(part)
end
