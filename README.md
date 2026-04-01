# Lucky Attachment

File uploads for [Lucky](https://github.com/luckyframework/lucky) with
pluggable storage backends, metadata extraction, and a two-stage upload
workflow. Supports local filesystem, S3-compatible services, and in-memory
storage for testing.

- **Pluggable storage.** Ship with FileSystem, S3, and Memory backends, or
  build your own.
- **Metadata extraction.** Filename, MIME type, size, and image dimensions
  out of the box, with a macro for custom extractors.
- **Two-stage uploads.** Cache first, promote later for safer form handling.
- **JSON-serializable.** StoredFile objects serialize to JSON for easy
  persistence in your database.

## Quick start

```crystal
require "lucky_attachment"

# Define an uploader
struct ImageUploader < Lucky::Attachment::Uploader
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
     lucky_attachment:
       github: wout/lucky_attachment
   ```

2. Run `shards install`

3. Require the shard:

   ```crystal
   # src/shards.cr

   # ...
   require "lucky_attachment"
   ```

## Configuration

Configure storage backends through Habitat:

```crystal
# config/lucky_attachment.cr

Lucky::Attachment.configure do |settings|
  settings.storages["cache"] = Lucky::Attachment::Storage::FileSystem.new(
    directory: "uploads",
    prefix: "cache"
  )
  settings.storages["store"] = Lucky::Attachment::Storage::FileSystem.new(
    directory: "uploads"
  )
  settings.path_prefix = ":model/:id/:attachment"
end
```

For tests, use the in-memory backend:

```crystal
# spec/setup/lucky_attachment.cr

Lucky::Attachment.configure do |settings|
  settings.storages["cache"] = Lucky::Attachment::Storage::Memory.new
  settings.storages["store"] = Lucky::Attachment::Storage::Memory.new
end
```

## Uploaders

Create an uploader by inheriting from `Lucky::Attachment::Uploader`:

```crystal
struct ImageUploader < Lucky::Attachment::Uploader
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
struct ImageUploader < Lucky::Attachment::Uploader
  def generate_location(uploaded_file, metadata, **options) : String
    date = Time.utc.to_s("%Y/%m/%d")
    File.join("images", date, super)
  end
end
```

### Custom storage keys

By default, uploaders use `"cache"` and `"store"` as storage keys. Override
`self.storages` to use different ones:

```crystal
struct ImageUploader < Lucky::Attachment::Uploader
  def self.storages : NamedTuple(cache: String, store: String)
    {cache: "tmp", store: "offsite"}
  end
end
```

## Storage backends

### FileSystem

Stores files on the local filesystem:

```crystal
Lucky::Attachment::Storage::FileSystem.new(
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
Lucky::Attachment::Storage::S3.new(
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
storage = Lucky::Attachment::Storage::Memory.new(
  base_url: "https://cdn.example.com"  # optional
)
storage.clear!  # reset between tests
```

### Custom storage

Implement your own by inheriting from `Lucky::Attachment::Storage`:

```crystal
class MyStorage < Lucky::Attachment::Storage
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

| Extractor | Key | Description |
|---|---|---|
| `FilenameFromIO` | `filename` | Original filename from the upload |
| `MimeFromIO` | `mime_type` | MIME type from the Content-Type header |
| `SizeFromIO` | `size` | File size in bytes |

### Additional extractors

These can be registered on your uploader with the `extract` macro:

| Extractor | Key(s) | Requires |
|---|---|---|
| `MimeFromExtension` | `mime_type` | - |
| `MimeFromFile` | `mime_type` | `file` CLI tool |
| `DimensionsFromMagick` | `width`, `height` | `magick` or `identify` CLI tool |

```crystal
struct ImageUploader < Lucky::Attachment::Uploader
  # Replace the default MIME extractor with one that uses the file utility
  extract mime_type, using: Lucky::Attachment::Extractor::MimeFromFile

  # Add image dimension extraction
  extract dimensions, using: Lucky::Attachment::Extractor::DimensionsFromMagick
end
```

Shorter aliases are available inside uploader definitions:

```crystal
struct ImageUploader < Lucky::Attachment::Uploader
  extract mime_type, using: MimeFromFileExtractor
  extract dimensions, using: DimensionsFromMagickExtractor
end
```

### Custom extractors

Create a struct that includes `Lucky::Attachment::Extractor`:

```crystal
struct PageCountExtractor
  include Lucky::Attachment::Extractor

  def extract(uploaded_file, metadata, **options) : Int32?
    # Return the value to store, or nil to skip
    count_pages(uploaded_file.tempfile)
  end
end
```

Then register it:

```crystal
struct PdfUploader < Lucky::Attachment::Uploader
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

1. Fork it (<https://github.com/wout/lucky_attachment/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Wout](https://github.com/wout) - creator and maintainer
