# frozen_string_literal: true

class SyncJobRun < ApplicationRecord
  validates :job_type, presence: true, inclusion: { in: ["local_sync", "community_sync"] }
  validates :status, presence: true, inclusion: { in: ["running", "completed", "failed"] }
  validates :started_at, presence: true

  scope :recent, -> { order(started_at: :desc) }
  scope :running, -> { where(status: "running") }
  scope :completed, -> { where(status: "completed") }
  scope :failed, -> { where(status: "failed") }

  class << self
    def create_for_job(job_type)
      create!(
        job_type: job_type,
        status: "running",
        started_at: Time.current,
      )
    end
  end

  def complete!(results = {})
    update!(
      status: "completed",
      completed_at: Time.current,
      results: results.to_json,
    )
  end

  def fail!(error_message)
    update!(
      status: "failed",
      completed_at: Time.current,
      error_message: error_message,
    )
  end

  def duration
    return unless started_at

    end_time = completed_at || Time.current
    end_time - started_at
  end

  def duration_text
    return "Running..." unless completed_at
    return "< 1 second" if duration < 1

    "#{duration.round(1)} seconds"
  end

  def parsed_results
    return {} if results.blank?

    JSON.parse(results)
  rescue JSON::ParserError
    {}
  end

  def running?
    status == "running"
  end

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end
end
