require 'open-uri'
require 'kconv'

module Bot2ch
  class Menu
    def initialize
      @bbsmenu = 'http://menu.2ch.net/bbsmenu.html'
    end

    def get_board(board_name)
      reg = Regexp.new("href=(.+#{board_name})", Regexp::IGNORECASE)
      open(@bbsmenu) do |f|
        f.each do |line|
          return Board.new($1) if line =~ reg
        end
      end
    end
  end

  class Board
    def initialize(url)
      @url = url
      @subject = "#{url}/subject.txt"
    end

    def get_threads
      threads = []
      open(@subject) do |f|
        lines = f.read.toutf8
        lines.each do |line|
          dat, title = line.split('<>')
          threads << Thread.new("#{@url}/dat/#{dat}", title)
        end
      end
      threads
    end
  end

  class Thread
    attr_accessor :title

    def initialize(url, title)
      @dat = url
      @title = title.strip
    end

    def get_images
      images = []
      downloaders = [NormalImageDownloader]
      open(@dat) do |f|
        lines = f.read.toutf8
        lines.each do |line|
          contents = line.split('<>')[3]
          while contents =~ /\/\/[-_.!~*\'()a-zA-Z0-9;\/?:\@&=+\$,%#]+/i
            url = "http:#{$&}"
            contents = $'
            image_downloader = downloaders.find { |d| d.match(url) }
            next unless image_downloader
            images << image_downloader.new(url)
          end
        end
      end
      images
    end

    def dat_no
      File.basename(@dat, '.dat')
    end
  end

  class NormalImageDownloader
    def initialize(url)
      @url = url
    end

    def download(saveTo)
      puts "download: #{@url}"
      open(saveTo, 'wb') do |f|
        open(@url) do |img|
          f.write img.read
        end
      end
    end

    def self.match(url)
      url =~ /.jpg$/i
    end
  end

  class App
    def execute(board)
      image_root_dir = File.dirname(__FILE__) + '/images'
      menu = Menu.new
      board = menu.get_board(board)
      threads = board.get_threads
      puts "total: #{threads.length} threads"
      threads.each do |thread|
        images = thread.get_images
        next if images.empty?
        parent_dir = "#{image_root_dir}/#{thread.dat_no}" 
        Dir.mkdir(parent_dir) unless File.exists?(parent_dir)
        puts "#{thread.title}: #{images.length} pics"
        # restore
        images.each_with_index do |image, index|
          image.download("#{parent_dir}/#{index}.jpg") rescue next
        end
        # dump
      end
    end
  end
end

Bot2ch::App.new.execute('news4vip')
