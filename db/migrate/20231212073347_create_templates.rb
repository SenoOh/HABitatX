class CreateTemplates < ActiveRecord::Migration[7.1]
  def change
    create_table :templates do |t|
      t.string :title_template
      t.text :content
      t.text :basename
      t.text :file_type
      t.timestamps
    end
  end
end