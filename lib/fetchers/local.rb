# encoding: utf-8
# author: Dominik Richter
# author: Christoph Hartmann

require 'openssl'

module Fetchers
  class Local < Inspec.fetcher(1)
    name 'local'
    priority 0

    def self.resolve(target)
      local_path = if target.is_a?(String)
                     resolve_from_string(target)
                   elsif target.is_a?(Hash)
                     # If target is a Hash then it is a dependency. We should
                     # archive it in order to create a checksum and vendor it.
                     do_vendor = true
                     resolve_from_hash(target)
                   end

      new(local_path, do_vendor: do_vendor) if local_path
    end

    def self.resolve_from_hash(target)
      return unless target.key?(:path)

      if target.key?(:cwd)
        File.expand_path(target[:path], target[:cwd])
      else
        target[:path]
      end
    end

    def self.resolve_from_string(target)
      # Support "urls" in the form of file://
      if target.start_with?('file://')
        target = target.gsub(%r{^file://}, '')
      else
        # support for windows paths
        target = target.tr('\\', '/')
      end

      target if File.exist?(target)
    end

    def initialize(target, opts)
      @target = target
      @do_vendor = opts[:do_vendor]
    end

    def fetch(path)
      return @target unless @do_vendor

      if File.directory?(@target)
        # Create an archive, checksum, and move to the vendor directory
        Dir.mktmpdir do |tmpdir|
          final_path = File.join(tmpdir, "#{File.basename(@target)}.tar.gz")
          opts = {
            backend: Inspec::Backend.create(target: 'mock://'),
            output: final_path,
          }
          Inspec::Profile.for_target(@target, opts).archive(opts)
          # Reassign `@target` for `#cache_key`
          @target = final_path
          FileUtils.mv(archive_path, File.join(path, "#{cache_key}.tar.gz"))
        end
      else
        # Verify profile (archive) is valid and extract to vendor directory
        opts = { backend: Inspec::Backend.create(target: 'mock://')}
        Inspec::Profile.for_target(@target, opts).check
        Inspec::FileProvider.for_path(@target).extract(path)
      end

      @target
    end

    def archive_path
      @target
    end

    def writable?
      File.directory?(@target)
    end

    def cache_key
      sha256.to_s
    end

    def sha256
      return nil if File.directory?(@target)
      @archive_shasum ||=
        OpenSSL::Digest::SHA256.digest(File.read(@target)).unpack('H*')[0]
    end

    def resolved_source
      h = { path: @target }
      h[:sha256] = sha256 if sha256
      h
    end
  end
end
