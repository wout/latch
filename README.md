# Latch

File uploads with pluggable storage backends, metadata extraction, variant
processing, and a two-stage upload workflow. Supports local filesystem,
S3-compatible services, and in-memory storage for testing.

The name is short for **L**ucky **At**ta**ch**ment. This shard was originally
created for for [Lucky Framework](https://github.com/luckyframework/lucky), but
it can be used in any Crystal app.

- **Pluggable storage.** Ship with FileSystem, S3, and Memory backends, or
  build your own.
- **Metadata extraction.** Filename, MIME type, size, and image dimensions
  out of the box, with a macro for custom extractors.
- **Async file processing.** Create image variants or process videos, right
  after a commit or in a background job.
- **Two-stage uploads.** Cache first, promote later for safer form handling.
- **JSON-serializable.** StoredFile objects serialize to JSON for easy
  persistence in your database.

## Quick start

```crystal
require "latch"

# Define an uploader
struct ImageUploader
  include Latch::Uploader
end

# Upload a file
stored_file = ImageUploader.store(uploaded_file)
stored_file.url        # => "/uploads/a1b2c3d4.jpg"
stored_file.filename   # => "photo.jpg"
stored_file.mime_type  # => "image/jpeg"
stored_file.size       # => 102400
```

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     latch:
       github: wout/latch
   ```

2. Run `shards install`

3. Require the shard:

   ```crystal
   # src/shards.cr

   # ...
   require "latch"
   ```

## Configuration

Configure storage backends through Habitat:

```crystal
# config/latch.cr

Latch.configure do |settings|
  settings.storages["cache"] = Latch::Storage::FileSystem.new(
    directory: "uploads",
    prefix: "cache"
  )
  settings.storages["store"] = Latch::Storage::FileSystem.new(
    directory: "uploads"
  )
  settings.path_prefix = ":model/:id/:attachment"
end
```

For tests, use the in-memory backend:

```crystal
# spec/setup/latch.cr

Latch.configure do |settings|
  settings.storages["cache"] = Latch::Storage::Memory.new
  settings.storages["store"] = Latch::Storage::Memory.new
end
```

## Uploaders

Create an uploader by including `Latch::Uploader`:

```crystal
struct ImageUploader
  include Latch::Uploader
end
```

Each uploader automatically extracts `filename`, `mime_type`, and `size` from
the uploaded file. The extracted values are available as methods on the returned
`StoredFile`.

### Uploading files

There are three ways to upload:

```crystal
# Cache a file (temporary storage, e.g. between form submissions)
cached = ImageUploader.cache(uploaded_file)

# Promote a cached file to permanent storage
stored = ImageUploader.promote(cached)

# Or upload directly to permanent storage
stored = ImageUploader.store(uploaded_file)
```

### Custom upload locations

Override `generate_location` to control where files are stored:

```crystal
struct ImageUploader
  include Latch::Uploader

  def generate_location(uploaded_file, metadata, **options) : String
    date = Time.utc.to_s("%Y/%m/%d")
    File.join("images", date, super)
  end
end
```

### Custom storage keys

By default, uploaders use `"cache"` and `"store"` as storage keys. Use the
`storages` macro to change them:

```crystal
struct ImageUploader
  include Latch::Uploader

  # Override both
  storages cache: "tmp", store: "offsite"
end
```

You only need to specify the keys you want to change, the others keep their
defaults:

```crystal
struct ImageUploader
  include Latch::Uploader

  # Only change the store key, cache stays "cache"
  storages store: "offsite"
end
```

## Processors

Processors transform uploaded files into variants (e.g. resized images).
Processing is decoupled from uploading, so it can run inline or in a
background job.

### Using the MagickProcessor

The built-in `Latch::Processor::Magick` module handles ImageMagick-based
transformations. It declares its own variant options (`resize`, `gravity`,
`extent`, `crop`, `quality`, all optional strings). Just include it and
define variants:

```crystal
struct AvatarSizesProcessor
  include Latch::Processor::Magick

  variant large, resize: "2000x2000"
  variant small, resize: "200x200", gravity: "center"
end
```

Each variant option becomes a `-key value` pair passed to `magick convert`.
Typos and missing required options are caught at compile time.

### Custom processors

Create a module annotated with `@[Latch::VariantOptions(...)]` that includes
`Latch::Processor`. Use the `process` macro to define per-variant logic.
The block should return an `IO` with the processed content:

```crystal
@[Latch::VariantOptions(quality: Int32)]
module MyQualityProcessor
  include Latch::Processor

  process do
    transform(tempfile, variant_options) # returns IO
  end
end

struct QualityProcessor
  include MyQualityProcessor

  variant high, quality: 95
  variant low, quality: 30
end
```

The block runs inside a download/variant loop with `stored_file`, `storage`,
`name`, `tempfile`, `variant_name`, and `variant_options` in scope. Location
calculation and uploading are handled automatically.

For full control, you can bypass the `process` macro and generate
`self.process` directly:

```crystal
@[Latch::VariantOptions(quality: Int32)]
module MyQualityProcessor
  include Latch::Processor

  macro included
    def self.process(
      stored_file : Latch::StoredFile,
      storage : Latch::Storage,
      name : String,
      **options,
    ) : Nil
      stored_file.download do |tempfile|
        VARIANTS.each do |variant_name, variant_options|
          location = stored_file.variant_location("\#{name}_\#{variant_name}")
          io = transform(tempfile, variant_options)
          storage.upload(io, location)
        end
      end
    end
  end
end
```

### Registering processors

Use the `process` macro on your uploader:

```crystal
struct AvatarUploader
  include Latch::Uploader

  process sizes, using: AvatarSizesProcessor
end
```

### Running processors

Processing runs separately from uploading:

```crystal
stored = AvatarUploader.store(uploaded_file)
AvatarUploader.process(stored)
```

### Accessing variants

The `process` macro generates accessor methods on `StoredFile`, prefixed with
the processor name:

```crystal
stored.sizes_large.url     # => "/uploads/abc123/sizes_large.jpg"
stored.sizes_small.url     # => "/uploads/abc123/sizes_small.jpg"
stored.sizes_large.exists? # => true (after processing)
```

Multiple processors can be registered on the same uploader. The processor name
prevents naming collisions:

```crystal
struct AvatarUploader
  include Latch::Uploader

  process sizes, using: AvatarSizesProcessor
  process quality, using: AvatarQualityProcessor
end

stored.sizes_large.url    # => "/uploads/abc123/sizes_large.jpg"
stored.quality_high.url   # => "/uploads/abc123/quality_high.jpg"
```

## Storage backends

### FileSystem

Stores files on the local filesystem:

```crystal
Latch::Storage::FileSystem.new(
  directory: "uploads",
  prefix: "cache",                # optional subdirectory
  clean: true,                    # clean empty parent dirs on delete (default)
  permissions: File::Permissions.new(0o644),
  directory_permissions: File::Permissions.new(0o755)
)
```

### S3

Stores files on AWS S3 or any S3-compatible service (RustFS, Tigris,
Cloudflare R2):

```crystal
Latch::Storage::S3.new(
  bucket: "my-bucket",
  region: "eu-west-1",
  access_key_id: ENV["AWS_ACCESS_KEY_ID"],
  secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"],
  endpoint: "http://localhost:9000",   # optional, for S3-compatible services
  prefix: "uploads",                   # optional key prefix
  public: false,                       # set to true for public-read ACL
  upload_options: {                    # optional default headers
    "Cache-Control" => "max-age=31536000",
  }
)
```

> [!NOTE]
> S3 storage requires the `awscr-s3` shard. Add it to your `shard.yml`:
>
> ```yaml
> dependencies:
>   awscr-s3:
>     github: taylorfinnell/awscr-s3
> ```

Presigned URLs are supported:

```crystal
stored_file.url(expires_in: 1.hour)
```

### Memory

In-memory storage for testing:

```crystal
storage = Latch::Storage::Memory.new(
  base_url: "https://cdn.example.com"  # optional
)
storage.clear!  # reset between tests
```

### Custom storage

Implement your own by inheriting from `Latch::Storage`:

```crystal
class MyStorage < Latch::Storage
  def upload(io : IO, id : String, **options) : Nil
  end

  def open(id : String, **options) : IO
  end

  def exists?(id : String) : Bool
  end

  def url(id : String, **options) : String
  end

  def delete(id : String) : Nil
  end
end
```

## Metadata extractors

### Built-in extractors

Every uploader registers three extractors by default:

| Extractor        | Key         | Description                            |
| ---------------- | ----------- | -------------------------------------- |
| `FilenameFromIO` | `filename`  | Original filename from the upload      |
| `MimeFromIO`     | `mime_type` | MIME type from the Content-Type header |
| `SizeFromIO`     | `size`      | File size in bytes                     |

### Additional extractors

These can be registered on your uploader with the `extract` macro:

| Extractor              | Key(s)            | Requires                        |
| ---------------------- | ----------------- | ------------------------------- |
| `MimeFromExtension`    | `mime_type`       | -                               |
| `MimeFromFile`         | `mime_type`       | `file` CLI tool                 |
| `DimensionsFromMagick` | `width`, `height` | `magick` or `identify` CLI tool |

```crystal
struct ImageUploader
  include Latch::Uploader

  # Replace the default MIME extractor with one that uses the file utility
  extract mime_type, using: Latch::Extractor::MimeFromFile

  # Add image dimension extraction
  extract dimensions, using: Latch::Extractor::DimensionsFromMagick
end
```

Shorter aliases are available inside uploader definitions:

```crystal
struct ImageUploader
  include Latch::Uploader

  extract mime_type, using: MimeFromFileExtractor
  extract dimensions, using: DimensionsFromMagickExtractor
end
```

### Custom extractors

Create a struct that includes `Latch::Extractor`:

```crystal
struct PageCountExtractor
  include Latch::Extractor

  def extract(uploaded_file, metadata, **options) : Int32?
    # Return the value to store, or nil to skip
    count_pages(uploaded_file.tempfile)
  end
end
```

Then register it:

```crystal
struct PdfUploader
  include Latch::Uploader
  extract pages, using: PageCountExtractor
end

stored_file = PdfUploader.store(uploaded_file)
stored_file.pages  # => 24
```

## Working with stored files

`StoredFile` objects are JSON-serializable and provide several convenience
methods:

```crystal
stored_file.url                    # storage URL
stored_file.exists?                # check existence
stored_file.extension              # file extension
stored_file.delete                 # remove from storage

# Read content
stored_file.open { |io| io.gets_to_end }

# Download to a temp file
stored_file.download do |tempfile|
  process(tempfile.path)
end
# tempfile is automatically cleaned up

# Stream to an IO
stored_file.stream(response.output)
```

### JSON format

StoredFile serializes to a format compatible with
[Shrine](https://shrinerb.com):

```json
{
  "id": "uploads/a1b2c3d4.jpg",
  "storage": "store",
  "metadata": {
    "filename": "photo.jpg",
    "size": 102400,
    "mime_type": "image/jpeg"
  }
}
```

## Contributing

1. Fork it (<https://github.com/wout/latch/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Wout](https://github.com/wout) - creator and maintainer
