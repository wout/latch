require "../../spec_helper"
require "../../support/avram"

struct TestImageUploader
  include Latch::Uploader
end

class AttachableItem < BaseModel
  include Latch::Avram::Model

  table do
    attach image : TestImageUploader::StoredFile?
  end
end

class AttachableItem::SaveOperation
  attach image
end

describe Latch::Avram::Model do
  describe "attach macro" do
    it "registers the path prefix" do
      AttachableItem::ATTACHMENT_PREFIX_IMAGE.should contain("attachable_item")
      AttachableItem::ATTACHMENT_PREFIX_IMAGE.should contain("image")
    end

    it "registers the uploader" do
      AttachableItem::ATTACHMENT_UPLOADER_IMAGE.should eq(TestImageUploader)
    end

    it "creates a DeleteOperation" do
      {{ AttachableItem::DeleteOperation < Avram::DeleteOperation(AttachableItem) }}.should be_true
    end
  end
end

class TestStoredFile
  property size : Int64?
  property mime_type : String?

  def initialize(@size : Int64? = nil, @mime_type : String? = nil)
  end

  def size? : Int64?
    @size
  end

  def mime_type? : String?
    @mime_type
  end
end

private def file_attribute(file : T) : Avram::Attribute(T) forall T
  Avram::Attribute.new(value: file, param: nil, param_key: "fake", name: :fake)
end

private def nil_file_attribute : Avram::Attribute(TestStoredFile?)
  Avram::Attribute(TestStoredFile?).new(value: nil, param: nil, param_key: "fake", name: :fake)
end

private def stored_file(size : Int64? = nil, mime_type : String? = nil) : TestStoredFile
  TestStoredFile.new(size: size, mime_type: mime_type)
end

describe Latch::Avram::SaveOperation do
  describe "attach macro" do
    it "creates a file attribute" do
      op = AttachableItem::SaveOperation.new
      op.responds_to?(:image_file).should be_true
    end

    it "creates a delete attribute for nilable attachments" do
      op = AttachableItem::SaveOperation.new
      op.responds_to?(:delete_image).should be_true
    end
  end

  describe "validate_file_size_of" do
    op = AttachableItem::SaveOperation.new

    it "returns true when the attribute has no file" do
      op.validate_file_size_of(nil_file_attribute, max: 5_000_000_i64).should be_true
    end

    it "validates the file is not too small" do
      attr = file_attribute(stored_file(size: 500_i64))
      op.validate_file_size_of(attr, min: 1_000_i64).should be_false
      attr.errors.should eq(["must be at least 1000 bytes"])
    end

    it "validates the file is not too large" do
      attr = file_attribute(stored_file(size: 10_000_000_i64))
      op.validate_file_size_of(attr, max: 5_000_000_i64).should be_false
      attr.errors.should eq(["must not be larger than 5000000 bytes"])
    end

    it "validates within a min and max range" do
      attr = file_attribute(stored_file(size: 2_000_i64))
      op.validate_file_size_of(attr, min: 1_000_i64, max: 5_000_000_i64).should be_true
      attr.valid?.should be_true
    end

    it "fails when size is nil and allow_blank is false" do
      attr = file_attribute(stored_file)
      op.validate_file_size_of(attr, min: 1_000_i64).should be_false
      attr.errors.should eq(["must be at least 1000 bytes"])
    end

    it "passes when size is nil and allow_blank is true" do
      attr = file_attribute(stored_file)
      op.validate_file_size_of(attr, min: 1_000_i64, allow_blank: true).should be_true
      attr.valid?.should be_true
    end

    it "supports a custom message" do
      attr = file_attribute(stored_file(size: 10_000_000_i64))
      op.validate_file_size_of(attr, max: 5_000_000_i64, message: "is way too big").should be_false
      attr.errors.should eq(["is way too big"])
    end
  end

  describe "validate_file_mime_type_of" do
    op = AttachableItem::SaveOperation.new

    describe "with an allowed list" do
      it "returns true when the attribute has no file" do
        op.validate_file_mime_type_of(nil_file_attribute, in: ["image/png"]).should be_true
      end

      it "passes when the MIME type is in the allowed list" do
        attr = file_attribute(stored_file(mime_type: "image/png"))
        op.validate_file_mime_type_of(attr, in: ["image/png", "image/jpeg"]).should be_true
        attr.valid?.should be_true
      end

      it "fails when the MIME type is not in the allowed list" do
        attr = file_attribute(stored_file(mime_type: "image/gif"))
        op.validate_file_mime_type_of(attr, in: ["image/png", "image/jpeg"]).should be_false
        attr.errors.should eq(["is not an accepted file type"])
      end

      it "fails when the MIME type is nil and allow_blank is false" do
        attr = file_attribute(stored_file)
        op.validate_file_mime_type_of(attr, in: ["image/png"]).should be_false
        attr.errors.should eq(["is not an accepted file type"])
      end

      it "passes when the MIME type is nil and allow_blank is true" do
        attr = file_attribute(stored_file)
        op.validate_file_mime_type_of(attr, in: ["image/png"], allow_blank: true).should be_true
        attr.valid?.should be_true
      end

      it "supports a custom message" do
        attr = file_attribute(stored_file(mime_type: "image/gif"))
        op.validate_file_mime_type_of(attr, in: ["image/png"], message: "wrong file type").should be_false
        attr.errors.should eq(["wrong file type"])
      end
    end

    describe "with a pattern" do
      it "returns true when the attribute has no file" do
        op.validate_file_mime_type_of(nil_file_attribute, with: /image\/.*/).should be_true
      end

      it "passes when the MIME type matches the pattern" do
        attr = file_attribute(stored_file(mime_type: "image/png"))
        op.validate_file_mime_type_of(attr, with: /image\/.*/).should be_true
        attr.valid?.should be_true
      end

      it "fails when the MIME type does not match the pattern" do
        attr = file_attribute(stored_file(mime_type: "video/mp4"))
        op.validate_file_mime_type_of(attr, with: /image\/.*/).should be_false
        attr.errors.should eq(["is not an accepted file type"])
      end

      it "fails when the MIME type is nil and allow_blank is false" do
        attr = file_attribute(stored_file)
        op.validate_file_mime_type_of(attr, with: /image\/.*/).should be_false
        attr.errors.should eq(["is not an accepted file type"])
      end

      it "passes when the MIME type is nil and allow_blank is true" do
        attr = file_attribute(stored_file)
        op.validate_file_mime_type_of(attr, with: /image\/.*/, allow_blank: true).should be_true
        attr.valid?.should be_true
      end

      it "supports a custom message" do
        attr = file_attribute(stored_file(mime_type: "video/mp4"))
        op.validate_file_mime_type_of(attr, with: /image\/.*/, message: "images only").should be_false
        attr.errors.should eq(["images only"])
      end
    end
  end
end
