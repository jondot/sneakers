require 'stringio'
require 'zlib'

# Simple gzip encoder/decoder for testing
def gzip_compress(s)
  io = StringIO.new('w')
  w = Zlib::GzipWriter.new(io)
  w.write(s)
  w.close
  io.string
end

def gzip_decompress(s)
  Zlib::GzipReader.new(StringIO.new(s, 'rb')).read
end
