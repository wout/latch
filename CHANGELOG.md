# Changelog

All notable changes to this project will be documented in this file.

## [0.3.1] - 2026-04-05

### Added

- **Nilable variant accessors** (e.g. `stored.sizes_thumb?`) that return `nil`
  if the variant hasn't been processed yet, making template rendering safer.

## [0.3.0] - 2026-04-05

### Added

- **FFmpeg processor** for video and audio transformations with compile-time
  validated options (codec, bitrate, scaling, thumbnails, and more).
- **Vips processor** using `vipsthumbnail` for high-performance image
  processing with smart cropping, quality control, and format conversion.
- **DimensionsFromVips extractor** using `vipsheader` as an alternative to
  the ImageMagick-based dimension extractor.
- **File attachment validations** for Avram SaveOperations:
  `validate_file_size_of` and `validate_file_mime_type_of` (with allowed list
  or regex pattern).
- **`StringOrInt` type alias** for processor options like `quality`, `crf`,
  `rotate`, `density`, `frames`, `frame_rate`, and `duration`, allowing both
  integer and string values.
- **Expanded ImageMagick options:** `auto_orient`, `background`, `colorspace`,
  `density`, `flatten`, `gaussian_blur`, `interlace`, `rotate`,
  `sampling_factor`, `sharpen`, `strip`, and `thumbnail`.
- Background processing example with Mel in the README.
- StoredFile extensibility example in the README.

### Changed

- Processor option `quality` accepts `Int32` in addition to `String` across
  all built-in processors.
- Processing block in Avram `attach` now takes a single argument (the record)
  instead of two (stored file and record). The stored file is accessible via
  the record.
- Simplified nilability detection in processor macros using `resolve.nilable?`.

### Fixed

- **Variant cleanup on delete:** `StoredFile#delete` now removes all variant
  files before deleting the original.
- ImageMagick processor now converts underscores to hyphens in option names
  (e.g. `auto_orient` becomes `-auto-orient`).
- ImageMagick processor falls back to `convert` when `magick` is not available
  (ImageMagick 6 compatibility).
- Extractor aliases removed to avoid having two ways to reference the same
  extractor.

## [0.2.0] - 2026-04-05

### Added

- **FFmpeg processor** for video and audio transformations.
- **Vips processor** for high-performance image processing.
- **DimensionsFromVips extractor** as an alternative to ImageMagick.
- **Avram file validations** (`validate_file_size_of`,
  `validate_file_mime_type_of`) extracted from the Avram PR.
- API docs link in the README.

### Fixed

- Variant files are cleaned up when the stored file is deleted.
- ImageMagick `thumbnail` command compatibility.

## [0.1.0] - 2026-04-04

### Added

- **Uploaders** with pluggable storage keys, custom locations, and metadata
  extraction (`filename`, `mime_type`, `size` by default).
- **Two-stage upload workflow:** cache first, promote later.
- **Processor system** with `variant`, `original`, and `process do` macros.
  Variants run in parallel via fibers.
- **ImageMagick processor** (`Latch::Processor::Magick`).
- **Avram integration** (`Latch::Avram::Model`) with `attach` macro for
  models and SaveOperations, including automatic caching, promotion, cleanup,
  and inline or background processing support.
- **Framework-agnostic design** via the `Latch::UploadedFile` interface.
  Built-in Lucky support, adaptable to Kemal or any other Crystal framework.
- **Storage backends:** FileSystem, S3 (with presigned URLs), and Memory.
- **Metadata extractors:** `FilenameFromIO`, `MimeFromIO`, `SizeFromIO`,
  `MimeFromExtension`, `MimeFromFile`, `DimensionsFromMagick`.
- **Custom extractors** via the `Latch::Extractor` interface.
- **StoredFile** with JSON serialization (Shrine-compatible format),
  downloading, streaming, and variant accessors.
- `StoredFile#process` shortcut for `Uploader.process(stored)`.
- Compile-time validation of processor options with helpful error messages.
- Lucky removed as a hard dependency (optional via
  `require "latch/lucky/uploaded_file"`).
