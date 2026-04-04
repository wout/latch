# Interface for uploaded file objects. Include this module in your framework's
# uploaded file class to make it compatible with Latch.
#
# Only `tempfile` and `filename` are required. The other methods have sensible
# defaults that can be overridden.
#
# ```
# struct MyUploadedFile
#   include Latch::UploadedFile
#
#   getter tempfile : File
#   getter filename : String
#
#   def initialize(@tempfile, @filename)
#   end
# end
# ```
#
module Latch::UploadedFile
  abstract def tempfile : File
  abstract def filename : String

  def path : String
    tempfile.path
  end

  def content_type : String?
    nil
  end

  def size : UInt64
    tempfile.size
  end
end
