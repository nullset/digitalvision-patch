require 'rubygems'
require 'find'
require 'digest/md5'
require 'open-uri'
require 'cgi'
require 'active_record'

ActiveRecord::Base.establish_connection(
  :adapter => 'sqlite3',
  :database => '/Users/nn/Desktop/digitalvision.sqlite3',
  :pool => 5,
  :timeout => 5000
)
class Item < ActiveRecord::Base
end

ActiveRecord::Base.logger = Logger.new(STDOUT)
  
# 
# i = 0
# root = '/Users/nn/Downloads/digitalvision'
# Find.find(root) do |path| 
#   # if File.basename(path) =~ /file2$/
#   #   puts "PRUNED #{path}"
#   #   Find.prune
#   # end
#   if File.file?(path)
#     local_hash = Digest::MD5.hexdigest(File.read(path))
#     Item.create(:path => path.sub(root, ''), :local_hash => local_hash)
#     i += 1
#     break if i == 10
#   end
# end
# 
# puts "There are #{i} things"
# # 13579 files


class HackCheck
  def initialize(root_local_path, website)
    @root_local_path = root_local_path
    @website = website
    @base_path = ''
    @filename = ''
    @item = nil
    @ignore_files = ['.wmv', '.avi', '.mov', '.mp4', '.flv', '.mpg', '.jpg', '.tif', '.zip']
    @ignore_files = @ignore_files.collect {|i| [i, i.upcase] }.flatten
  end
  
  def check
    i = 0
    start_time = Time.now
    Find.find(@root_local_path) do |path| 
      if File.file?(path)
        next if @ignore_files.include?(File.extname(path))
        @base_path = path.sub(@root_local_path, '')
        @filename = File.basename(@base_path)
        local_hash = Digest::MD5.hexdigest(File.read(path))
        @item = Item.find_by_path(@base_path)
        url = @website + @base_path

        begin
          file = open(url.gsub(/ /, '%20')) # open(CGI::escape(url))
        rescue => e
          file = nil
          message = e.message
        end
        
        if file
          # can open file remotely
          remote_hash = Digest::MD5.hexdigest(file.read)
          if remote_hash == local_hash
            state = 'synced'
          else
            state = 'different'
          end
          
          if @item
            @item.update_attributes(:local_hash => local_hash, :remote_hash => remote_hash, :state => state, :message => nil, :updated_at => Time.now)
          else
            @item = Item.create(:filename => @filename, :path => @base_path, :local_hash => local_hash, :url => url, :remote_hash => remote_hash, :state => state)
          end
        else
          # can't open file
          if @item
            remote_hash ||= nil
            @item.update_attributes(:local_hash => local_hash, :remote_hash => remote_hash, :state => 'unsynced', :message => message, :updated_at => Time.now)
          else
            @item = Item.create(:filename => @filename, :path => @base_path, :local_hash => local_hash, :url => url, :message => message)
          end
        end
        i += 1
      end
    end
    end_time = Time.now
    puts "Took #{end_time - start_time} seconds to process #{i} files"
  end
  
  def file_in_db
    puts @item.inspect
    return false if @item.nil?
    return true
  end
end

class CreateItems < ActiveRecord::Migration
  def self.up
    create_table :items do |t|
      t.string :filename, :null => false
      t.string :state, :default => 'unsynced'
      t.string :message
      t.string :path, :null => false
      t.string :local_hash
      t.string :url, :null => false
      t.string :remote_hash
      t.string :message
      t.datetime :created_at
      t.datetime :updated_at
    end
    add_index :items, :path
    add_index :items, :state
  end

  def self.down
    drop_table :items
  end
end

# CreateItems.up
h = HackCheck.new('/Users/nn/Downloads/digitalvision', 'http://www.digitalvision.se')
h.check