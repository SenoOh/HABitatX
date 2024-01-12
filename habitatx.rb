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

def get_things(things_file_path)
  if File.zero?(things_file_path)
    {}
  else
    File.open(things_file_path) { |f| JSON.parse(f.read) }
  end
rescue Errno::ENOENT
  # ファイルが存在しない場合や読み込めない場合のエラーハンドリング
  {}
end

def set_things(things_file_path, things)
  File.open(things_file_path, 'w') { |f| f.write(JSON.pretty_generate(things)) }
end



def get_items(items_file_path)
  if File.zero?(items_file_path)
    {}
  else
    File.open(items_file_path) { |f| JSON.parse(f.read) }
  end
rescue Errno::ENOENT
  # ファイルが存在しない場合や読み込めない場合のエラーハンドリング
  {}
end


def set_items(items_file_path, items)
  File.open(items_file_path, 'w') { |f| f.write(JSON.pretty_generate(items)) }
end




def post_things(excel_things, things_erb)
  xlsx = Roo::Excelx.new("#{__dir__}/db/excel/#{excel_things}") # Excelファイルを指定
  variables = xlsx.row(1)
  (2..xlsx.last_row).each do |row_number|
    values = xlsx.row(row_number)
    data = {}
    variables.each_with_index do |variable, index|
      data[variable] = values[index] # Excelの1行目とn行目を対応付ける
    end
    erb_template = ERB.new(things_erb) # テンプレート文字列を使用する
    output = erb_template.result(binding) # erbファイルを書き換える
    File.open("#{__dir__}/db/created_thing.erb", 'w') { |file| file.write(output) } # 新しいファイルにoutputでの変更を書き換える
    File.open("#{__dir__}/db/created_thing.erb", "r") do |input_file|
      File.open("#{__dir__}/db/fixed_thing.erb", "w") do |output_file|
        input_file.each_line do |line|
          output_file.write(line) unless line.strip.empty? # 空行以外を書き込み
        end
      end
    end
    FileUtils.cp("#{__dir__}/db/fixed_thing.erb", "#{OPENHAB_PATH}/things/#{data['thingID']}.things")
  end
  File.delete("#{__dir__}/db/created_thing.erb")
  File.delete("#{__dir__}/db/fixed_thing.erb")
end

def delete_things(excel_things)
  xlsx = Roo::Excelx.new("#{__dir__}/db/excel/#{excel_things}") # Excelファイルを指定
  variables = xlsx.row(1)
  (2..xlsx.last_row).each do |row_number|
    values = xlsx.row(row_number)
    data = {}
    variables.each_with_index do |variable, index|
      data[variable] = values[index] # Excelの1行目とn行目を対応付ける
    end
    File.delete("#{OPENHAB_PATH}/things/#{data['thingID']}.things")
  end
end


def post_items(excel_items, items_erb)
  xlsx = Roo::Excelx.new("#{__dir__}/db/excel/#{excel_items}") # Excelファイルを指定
  variables = xlsx.row(1)
  (2..xlsx.last_row).each do |row_number|
    values = xlsx.row(row_number)
    data = {}
    variables.each_with_index do |variable, index|
      data[variable] = values[index] # Excelの1行目とn行目を対応付ける
    end
    erb_template = ERB.new(items_erb) # テンプレート文字列を使用する
    output = erb_template.result(binding) # erbファイルを書き換える
    File.open("#{OPENHAB_PATH}/items/#{data['itemID']}.items", 'w') { |file| file.write(output) } # 新しいファイルにoutputでの変更を書き換える
  end
end

def delete_items(excel_items)
  xlsx = Roo::Excelx.new("#{__dir__}/db/excel/#{excel_items}") # Excelファイルを指定
  variables = xlsx.row(1)
  (2..xlsx.last_row).each do |row_number|
    values = xlsx.row(row_number)
    data = {}
    variables.each_with_index do |variable, index|
        data[variable] = values[index] # Excelの1行目とn行目を対応付ける
    end

    File.delete("#{OPENHAB_PATH}/items/#{data['itemID']}.items")
  end
end





get '/' do
  erb :index
end

get '/doc/habitatx.pdf' do
  send_file File.join(settings.root, 'doc', 'habitatx.pdf'), type: 'application/pdf'
end




# get '/things' do
get '/things' do
  @things = get_things(THINGS_FILE_PATH)
  erb :'things/index'
end

get '/things/new' do
  @template = Code.all
  erb :'things/new'
end

# get '/things/:id' do
post '/things' do
  @template = Datafile.all
  title_things = params[:title_things]
  template_things = params[:template_things]

  things = get_things(THINGS_FILE_PATH)
  if things.empty?
    id = '1' # もしくは適切なデフォルトのIDを設定
  else
    id = (things.keys.map(&:to_i).max + 1).to_s
  end
  things[id] = { 'title_things' => title_things, 'excel_things' => excel_things, 'things_erb' => things_erb }
  set_things(THINGS_FILE_PATH, things)

  things_template = Code.find_by(things_erb)
  things_content = things_template["content"]
  post_things(excel_things, things_content)

  redirect '/things'
end


get '/things/:id' do
  things = get_things(THINGS_FILE_PATH)
  @title_things = things[params[:id]]['title_things']
  @excel_things = things[params[:id]]['excel_things']
  @things_erb = things[params[:id]]['things_erb']
  erb :'things/show'
end

get '/things/:id/edit' do
  @template = Code.all
  things = get_things(THINGS_FILE_PATH)
  @title_things = things[params[:id]]['title_things']
  @excel_things = things[params[:id]]['excel_things']
  @things_erb = things[params[:id]]['things_erb']
  erb :'/things/edit'
end

patch '/things/:id' do
  @template = Code.all
  title_things = params[:title_things]
  excel_things = params[:excel_things]
  things_erb = params[:things_erb]

  things = get_things(THINGS_FILE_PATH)
  @excel_things = things[params[:id]]['excel_things']
  things[params[:id]] = { 'title_things' => title_things, 'excel_things' => excel_things, 'things_erb' => things_erb }
  set_things(THINGS_FILE_PATH, things)

  things_template = Code.find_by(things_erb)
  things_content = things_template["content"]
  delete_things(@excel_things)
  post_things(excel_things, things_content)

  redirect "/things/#{params[:id]}"
end


delete '/things/:id' do
  things = get_things(THINGS_FILE_PATH)
  @excel_things = things[params[:id]]['excel_things']
  things.delete(params[:id])
  set_things(THINGS_FILE_PATH, things)

  delete_things(@excel_things)

  redirect '/things'
end









# get '/items' do
get '/items' do
  @items = get_items(ITEMS_FILE_PATH)
  erb :'items/index'
end

get '/items/new' do
  @template = Code.all
  erb :'items/new'
end

# get '/items/:id' do
post '/items' do
  @template = Code.all
  title_items = params[:title_items]
  excel_items = params[:excel_items]
  items_erb = params[:items_erb]

  items = get_items(ITEMS_FILE_PATH)
  if items.empty?
    id = '1' # もしくは適切なデフォルトのIDを設定
  else
    id = (items.keys.map(&:to_i).max + 1).to_s
  end
  items[id] = { 'title_items' => title_items, 'excel_items' => excel_items, 'items_erb' => items_erb}
  set_items(ITEMS_FILE_PATH, items)

  items_template = Code.find_by(items_erb)
  items_content = items_template["content"]
  post_items(excel_items, items_content)

  redirect '/items'
end


get '/items/:id' do
  items = get_items(ITEMS_FILE_PATH)
  @title_items = items[params[:id]]['title_items']
  @excel_items = items[params[:id]]['excel_items']
  @items_erb = items[params[:id]]['items_erb']
  erb :'items/show'
end

get '/items/:id/edit' do
  @template = Code.all
  items = get_items(ITEMS_FILE_PATH)
  @title_items = items[params[:id]]['title_items']
  @excel_items = items[params[:id]]['excel_items']
  @items_erb = items[params[:id]]['items_erb']
  erb :'/items/edit'
end

patch '/items/:id' do
  @template = Code.all
  title_items = params[:title_items]
  excel_items = params[:excel_items]
  items_erb = params[:items_erb]

  items = get_items(ITEMS_FILE_PATH)
  @excel_items = items[params[:id]]['excel_items']
  items[params[:id]] = { 'title_items' => title_items, 'excel_items' => excel_items, 'items_erb' => items_erb }
  set_items(ITEMS_FILE_PATH, items)

  items_template = Code.find_by(items_erb)
  items_content = items_template["content"]
  delete_items(@excel_items)
  post_items(excel_items, items_content)

  redirect "/items/#{params[:id]}"
end


delete '/items/:id' do
  items = get_items(ITEMS_FILE_PATH)
  @excel_items = items[params[:id]]['excel_items']
  items.delete(params[:id])
  set_items(ITEMS_FILE_PATH, items)

  delete_items(@excel_items)

  redirect '/items'
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





# # get '/code' do
# get '/code' do
#   @code = Code.all
#   erb :'code/index'
# end

# get '/code/new' do
#   erb :'code/new'
# end

# # get '/code/:id' do
# post '/code' do
#   title_code = params[:title_code]
#   content = params[:content]
#   Code.create(title_code: title_code, content: content)

#   redirect '/code'
# end


# get '/code/:id' do
#   code = Code.find_by(id: params[:id])
#   @title_code = code["title_code"]
#   @content = code["content"]
#   erb :'code/show'
# end

# get '/code/:id/edit' do
#   code = Code.find_by(id: params[:id])
#   @title_code = code["title_code"]
#   @content = code["content"]
#   erb :'/code/edit'
# end

# patch '/code/:id' do
#   title_code = params[:title_code]
#   content = params[:content]
#   code = Code.find_by(id: params[:id])
#   return unless code
#   code.update(title_code: title_code, content: content)

#   redirect "/code/#{params[:id]}"
# end


# delete '/code/:id' do
#   code = Code.find_by(id: params[:id])
#   return unless code

#   code.destroy
#   redirect '/code'
# end



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

  file_data = File.binread("#{__dir__}/db/excel/#{table}")

  selected_template = Template.find_by(title_template: title_template)
  template_id = selected_template["id"]

  Datafile.create(title_datafile: title_datafile, table: file_data, template_id: template_id)

  redirect '/datafile'
end

get '/datafile/:id/download' do
  datafile = Datafile.find(params[:id])
  table_data = datafile["table"]
  File.open("#{__dir__}/db/excel/file/nomlab_member.xlsx", 'wb') do |file|
    file.write(table_data)
  end
  redirect "/datafile/#{params[:id]}"
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
  title_datafile = params[:title_datafile]
  table = params[:table]
  title_template = params[:title_template]
  file_data = File.binread("#{__dir__}/db/excel/#{excel}")

  selected_template = Template.find_by(title_template: title_template)
  template_id = selected_template["id"]

  datafile = Datafile.find_by(id: params[:id])
  return unless datafile
  datafile.title_datafile = excel
  datafile.table = file_data
  datafile.template_id = template_id
  datafile.save
  redirect "/datafile/#{params[:id]}"
end


delete '/datafile/:id' do
  datafile = Datafile.find_by(id: params[:id])
  return unless datafile

  datafile.destroy
  redirect '/datafile'
end



# # get '/template' do
# get '/template' do
#   @template = Datafile.all
#   erb :'template/index'
# end

# get '/template/new' do
#   @codes = Code.all
#   erb :'template/new'
# end

# # get '/template/:id' do
# post '/template' do
#   @codes = Code.all
#   excel = params[:excel]
#   codes_title = params[:codes_title]

#   file_data = File.binread("#{__dir__}/db/excel/#{excel}")

#   selected_code = Code.find_by(title_code: codes_title)
#   code_id = selected_code["id"]

#   Datafile.create(title_template: excel, excel: file_data, codes_id: code_id)

#   redirect '/template'
# end

# get '/template/:id/download' do
#   template = Datafile.find(params[:id])
#   excel_data = template["excel"]
#   File.open("#{__dir__}/db/excel/file/nomlab_member.xlsx", 'wb') do |file|
#     file.write(excel_data)
#   end
#   redirect "/template/#{params[:id]}"
# end


# get '/template/:id' do
#   template = Datafile.find_by(id: params[:id])
#   @excel = template["title_template"]
#   codes_id = template["codes_id"]
#   code_template = Code.find_by(id: codes_id)
#   @code = code_template["content"]
#   erb :'template/show'
# end

# get '/template/:id/edit' do
#   @codes = Code.all
#   template = Datafile.find_by(id: params[:id])
#   @excel = template["title_template"]
#   @codes_id = template["codes_id"]
#   erb :'/template/edit'
# end


# patch '/template/:id' do
#   @codes = Code.all
#   excel = params[:excel]
#   codes_title = params[:codes_title]
#   file_data = File.binread("#{__dir__}/db/excel/#{excel}")

#   selected_code = Code.find_by(title_code: codes_title)
#   code_id = selected_code["id"]

#   datafile = Datafile.find_by(id: params[:id])

#   return unless datafile
#   datafile.title_template = excel
#   datafile.excel = file_data
#   datafile.codes_id = code_id
#   datafile.save
#   redirect "/template/#{params[:id]}"
# end


# delete '/template/:id' do
#   template = Datafile.find_by(id: params[:id])
#   return unless template

#   template.destroy
#   redirect '/template'
# end