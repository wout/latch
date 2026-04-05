require "./storage"

module Latch
  alias MetadataValue = String | Int64 | Int32 | Float64 | Bool | Nil
  alias MetadataHash = Hash(String, MetadataValue)

  # Accepts both integers and strings for processor options like quality,
  # density, and rotation where either form feels natural.
  alias StringOrInt = Int32 | String | Nil

  annotation MetadataMethods
  end

  annotation VariantOptions
  end

  class Error < Exception; end

  class FileNotFound < Error; end

  class InvalidFile < Error; end

  class CliToolNotFound < Error; end
end
