require 'sinatra'
require 'sinatra/reloader'
require 'json'
require 'roo'
require 'erb'
require 'fileutils'
require 'pg'

THINGS_FILE_PATH = 'src/db/things.json'
ITEMS_FILE_PATH = 'src/db/items.json'
OPENHAB_PATH = '/etc/openhab'

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



def conn
  @conn ||= PG.connect(dbname: 'postgres', user: 'habitatx', password: 'habitatX')
end

configure do
  result = conn.exec("SELECT * FROM information_schema.tables WHERE table_name = 'template'")
  conn.exec('CREATE TABLE template (id serial, title varchar(255), content text)') if result.values.empty?
end

def read_template_all
  result = conn.exec('SELECT * FROM template')
  
  if result.num_tuples.zero?
    [] # 空の場合は空の配列を返す
  else
    result
  end
end


def read_template_by_id(id)
  result = conn.exec_params('SELECT * FROM template WHERE id = $1;', [id])
  result.tuple_values(0)
end

def read_template_by_title(title)
  result = conn.exec_params('SELECT * FROM template WHERE title = $1', [title] )
  result.tuple_values(0)
end



def post_template(title, content)
  conn.exec_params('INSERT INTO template(title, content) VALUES ($1, $2);', [title, content])
end

def edit_template(title, content, id)
  conn.exec_params('UPDATE template SET title = $1, content = $2 WHERE id = $3;', [title, content, id])
end

def delete_template(title, id)
  conn.exec_params('DELETE FROM template WHERE id = $1;', [id])
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
  @template = read_template_all
  erb :'things/new'
end

# get '/things/:id' do
post '/things' do
  @template = read_template_all
  title_things = params[:title_things]
  excel_things = params[:excel_things]
  things_erb = params[:things_erb]

  things = get_things(THINGS_FILE_PATH)
  if things.empty?
    id = '1' # もしくは適切なデフォルトのIDを設定
  else
    id = (things.keys.map(&:to_i).max + 1).to_s
  end
  things[id] = { 'title_things' => title_things, 'excel_things' => excel_things, 'things_erb' => things_erb }
  set_things(THINGS_FILE_PATH, things)

  things_template = read_template_by_title(things_erb)
  things_content = things_template[2]
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
  @template = read_template_all
  things = get_things(THINGS_FILE_PATH)
  @title_things = things[params[:id]]['title_things']
  @excel_things = things[params[:id]]['excel_things']
  @things_erb = things[params[:id]]['things_erb']
  erb :'/things/edit'
end

patch '/things/:id' do
  @template = read_template_all
  title_things = params[:title_things]
  excel_things = params[:excel_things]
  things_erb = params[:things_erb]

  things = get_things(THINGS_FILE_PATH)
  @excel_things = things[params[:id]]['excel_things']
  things[params[:id]] = { 'title_things' => title_things, 'excel_things' => excel_things, 'things_erb' => things_erb }
  set_things(THINGS_FILE_PATH, things)

  things_template = read_template_by_title(things_erb)
  things_content = things_template[2]
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
  @template = read_template_all
  erb :'items/new'
end

# get '/items/:id' do
post '/items' do
  @template = read_template_all
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

  items_template = read_template_by_title(items_erb)
  items_content = items_template[2]
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
  @template = read_template_all
  items = get_items(ITEMS_FILE_PATH)
  @title_items = items[params[:id]]['title_items']
  @excel_items = items[params[:id]]['excel_items']
  @items_erb = items[params[:id]]['items_erb']
  erb :'/items/edit'
end

patch '/items/:id' do
  @template = read_template_all
  title_items = params[:title_items]
  excel_items = params[:excel_items]
  items_erb = params[:items_erb]

  items = get_items(ITEMS_FILE_PATH)
  @excel_items = items[params[:id]]['excel_items']
  items[params[:id]] = { 'title_items' => title_items, 'excel_items' => excel_items, 'items_erb' => items_erb }
  set_items(ITEMS_FILE_PATH, items)

  items_template = read_template_by_title(items_erb)
  items_content = items_template[2]
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
  @template = read_template_all
  erb :'template/index'
end

get '/template/new' do
  erb :'template/new'
end

# get '/template/:id' do
post '/template' do
  title = params[:title]
  content = params[:content]
  post_template(title, content)

  redirect '/template'
end


get '/template/:id' do
  template = read_template_by_id(params[:id])
  @title = template[1]
  @content = template[2]
  erb :'template/show'
end

get '/template/:id/edit' do
  template = read_template_by_id(params[:id])
  @title = template[1]
  @content = template[2]
  erb :'/template/edit'
end

patch '/template/:id' do
  title = params[:title]
  content = params[:content]

  edit_template(title, content, params[:id])

  redirect "/template/#{params[:id]}"
end


delete '/template/:id' do
  template = read_template_by_id(params[:id])
  @title = template[1]

  delete_template(@title, params[:id])

  redirect '/template'
end