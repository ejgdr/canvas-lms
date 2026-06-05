# frozen_string_literal: true

class CreateDiscussionTopicSummaryReports < ActiveRecord::Migration[7.1]
  tag :predeploy

  def change
    create_table :discussion_topic_summary_reports do |t|
      t.references :discussion_topic_summary, null: false, foreign_key: true, index: true
      t.references :user, null: false, foreign_key: true, index: false
      t.string :reason, null: false
      t.string :comment, limit: 500
      t.string :reporter_role, null: false

      t.timestamps
    end
  end
end
