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
end
