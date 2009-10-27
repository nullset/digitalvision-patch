require 'rubygems'
require 'find'
require 'digest/md5'
# require 'open-uri'
require 'typhoeus'
require 'carrot'
require 'cgi'
require 'active_record'

ActiveRecord::Base.establish_connection(
  :adapter => 'sqlite3',
  :database => '/Users/nn/projects/wrayco/digitalvision-patch/digitalvision.sqlite3',
  :pool => 5,
  :timeout => 5000
)
class Item < ActiveRecord::Base
end

ActiveRecord::Base.logger = Logger.new(STDOUT)
  
class HackCheck
  def initialize(root_local_path, website)
    @root_local_path = root_local_path
    @website = website
    @base_path = ''
    @filename = ''
    @item = nil
    @add_count = 0
    @pop_count = 0
    @ignore_files = ['.wmv', '.avi', '.mov', '.mp4', '.flv', '.mpg', '.jpg', '.tif', '.zip'].collect {|f| [f, f.upcase] }.flatten
    @q = Carrot.queue('input_files')
    # monitor_queue
  end
  
  def monitor_queue
    puts '---> Now monitoring queue'
    while path = @q.pop(:ack => true)
      puts "Popping: #{path}"
      pull(path)
      @q.ack
      @pop_count += 1
    end
    Carrot.stop
  end
  
  def check
    start_time = Time.now
    
    Find.find(@root_local_path) do |path|
      # next if File.directory?(path)
      next if @ignore_files.include?(File.extname(path))
      puts "Adding: #{path}"
      @q.publish(path)
      @add_count += 1
    end
    
    monitor_queue

    end_time = Time.now
    puts "\nIt took #{end_time - start_time} seconds to process #{@add_count} queued files (#{@pop_count} popped)"

    # Find.find(@root_local_path) do |path| 
    #   if File.file?(path)
    #     next if @ignore_files.include?(File.extname(path))
    #     @base_path = path.sub(@root_local_path, '')
    #     @filename = File.basename(@base_path)
    #     local_hash = Digest::MD5.hexdigest(File.read(path))
    #     @item = Item.find_by_path(@base_path)
    #     url = @website + @base_path
    # 
    #     # begin
    #       request = Remote.get(url.gsub(/ /, '%20')) # open(CGI::escape(url))
    #       if request.code == 200
    #         remote_hash = Digest::MD5.hexdigest(request.body)
    #         if remote_hash == local_hash
    #           state = 'synced'
    #         else
    #           state = 'different'
    #         end
    # 
    #         if @item
    #           @item.update_attributes(:local_hash => local_hash, :remote_hash => remote_hash, :state => state, :code => nil, :message => nil, :updated_at => Time.now)
    #         else
    #           @item = Item.create(:filename => @filename, :path => @base_path, :local_hash => local_hash, :url => url, :remote_hash => remote_hash, :state => state)
    #         end
    #       else
    #         code = request.code
    #         message = request.headers
    #         if @item
    #           remote_hash ||= nil
    #           @item.update_attributes(:local_hash => local_hash, :remote_hash => remote_hash, :state => 'unsynced', :code => code, :message => message, :updated_at => Time.now)
    #         else
    #           @item = Item.create(:filename => @filename, :path => @base_path, :local_hash => local_hash, :url => url, :code => code, :message => message)
    #         end
    #       end
    #         
    #     # rescue => e
    #     #   file = nil
    #     #   message = e.message
    #     # end
    #     
    #     # if file
    #     #   # can open file remotely
    #     #   remote_hash = Digest::MD5.hexdigest(file.body)
    #     #   if remote_hash == local_hash
    #     #     state = 'synced'
    #     #   else
    #     #     state = 'different'
    #     #   end
    #     #   
    #     #   if @item
    #     #     @item.update_attributes(:local_hash => local_hash, :remote_hash => remote_hash, :state => state, :message => nil, :updated_at => Time.now)
    #     #   else
    #     #     @item = Item.create(:filename => @filename, :path => @base_path, :local_hash => local_hash, :url => url, :remote_hash => remote_hash, :state => state)
    #     #   end
    #     # else
    #     #   # can't open file
    #     #   if @item
    #     #     remote_hash ||= nil
    #     #     @item.update_attributes(:local_hash => local_hash, :remote_hash => remote_hash, :state => 'unsynced', :message => message, :updated_at => Time.now)
    #     #   else
    #     #     @item = Item.create(:filename => @filename, :path => @base_path, :local_hash => local_hash, :url => url, :message => message)
    #     #   end
    #     # end
    #     i += 1
    #   end
    # end
  end
  
  def pull(path)
    if File.file?(path)
      @base_path = path.sub(@root_local_path, '')
      @filename = File.basename(@base_path)
      local_hash = Digest::MD5.hexdigest(File.read(path))
      @item = Item.find_by_path(@base_path)
      url = @website + @base_path

      request = Remote.get(url.gsub(/ /, '%20')) # open(CGI::escape(url))
      if request.code == 200
        remote_hash = Digest::MD5.hexdigest(request.body)
        if remote_hash == local_hash
          state = 'synced'
        else
          state = 'different'
        end

        if @item
          @item.update_attributes(:local_hash => local_hash, :remote_hash => remote_hash, :state => state, :code => nil, :message => nil, :updated_at => Time.now)
        else
          @item = Item.create(:filename => @filename, :path => @base_path, :local_hash => local_hash, :url => url, :remote_hash => remote_hash, :state => state)
        end
      else
        code = request.code
        message = request.headers
        if @item
          remote_hash ||= nil
          @item.update_attributes(:local_hash => local_hash, :remote_hash => remote_hash, :state => 'unsynced', :code => code, :message => message, :updated_at => Time.now)
        else
          @item = Item.create(:filename => @filename, :path => @base_path, :local_hash => local_hash, :url => url, :code => code, :message => message)
        end
      end
    end
  end
end

class Remote
  include Typhoeus
end

class CreateItems < ActiveRecord::Migration
  def self.up
    create_table :items do |t|
      t.string :filename, :null => false
      t.string :state, :default => 'unsynced'
      t.integer :code
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