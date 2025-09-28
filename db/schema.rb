# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_09_28_233950) do
  create_table "template_comparisons", force: :cascade do |t|
    t.integer "local_template_id", null: false
    t.integer "community_template_id", null: false
    t.string "status", default: "pending", null: false
    t.json "user_choices"
    t.json "differences"
    t.datetime "last_compared_at"
    t.datetime "applied_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["community_template_id"], name: "index_template_comparisons_on_community_template_id"
    t.index ["last_compared_at"], name: "index_template_comparisons_on_last_compared_at"
    t.index ["local_template_id", "community_template_id"], name: "index_template_comparisons_on_template_pair", unique: true
    t.index ["local_template_id"], name: "index_template_comparisons_on_local_template_id"
    t.index ["status"], name: "index_template_comparisons_on_status"
  end

  create_table "template_configs", force: :cascade do |t|
    t.integer "template_id", null: false
    t.string "name", null: false
    t.string "config_type", null: false
    t.string "target"
    t.string "default_value"
    t.string "mode"
    t.text "description"
    t.boolean "required", default: false
    t.string "display", default: "always"
    t.integer "order_index", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["config_type"], name: "index_template_configs_on_config_type"
    t.index ["template_id", "name"], name: "index_template_configs_on_template_id_and_name", unique: true
    t.index ["template_id"], name: "index_template_configs_on_template_id"
  end

  create_table "templates", force: :cascade do |t|
    t.string "name", null: false
    t.string "repository", null: false
    t.string "network"
    t.string "category"
    t.string "banner"
    t.string "webui"
    t.text "description"
    t.text "xml_content", null: false
    t.string "local_path"
    t.string "status", default: "active", null: false
    t.string "source", null: false
    t.string "template_version"
    t.datetime "last_updated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_templates_on_name"
    t.index ["repository", "source"], name: "index_templates_on_repository_and_source", unique: true
    t.index ["repository"], name: "index_templates_on_repository"
    t.index ["source"], name: "index_templates_on_source"
    t.index ["status"], name: "index_templates_on_status"
  end

  add_foreign_key "template_comparisons", "templates", column: "community_template_id"
  add_foreign_key "template_comparisons", "templates", column: "local_template_id"
  add_foreign_key "template_configs", "templates"
end
