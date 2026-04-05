require "../../spec_helper"

private struct TestFFmpegProcessor
  include Latch::Processor::FFmpeg

  original video_codec: "libx264", crf: 23, preset: "ultrafast"
  variant preview, scale: "32:-2", video_codec: "libx264", crf: 28, preset: "ultrafast"
  variant thumb, frames: 1, scale: "32:-2"
end

private struct FFmpegUploader
  include Latch::Uploader

  process videos, using: TestFFmpegProcessor
end

describe Latch::Processor::FFmpeg do
  memory_store = Latch::Storage::Memory.new

  before_each do
    memory_store.clear!

    Latch.configure do |settings|
      settings.storages["cache"] = Latch::Storage::Memory.new
      settings.storages["store"] = memory_store
    end
  end

  describe "VARIANTS constant" do
    it "contains all defined variants" do
      TestFFmpegProcessor::VARIANTS.size.should eq(2)
      TestFFmpegProcessor::VARIANTS["preview"][:video_codec].should eq("libx264")
      TestFFmpegProcessor::VARIANTS["preview"][:crf].should eq(28)
      TestFFmpegProcessor::VARIANTS["preview"][:scale].should eq("32:-2")
      TestFFmpegProcessor::VARIANTS["thumb"][:frames].should eq(1)
    end
  end

  describe "ORIGINAL_OPTIONS constant" do
    it "stores the original processing options" do
      original = TestFFmpegProcessor::ORIGINAL_OPTIONS.first
      original[:video_codec].should eq("libx264")
      original[:crf].should eq(23)
      original[:preset].should eq("ultrafast")
    end
  end

  describe "#process" do
    it "creates variant files in storage" do
      stored = FFmpegUploader.store(build_uploaded_file(
        path: "spec/fixtures/tiny_video.mp4",
        filename: "video.mp4",
      ))

      FFmpegUploader.process(stored)

      memory_store.exists?(stored.variant_location("videos_preview")).should be_true
      memory_store.exists?(stored.variant_location("videos_thumb")).should be_true
    end

    it "processes the original file in place" do
      stored = FFmpegUploader.store(build_uploaded_file(
        path: "spec/fixtures/tiny_video.mp4",
        filename: "video.mp4",
      ))

      original_content = memory_store.open(stored.id).gets_to_end

      FFmpegUploader.process(stored)

      processed_content = memory_store.open(stored.id).gets_to_end
      processed_content.should_not eq(original_content)
    end
  end

  describe "variant accessors" do
    it "generates accessor methods on StoredFile" do
      stored = FFmpegUploader.store(build_uploaded_file(
        path: "spec/fixtures/tiny_video.mp4",
        filename: "video.mp4",
      ))

      stored.responds_to?(:videos_preview).should be_true
      stored.responds_to?(:videos_thumb).should be_true
    end

    it "returns variants that exist after processing" do
      stored = FFmpegUploader.store(build_uploaded_file(
        path: "spec/fixtures/tiny_video.mp4",
        filename: "video.mp4",
      ))

      FFmpegUploader.process(stored)

      stored.videos_preview.exists?.should be_true
      stored.videos_thumb.exists?.should be_true
    end
  end
end

private def build_uploaded_file(
  path : String? = nil,
  filename : String = "test.mp4",
  content : String? = nil,
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
  part = HTTP::FormData::Part.new(headers: headers, body: body)
  Lucky::UploadedFile.new(part)
end
