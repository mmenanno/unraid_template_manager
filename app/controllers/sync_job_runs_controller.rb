# frozen_string_literal: true

class SyncJobRunsController < ApplicationController
  def index
    @running_jobs = SyncJobRun.running.recent.limit(10)
    @recent_jobs = SyncJobRun.recent.limit(20)
    @failed_jobs = SyncJobRun.failed.recent.limit(10)
  end

  def show
    @job_run = SyncJobRun.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to(sync_job_runs_path, alert: t("sync_job_runs.not_found"))
  end
end
