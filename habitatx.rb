require 'sinatra'
require 'sinatra/reloader'
require 'json'
require 'roo'
require 'erb'
require 'fileutils'
require 'active_record'
require 'sinatra/activerecord'
require 'pg'
require 'rake'

THINGS_FILE_PATH = '/db/things.json'
ITEMS_FILE_PATH = '/db/items.json'
OPENHAB_PATH = '/etc/openhab'


set :database_file, 'config/database.yml'

ActiveRecord::Base.establish_connection(
  adapter: 'postgresql',
  database: 'postgres', 
  username: 'habitatx'
)
class Template < ActiveRecord::Base
  belongs_to :datafiles
end

class Datafile < ActiveRecord::Base
  has_many :templates
end


def post_things(hash_json, template_code)
  for code in hash_json['data']
    erb_template = ERB.new(template_code) # テンプレート文字列を使用する
    output = erb_template.result(binding) # erbファイルを書き換える
    File.open("#{__dir__}/db/created_thing.erb", 'w') { |file| file.write(output) } # 新しいファイルにoutputでの変更を書き換える
    File.open("#{__dir__}/db/created_thing.erb", "r") do |input_file|
      File.open("#{__dir__}/db/fixed_thing.erb", "w") do |output_file|
        input_file.each_line do |line|
          output_file.write(line) unless line.strip.empty? # 空行以外を書き込み
        end
      end
    end
    FileUtils.cp("#{__dir__}/db/fixed_thing.erb", "#{OPENHAB_PATH}/things/#{code['thingID']}.things")
  end
  File.delete("#{__dir__}/db/created_thing.erb")
  File.delete("#{__dir__}/db/fixed_thing.erb")
end

def delete_things(hash_json)
  for code in hash_json['data']
    File.delete("#{OPENHAB_PATH}/things/#{code['thingID']}.things")
  end
end


def post_items(hash_json, template_code)
  for code in hash_json['data']
    erb_template = ERB.new(template_code) # テンプレート文字列を使用する
    output = erb_template.result(binding) # erbファイルを書き換える
    File.open("#{OPENHAB_PATH}/items/#{code['itemID']}.items", 'w') { |file| file.write(output) } # 新しいファイルにoutputでの変更を書き換える
  end
end

def delete_items(hash_json)
  for code in hash_json['data']
    File.delete("#{OPENHAB_PATH}/items/#{code['itemID']}.items")
  end
end



get '/' do
  erb :index
end

get '/doc/habitatx.pdf' do
  send_file File.join(settings.root, 'doc', 'habitatx.pdf'), type: 'application/pdf'
end



# get '/template' do
get '/template' do
  @template = Template.all
  erb :'template/index'
end

get '/template/new' do
  erb :'template/new'
end

# get '/template/:id' do
post '/template' do
  title_template = params[:title_template]
  content = params[:content]
  basename = params[:basename]
  file_type = params[:file_type]
  Template.create(title_template: title_template, content: content, basename: basename, file_type: file_type)

  redirect '/template'
end


get '/template/:id' do
  template = Template.find_by(id: params[:id])
  @title_template = template["title_template"]
  @content = template["content"]
  @basename = template["basename"]
  @file_type = template["file_type"]
  erb :'template/show'
end

get '/template/:id/edit' do
  template = Template.find_by(id: params[:id])
  @title_template = template["title_template"]
  @content = template["content"]
  @basename = template["basename"]
  @file_type = template["file_type"]
  erb :'/template/edit'
end

patch '/template/:id' do
  title_template = params[:title_template]
  content = params[:content]
  basename = params[:basename]
  file_type = params[:file_type]
  template = Template.find_by(id: params[:id])
  return unless template
  template.update(title_template: title_template, content: content, basename: basename, file_type: file_type)

  redirect "/template/#{params[:id]}"
end


delete '/template/:id' do
  template = Template.find_by(id: params[:id])
  return unless template

  template.destroy
  redirect '/template'
end



# get '/datafile' do
get '/datafile' do
  @datafile = Datafile.all
  erb :'datafile/index'
end

get '/datafile/new' do
  @template = Template.all
  erb :'datafile/new'
end

# get '/datafile/:id' do
post '/datafile' do
  @template = Template.all
  title_datafile = params[:title_datafile]
  table = params[:table]
  title_template = params[:title_template]
  
  doc = Roo::Excelx.new("#{__dir__}/db/excel/#{table}")
  doc.default_sheet = doc.sheets.first

  headers = {}
  (doc.first_column..doc.last_column).each do |col|
    headers[col] = doc.cell(doc.first_row, col)
  end

  hash = {}
  hash[:data] = []
  ((doc.first_row + 1)..doc.last_row).each do |row|
    row_data = {}
    headers.keys.each do |col|
      value = doc.cell(row, col)
      value = value.to_i if doc.celltype(row, col) == :float && value.modulo(1) == 0.0
      row_data[headers[col]] = value
    end
    hash[:data] << row_data
  end

  selected_template = Template.find_by(title_template: title_template)
  template_id = selected_template["id"]
  template_code = selected_template["content"]

  
  Datafile.create(title_datafile: title_datafile, table: hash, template_id: template_id)
  hash_to_json = hash.to_json
  hash_json = JSON.parse(hash_to_json)
  puts "kkkkkkkkk:#{hash_json.inspect}"
  if selected_template["file_type"] == "things"
    post_things(hash_json, template_code)
  else
    post_items(hash_json, template_code)
  end
  redirect '/datafile'
end

get '/datafile/:id' do
  datafile = Datafile.find_by(id: params[:id])
  @title_datafile = datafile["title_datafile"]
  @table = datafile["table"]
  template_id = datafile["template_id"]
  template_table_id = Template.find_by(id: template_id)
  @code = template_table_id["content"]
  erb :'datafile/show'
end

get '/datafile/:id/edit' do
  @template = Template.all
  datafile = Datafile.find_by(id: params[:id])
  @title_datafile = datafile["title_datafile"]
  @table = datafile["table"]
  @template_id = datafile["template_id"]
  erb :'/datafile/edit'
end


patch '/datafile/:id' do
  @template = Template.all
  datafile = Datafile.find_by(id: params[:id])
  title_datafile = params[:title_datafile]
  table = params[:table]
  puts table.inspect
  table_json = table.gsub('=>', ':')
  puts table_json.inspect
  table_data = JSON.parse(table_json)
  puts "sasasasasasa:#{table_data.inspect}"
  title_template = params[:title_template]

  selected_template = Template.find_by(title_template: title_template)
  template_id = selected_template["id"]
  template_code = selected_template["content"]
  return unless datafile
  datafile.update(title_datafile: title_datafile, table: table_data, template_id: template_id)

  hash_json = table_data
  puts "dedededede:#{hash_json.class}"
  puts hash_json.class
  if selected_template["file_type"] == "things"
    post_things(hash_json, template_code)
  else
    post_items(hash_json, template_code)
  end
  redirect "/datafile/#{params[:id]}"
end


delete '/datafile/:id' do
  @template = Template.all
  datafile = Datafile.find_by(id: params[:id])
  title_template = datafile["title_template"]
  template_id = datafile["template_id"]
  template = Template.find_by(id: template_id)
  return unless datafile

  datafile.destroy

  hash_json = datafile["table"]
  if template["file_type"] == "things"
    delete_things(hash_json)
  else
    delete_items(hash_json)
  end
  redirect '/datafile'
end
