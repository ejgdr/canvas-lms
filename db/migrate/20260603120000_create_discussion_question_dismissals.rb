# frozen_string_literal: true

class CreateDiscussionQuestionDismissals < ActiveRecord::Migration[7.1]
  tag :predeploy

  def change
    create_table :discussion_question_dismissals do |t|
      t.references :discussion_entry, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end