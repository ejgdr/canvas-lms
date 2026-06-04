# frozen_string_literal: true

class CreateDiscussionQuestionDismissals < ActiveRecord::Migration[7.1]
  tag :predeploy

  def change
    create_table :discussion_question_dismissals do |t|
      t.references :discussion_entry, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true, index: false

      t.timestamps

      t.index %i[discussion_entry_id user_id], unique: true, name: "index_discussion_question_dismissals_entry_user_uniqueness"
    end
  end
end