require "../run_command"

# Processor module for FFmpeg-based video and audio transformations. Include
# this module and use the `variant` macro to define variants. Options are
# mapped to FFmpeg flags.
#
# ```
# struct VideoProcessor
#   include Latch::Processor::FFmpeg
#
#   original video_codec: "libx264", crf: "23", preset: "fast"
#   variant preview, scale: "640:-1", video_codec: "libx264", crf: "28"
#   variant thumb, frames: "1", format: "image2", scale: "320:-1"
# end
# ```
#
@[Latch::VariantOptions(
  audio_bitrate: String?,         # audio bitrate, e.g. "128k"
  audio_codec: String?,           # audio codec, e.g. "aac", "libopus"
  audio_filter: String?,          # custom audio filter, e.g. "volume=0.5"
  crf: Latch::StringOrInt,        # constant rate factor, e.g. 23
  duration: Latch::StringOrInt,   # max duration, e.g. 10 or "00:01:30"
  format: String?,                # output format, e.g. "mp4", "webm", "image2"
  frame_rate: Latch::StringOrInt, # output frame rate, e.g. 30
  frames: Latch::StringOrInt,     # number of frames to output, e.g. 1
  no_audio: Bool?,                # strip audio track
  preset: String?,                # encoding speed/quality, e.g. "fast", "slow"
  scale: String?,                 # resize, e.g. "1280:720", "-1:480"
  start: String?,                 # start time, e.g. "00:00:05"
  video_bitrate: String?,         # video bitrate, e.g. "1M", "500k"
  video_codec: String?,           # video codec, e.g. "libx264", "libx265"
  video_filter: String?,          # custom video filter, e.g. "transpose=1"
)]
module Latch::Processor::FFmpeg
  include Latch::Processor

  process do
    args = process_build_args(variant_options)
    suffix = process_output_suffix(variant_options)
    output = File.tempfile("latch-variant", suffix)
    run_ffmpeg(tempfile.path, args, output.path)
    output.tap(&.rewind)
  end

  macro included
    extend Latch::RunCommand

    private def self.run_ffmpeg(input : String, args : Array(String), output : String) : Nil
      run_command("ffmpeg", ["-y", "-i", input] + args + [output])
    end

    # Determines the output file suffix from the format option.
    private def self.process_output_suffix(variant) : String?
      if fmt = variant[:format]?
        ".#{fmt.gsub("image2", "jpg")}"
      end
    end

    # Builds the FFmpeg argument array from variant options.
    private def self.process_build_args(variant) : Array(String)
      filters = [] of String
      filters << "scale=#{variant[:scale]}" if variant[:scale]?
      filters << variant[:video_filter].to_s if variant[:video_filter]?

      Array(String).new.tap do |args|
        args << "-c:v" << variant[:video_codec].to_s if variant[:video_codec]?
        args << "-c:a" << variant[:audio_codec].to_s if variant[:audio_codec]?
        args << "-b:v" << variant[:video_bitrate].to_s if variant[:video_bitrate]?
        args << "-b:a" << variant[:audio_bitrate].to_s if variant[:audio_bitrate]?
        args << "-crf" << variant[:crf].to_s if variant[:crf]?
        args << "-preset" << variant[:preset].to_s if variant[:preset]?
        args << "-r" << variant[:frame_rate].to_s if variant[:frame_rate]?
        args << "-ss" << variant[:start].to_s if variant[:start]?
        args << "-t" << variant[:duration].to_s if variant[:duration]?
        args << "-frames:v" << variant[:frames].to_s if variant[:frames]?
        args << "-f" << variant[:format].to_s if variant[:format]?
        args << "-an" if variant[:no_audio]?
        args << "-vf" << filters.join(",") unless filters.empty?
        args << "-af" << variant[:audio_filter].to_s if variant[:audio_filter]?
      end
    end
  end
end
