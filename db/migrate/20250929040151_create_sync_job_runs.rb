# frozen_string_literal: true

class CreateSyncJobRuns < ActiveRecord::Migration[8.0]
  def change
    create_table(:sync_job_runs) do |t|
      t.string(:job_type, null: false)
      t.string(:status, null: false, default: "running")
      t.datetime(:started_at, null: false)
      t.datetime(:completed_at)
      t.text(:results)
      t.text(:error_message)

      t.timestamps
    end

    add_index(:sync_job_runs, :job_type)
    add_index(:sync_job_runs, :status)
    add_index(:sync_job_runs, :started_at)
  end
end
