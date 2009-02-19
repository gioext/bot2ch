# Bot2ch
# Copyright (c) 2009 Kazuki UCHIDA
# Licensed under the MIT License:
#   http://www.opensource.org/licenses/mit-license.php

require 'open-uri'
require 'kconv'
require 'yaml/store'
require 'net/http'

module Bot2ch
  class Menu
    def initialize
      @bbsmenu = 'http://menu.2ch.net/bbsmenu.html'
    end

    def get_board(subdir)
      reg = Regexp.new("href=(.+#{subdir})", Regexp::IGNORECASE)
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
      downloaders = [NormalImageDownloader, ImepitaDownloader]
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

  class Downloader
    attr_accessor :uri, :url

    def initialize(url)
      @url = url
      @uri = URI.parse(@url)
    end

    def save(res, saveTo)
      puts "download: #{url}"
      case res
      when Net::HTTPSuccess
        open(saveTo, 'wb') do |f|
          f.write res.body
        end
      end
    end
  end

  class NormalImageDownloader < Downloader
    def download(saveTo)
      http = Net::HTTP.new(uri.host, 80)
      res = http.get(uri.path)
      save(res, saveTo)
    end

    def self.match(url)
      url =~ /.jpg$/i
    end
  end

  class ImepitaDownloader < Downloader
    def download(saveTo)
      http = Net::HTTP.new(uri.host, 80)
      headers = {'Referer' => url}
      res = http.get("/image#{uri.path}", headers)
      save(res, saveTo)
    end

    def self.match(url)
      url =~ /\/\/imepita.jp\/\d+\/\d+/i
    end
  end

  class App
    def execute(subdir)
      root_dir = File.dirname(__FILE__)
      image_dir = "#{root_dir}/images"
      db = YAML::Store.new("#{root_dir}/log/thread.db")
      menu = Menu.new
      board = menu.get_board(subdir)
      threads = board.get_threads
      puts "total: #{threads.length} threads"
      threads.each do |thread|
        images = thread.get_images rescue next
        next if images.empty?
        parent_dir = "#{image_dir}/#{thread.dat_no}" 
        Dir.mkdir(parent_dir) unless File.exists?(parent_dir)
        puts "#{thread.title}: #{images.length} pics"
        downloaded = db.transaction { db[thread.dat_no] } || 0
        images.each_with_index do |image, index|
          next if index < downloaded
          image.download("#{parent_dir}/#{index}.jpg") rescue next
          sleep(0.2)
        end
        db.transaction { db[thread.dat_no] = images.length }
      end
    end
  end
end

Bot2ch::App.new.execute('news4vip')
