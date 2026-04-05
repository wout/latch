# Latch

File attachments for Crystal. Cache, promote, process, and serve uploads with
pluggable storage, metadata extraction, and file variant generation.

- **Two-stage uploads.** Cache first, promote later for safer form handling.
- **File processing.** Constrain originals, create variants, run in parallel.
- **Avram integration.** Attach files to models with a single macro.
- **Pluggable storage.** FileSystem, S3, and Memory out of the box.
- **Metadata extraction.** Filename, MIME type, size, and image dimensions.
- **Framework-agnostic.** Built-in Lucky support, adaptable to Kemal or any
  other Crystal framework.

The name is short for **L**ucky **At**ta**ch**ment. While originally created for
[Lucky](https://github.com/luckyframework/lucky), Latch can be used with any
Crystal framework.

[![CI](https://github.com/wout/latch/actions/workflows/ci.yml/badge.svg)](https://github.com/wout/latch/actions/workflows/ci.yml)
[![GitHub tag](https://img.shields.io/github/v/tag/wout/latch)](https://github.com/wout/latch/tags)

## Table of contents

- [Quick start](#quick-start)
- [Installation](#installation)
- [Configuration](#configuration)
- [Uploaders](#uploaders)
- [Avram integration](#avram-integration)
  - [Model setup](#model-setup)
  - [SaveOperation setup](#saveoperation-setup)
  - [Processing after upload](#processing-after-upload)
  - [Validating attachments](#validating-attachments)
- [Processors](#processors)
  - [ImageMagick processor](#imagemagick-processor)
  - [FFmpeg processor](#ffmpeg-processor)
  - [Vips processor](#vips-processor)
  - [Processing the original](#processing-the-original)
  - [Custom processors](#custom-processors)
- [Storage backends](#storage-backends)
- [Metadata extractors](#metadata-extractors)
- [Working with stored files](#working-with-stored-files)
- [Other frameworks](#other-frameworks)
- [API docs](#api-docs)

## Quick start

Set up your uploader:

```crystal
# src/uploaders/avatar_uploader.cr

struct AvatarProcessor
  include Latch::Processor::Magick

  original resize: "2000x2000>"
  variant thumb, resize: "200x200", gravity: "center"
end

struct AvatarUploader
  include Latch::Uploader

  extract dimensions, using: Latch::Extractor::DimensionsFromMagick
  process versions, using: AvatarProcessor
end

# src/models/user.cr

class User < BaseModel
  include Latch::Avram::Model

  table do
    attach avatar : AvatarUploader::StoredFile?
  end
end

# src/operations/save_user.cr

class User::SaveOperation < User::BaseOperation
  attach avatar, process: true
end
```

Upload a file:

```crystal
user = User::SaveOperation.create!(avatar_file: uploaded_file)
user.avatar.url # => "/uploads/user/1/avatar/a1b2c3d4.jpg"
user.avatar.versions_thumb.url # => "/uploads/user/1/avatar/a1b2c3d4/versions_thumb.jpg"
user.avatar.width # => 2000
```

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     latch:
       github: wout/latch
   ```

2. Run `shards install`

3. Require Latch with your framework integration:

   ```crystal
   require "latch"
   require "latch/lucky/avram" # Lucky + Avram
   ```

   Other combinations:

   ```crystal
   require "latch/lucky/uploaded_file" # Lucky without Avram
   require "latch/avram/model"         # Avram without Lucky
   ```

## Configuration

```crystal
Latch.configure do |settings|
  settings.storages["cache"] = Latch::Storage::FileSystem.new(
    directory: "uploads", prefix: "cache"
  )
  settings.storages["store"] = Latch::Storage::FileSystem.new(
    directory: "uploads"
  )
  settings.path_prefix = ":model/:id/:attachment"
end
```

For tests, use the in-memory backend:

```crystal
Latch.configure do |settings|
  settings.storages["cache"] = Latch::Storage::Memory.new
  settings.storages["store"] = Latch::Storage::Memory.new
end
```

## Uploaders

An uploader defines how files are stored and what metadata is extracted.

```crystal
struct ImageUploader
  include Latch::Uploader
end
```

Every uploader automatically extracts `filename`, `mime_type`, and `size`.
These are available as methods on the returned `StoredFile`.

### Uploading files

```crystal
# Cache (temporary storage, e.g. between form submissions)
cached = ImageUploader.cache(uploaded_file)

# Promote from cache to permanent storage
stored = ImageUploader.promote(cached)

# Or store directly
stored = ImageUploader.store(uploaded_file)
```

### Custom upload locations

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

By default, uploaders use `"cache"` and `"store"`. Override with the
`storages` macro:

```crystal
struct ImageUploader
  include Latch::Uploader

  storages cache: "tmp", store: "offsite"
end
```

## Avram integration

Latch integrates with [Avram](https://github.com/luckyframework/avram) for
model-level file attachments with automatic caching, promotion, and cleanup.

### Model setup

Use the `attach` macro inside a `table` block. The column should be a `jsonb`
type in your migration:

```crystal
class User < BaseModel
  include Latch::Avram::Model

  table do
    attach avatar : ImageUploader::StoredFile?
  end
end
```

```crystal
# In your migration
add avatar : JSON::Any?
```

### SaveOperation setup

The `attach` macro registers a file attribute and lifecycle hooks:

```crystal
class User::SaveOperation < User::BaseOperation
  attach avatar
end
```

The file attribute defaults to `avatar_file`. A custom name can be provided:

```crystal
attach avatar, field_name: "avatar_upload"
```

For nilable attachments, a `delete_avatar` attribute is added automatically:

```crystal
User::SaveOperation.update!(user, delete_avatar: true)
```

### Processing after upload

To run processors after promotion, pass `process: true`:

```crystal
attach avatar, process: true
```

For background processing, pass a block instead:

```crystal
attach avatar do |record|
  ProcessAvatarJob.perform_async(record.id)
end
```

### Validating attachments

Validate file size and MIME type in a `before_save` block:

```crystal
class User::SaveOperation < User::BaseOperation
  attach avatar

  before_save do
    validate_file_size_of avatar_file, max: 5_000_000
    validate_file_mime_type_of avatar_file, in: %w[image/png image/jpeg image/webp]
  end
end
```

MIME types can also be validated with a pattern:

```crystal
validate_file_mime_type_of avatar_file, with: /image\/.*/
```

### Upload lifecycle

1. **Before save** the file is cached to temporary storage
2. **After commit** the cached file is promoted to permanent storage
3. **After promotion** processors run (if configured)
4. **On update** the old file is replaced
5. **On delete** the attached file is removed

## Processors

Processors transform uploaded files into variants and can optionally modify
the original. Processing is decoupled from uploading, runs in parallel for
variants, and can be triggered inline or in a background job.

### ImageMagick processor

The built-in `Latch::Processor::Magick` module wraps `magick convert`. Define
variants with compile-time validated options:

```crystal
struct AvatarProcessor
  include Latch::Processor::Magick

  original resize: "2000x2000>"
  variant large, resize: "800x800"
  variant thumb, resize: "200x200", gravity: "center"
end
```

Typos are caught at compile time. All built-in options are optional, but
custom processors can declare required options.

<details>
<summary>**Available options**</summary>

- `auto_orient: true` → fix orientation from EXIF data
- `background: "white"` → background color, e.g. "white", "transparent"
- `colorspace: "sRGB"` → convert color model, e.g. "sRGB", "Gray"
- `crop: "200x200+10+10"` → cut a region
- `density: "72"` → resolution in DPI
- `extent: "800x600"` → pad/canvas size
- `flatten: true` → merge layers into one
- `gaussian_blur: "0x3"` → blur effect
- `gravity: "center"` → anchor point, e.g. "center", "north"
- `interlace: "Plane"` → progressive rendering
- `quality: "85"` → compression quality
- `resize: "800x600"` → scale to fit, e.g. "800x600", "200x200>"
- `rotate: "90"` → rotate by degrees
- `sampling_factor: "4:2:0"` → chroma subsampling
- `sharpen: "0x1"` → sharpen
- `strip: true` → remove all metadata and profiles
- `thumbnail: "200x200"` → like resize but strips profiles for smaller files

</details>

> [!IMPORTANT]
> Requires ImageMagick to be installed.

### FFmpeg processor

The built-in `Latch::Processor::FFmpeg` module wraps `ffmpeg` for video and
audio transformations:

```crystal
struct VideoProcessor
  include Latch::Processor::FFmpeg

  original video_codec: "libx264", crf: "23", preset: "fast"
  variant preview, scale: "640:-1", video_codec: "libx264", crf: "28"
  variant thumb, frames: "1", format: "image2", scale: "320:-1"
end
```

<details>
<summary>**Available options**</summary>

- `audio_bitrate: "128k"` → audio bitrate
- `audio_codec: "aac"` → audio codec, e.g. "aac", "libopus"
- `audio_filter: "volume=0.5"` → custom audio filter
- `crf: "23"` → constant rate factor (quality)
- `duration: "10"` → max duration in seconds
- `format: "webm"` → output format, e.g. "mp4", "webm", "image2"
- `frame_rate: "30"` → output frame rate
- `frames: "1"` → number of frames to output (for thumbnails)
- `no_audio: true` → strip audio track
- `preset: "fast"` → encoding speed/quality, e.g. "fast", "slow"
- `scale: "1280:720"` → resize, e.g. "1280:720", "-1:480"
- `start: "00:00:05"` → start time
- `video_bitrate: "1M"` → video bitrate, e.g. "1M", "500k"
- `video_codec: "libx264"` → video codec, e.g. "libx264", "libx265"
- `video_filter: "transpose=1"` → custom video filter

</details>

> [!IMPORTANT]
> Requires FFmpeg to be installed.

### Vips processor

The built-in `Latch::Processor::Vips` module uses `vipsthumbnail` for resize
operations and `vips copy` for metadata/format changes:

```crystal
struct AvatarProcessor
  include Latch::Processor::Vips

  original resize: "2000x2000>", strip: true
  variant large, resize: "800x800"
  variant thumb, resize: "200x200", crop: true, quality: 85
end
```

<details>
<summary>**Available options**</summary>

- `auto_orient: true` → fix orientation from EXIF data
- `crop: true` → crop to fill instead of shrink-to-fit
- `format: "webp"` → output format, e.g. "webp", "png"
- `linear: true` → process in linear color space (higher quality)
- `quality: 85` → JPEG/WebP compression quality (1-100)
- `resize: "200x200"` → bounding box, e.g. "200x200", "800x", "2000x2000>"
- `smartcrop: "attention"` → smart crop mode, e.g. "attention", "entropy"
- `strip: true` → remove all metadata and profiles

</details>

> [!IMPORTANT]
> Requires libvips to be installed.

### Processing the original

The `original` macro processes the uploaded file in place without creating a
copy. Variants are always processed first so they use the maximum available
quality.

```crystal
struct AvatarProcessor
  include Latch::Processor::Magick

  original resize: "2000x2000>"
end
```

> [!NOTE]
> If `original` is not declared, the uploaded file remains as-is.

### Registering and running processors

Register a processor on an uploader with the `process` macro:

```crystal
struct AvatarUploader
  include Latch::Uploader

  process versions, using: AvatarProcessor
end
```

Processing runs separately from uploading:

```crystal
stored = AvatarUploader.store(uploaded_file)
stored.process
```

Variant accessors are generated on `StoredFile`, prefixed with the processor
name:

```crystal
stored.versions_large.url     # => "/uploads/abc123/versions_large.jpg"
stored.versions_thumb.url     # => "/uploads/abc123/versions_thumb.jpg"
stored.versions_thumb.exists? # => true
```

### Custom processors

Create a module with `@[Latch::VariantOptions(...)]` and use the `process`
macro to define per-variant logic. The block should return an `IO`:

```crystal
@[Latch::VariantOptions(quality: Int32)]
module MyQualityProcessor
  include Latch::Processor

  process do
    do_your_thing_with_the(tempfile, variant_options) # return an IO
  end
end

struct QualityProcessor
  include MyQualityProcessor

  variant high, quality: 95
  variant low, quality: 30
end
```

The block runs with `stored_file`, `storage`, `name`, `tempfile`,
`variant_name`, and `variant_options` in scope.

For full control, bypass the `process` macro and generate `self.process`
directly with an `included` macro:

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
          io = do_your_thing_with_the(tempfile, variant_options)
          storage.upload(io, location)
        end
      end
    end
  end
end
```

## Storage backends

### FileSystem

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

Works with AWS S3 and any S3-compatible service
([RustFS](https://github.com/rustfs/rustfs), Tigris, Cloudflare R2):

> [!NOTE]
> RustFS is the open-source successor to MinIO, whose repository has been
> archived.

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

Inherit from `Latch::Storage` and implement five methods:

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

- **`FilenameFromIO`** (`filename`) Original filename from the upload
- **`MimeFromIO`** (`mime_type`) MIME type from the Content-Type header
- **`SizeFromIO`** (`size`) File size in bytes

Additional extractors can be registered with the `extract` macro:

- **`MimeFromExtension`** (`mime_type`) → MIME type from the file extension
- **`MimeFromFile`** (`mime_type`) → requires `file` CLI tool
- **`DimensionsFromMagick`** (`width`, `height`) → requires `magick` or `identify`
- **`DimensionsFromVips`** (`width`, `height`) → requires `vipsheader`

```crystal
struct ImageUploader
  include Latch::Uploader

  extract mime_type, using: Latch::Extractor::MimeFromFile
  extract dimensions, using: Latch::Extractor::DimensionsFromMagick
end
```

### Custom extractors

Create a struct that includes `Latch::Extractor`:

```crystal
struct PageCountExtractor
  include Latch::Extractor

  def extract(uploaded_file, metadata, **options) : Int32?
    count_pages(uploaded_file.tempfile)
  end
end
```

Register it and access the value on the stored file:

```crystal
struct PdfUploader
  include Latch::Uploader
  extract pages, using: PageCountExtractor
end

stored = PdfUploader.store(uploaded_file)
stored.pages # => 24
```

## Working with stored files

`StoredFile` objects are JSON-serializable and provide convenience methods for
accessing, downloading, and streaming files:

```crystal
stored.url                    # storage URL
stored.exists?                # check existence
stored.extension              # file extension
stored.delete                 # remove from storage

stored.open { |io| io.gets_to_end }         # read content
stored.download { |tempfile| use(tempfile) } # download to tempfile
stored.stream(response.output)               # stream to IO
```

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

## Other frameworks

Latch works with any Crystal framework. Implement the `Latch::UploadedFile`
module on your framework's upload class:

```crystal
module Latch::UploadedFile
  abstract def tempfile : File
  abstract def filename : String

  # Optional overrides with sensible defaults:
  # def path : String         -> tempfile.path
  # def content_type : String? -> nil
  # def size : UInt64         -> tempfile.size
end
```

### Kemal example

```crystal
require "kemal"
require "latch"

struct Kemal::FileUpload
  include Latch::UploadedFile

  def filename : String
    @filename || "upload"
  end

  def content_type : String?
    headers["Content-Type"]?
  end
end

post "/upload" do |env|
  upload = env.params.files["image"]
  stored = ImageUploader.store(upload)
  stored.url
end
```

## API docs

Online API documentation is available at
[wout.github.io/latch](https://wout.github.io/latch/).

## Contributing

1. Fork it (<https://github.com/wout/latch/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Wout](https://github.com/wout) - creator and maintainer
